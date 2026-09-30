import AppKit
import AshotCore
import CoreImage
import CoreMedia
import ScreenCaptureKit
import SwiftUI

// Mutable state is private and confined to queue. ScreenCaptureKit delivers frames on this queue.
final class LongReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
  let queue = DispatchQueue(label: "Ashot.long.processing", qos: .userInitiated)
  let context = CIContext(options: [.cacheIntermediates: false])
  private var accumulator = StitchAccumulator()
  private var paused = false
  private var stopped = false
  private var crop = CGRect.zero
  private var windowSize = CGSize.zero
  private var pixelsPerPoint = CGSize(width: 1, height: 1)
  private var onUpdate: (@Sendable (Int, Int, CGImage?) -> Void)?
  private var onError: (@Sendable (String) -> Void)?
  func configure(
    update: @escaping @Sendable (Int, Int, CGImage?) -> Void,
    error: @escaping @Sendable (String) -> Void
  ) {
    queue.async {
      self.onUpdate = update
      self.onError = error
    }
  }
  /// Frames arrive as the whole window, so the selected region is cut out here.
  /// Ordered on `queue`, which is also the stream's sample queue, so this lands
  /// before the first frame.
  func setCrop(_ rect: CGRect, windowSize: CGSize) {
    queue.async {
      self.crop = rect
      self.windowSize = windowSize
    }
  }
  func setPaused(_ value: Bool) { queue.async { self.paused = value } }
  func stop() { queue.async { self.stopped = true } }
  func finish(_ completion: @escaping @Sendable (Result<CapturedImage, Error>) -> Void) {
    queue.async {
      self.stopped = true
      completion(
        Result {
          CapturedImage(image: try self.accumulator.result(), pixelsPerPoint: self.pixelsPerPoint)
        })
    }
  }
  func stream(
    _ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType
  ) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard type == .screen, !paused, !stopped, buffer.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
        as? [[SCStreamFrameInfo: Any]], let status = attachments.first?[.status] as? Int,
      status == SCFrameStatus.complete.rawValue, let pixel = buffer.imageBuffer
    else { return }
    let ci = CIImage(cvPixelBuffer: pixel)
    guard let frame = context.createCGImage(ci, from: ci.extent) else { return }
    acceptFrame(frame)
  }
  /// Shared frame path for live buffers and image-level regression checks.
  func acceptFrame(_ frame: CGImage) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard !paused, !stopped else { return }
    guard let image = Self.region(of: frame, crop: crop, windowSize: windowSize) else {
      paused = true
      onError?("采集到的画面与所选区域不匹配。请取消后重新框选。")
      return
    }
    do {
      let match = try accumulator.accept(image)
      // Only accepted frames can update output metadata; rejected resized frames
      // must not alter the resolution of the already accumulated image.
      pixelsPerPoint = CGSize(
        width: CGFloat(frame.width) / windowSize.width,
        height: CGFloat(frame.height) / windowSize.height)
      recordFrame()
      if case .append = match {
        let result = try accumulator.result()
        let preview = Self.preview(result)
        onUpdate?(accumulator.height, accumulator.frameCount, preview)
      }
    } catch {
      recordFrame()
      paused = true
      let text: String
      switch error {
      case StitchError.limit: text = "已达到图片容量上限，请结束并保存已有部分。"
      case StitchError.ambiguous: text = "内容重复，无法确认拼接位置。请返回上一位置后重试。"
      default: text = "暂未对齐。可能滚动太快、出现动态内容或窗口变化。请返回上一位置后重试。"
      }
      onError?(text)
    }
  }
  /// Per-frame matcher telemetry: without the candidate shifts and their errors a
  /// "暂未对齐" failure cannot be told apart from a wrong match after the fact.
  private func recordFrame() {
    var fields: [String: Any] = ["height": accumulator.height, "frames": accumulator.frameCount]
    if let r = accumulator.lastReport {
      fields["same"] = r.sameError
      fields["bestShift"] = r.bestShift
      fields["bestError"] = r.bestError
      fields["runnerShift"] = r.runnerUpShift
      fields["runnerError"] = r.runnerUpError
      if let verify = r.verifyError { fields["verify"] = verify }
      if let matched = r.matched {
        fields["outcome"] = matched == .unchanged ? "unchanged" : "append"
      } else {
        fields["outcome"] = r.rejected.map { "\($0)" } ?? "?"
      }
    }
    record("longFrame", fields)
  }
  static func region(of frame: CGImage, crop: CGRect, windowSize: CGSize) -> CGImage? {
    guard
      let pixels = Geometry.pixelRect(
        crop, logicalSize: windowSize,
        pixelSize: CGSize(width: frame.width, height: frame.height))
    else { return nil }
    return frame.cropping(to: pixels)
  }
  static func preview(_ image: CGImage) -> CGImage? {
    let w = min(image.width, 240)
    let h = min(Int(Double(image.height) * Double(w) / Double(image.width)), 1800)
    guard
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
  }
}
@MainActor
final class LongCaptureController: NSObject, ObservableObject, SCStreamDelegate {
  let service: CaptureService, snapshot: CaptureSnapshot, rect: CGRect
  let receiver = LongReceiver()
  var stream: SCStream?
  var panel: NSPanel?
  var onFinish: ((CapturedImage?) -> Void)?
  @Published var height = 0
  @Published var count = 0
  @Published var preview: CGImage?
  @Published var message = "正在准备…"
  @Published var paused = false
  @Published var finishing = false
  var ended = false
  var streamRunning = false
  var watchedWindow: SCWindow?
  var monitor: Timer?
  init(service: CaptureService, snapshot: CaptureSnapshot, rect: CGRect) {
    self.service = service
    self.snapshot = snapshot
    self.rect = rect
  }
  func start() {
    let p = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 530),
      styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    p.title = "Ashot · 长截图"
    p.level = .floating
    p.isReleasedWhenClosed = false
    p.contentView = NSHostingView(rootView: LongPanel(controller: self))
    let globalX = snapshot.screen.frame.minX + rect.maxX + 12
    p.setFrameOrigin(
      CGPoint(
        x: min(globalX, snapshot.screen.frame.maxX - 312),
        y: max(snapshot.screen.frame.minY + 30, snapshot.screen.frame.maxY - rect.minY - 540)))
    p.orderFront(nil)
    panel = p
    receiver.configure(
      update: { [weak self] height, count, preview in
        DispatchQueue.main.async {
          guard let self, !self.ended else { return }
          self.height = height
          self.count = count
          self.preview = preview
          self.message = "缓慢向下滚动，完成后点击结束"
          record("longAppend", ["height": height, "frames": count])
        }
      },
      error: { [weak self] message in
        DispatchQueue.main.async {
          guard let self, !self.ended else { return }
          self.paused = true
          self.message = message
          record("longPaused", ["message": message, "height": self.height])
        }
      })
    Task {
      do {
        // Use the same window geometry as the frozen screen the user selected.
        // Querying after Ashot's overlay activates can return Stage Manager
        // thumbnails instead of the original document window bounds.
        let content = snapshot.content
        guard !ended else { return }
        // SelectionView and ScreenCaptureKit use top-left logical points.
        // NSScreen.frame is AppKit y-up and must not be mixed with SCWindow.frame.
        let container = snapshot.display.frame
        let globalCenter = Geometry.globalPoint(
          CGPoint(x: rect.midX, y: rect.midY), in: container)
        watchedWindow = content.windows.first {
          $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
            && $0.windowLayer == 0 && $0.frame.contains(globalCenter)
        }
        let globalRect = Geometry.globalRect(rect, in: container)
        guard let target = watchedWindow, target.frame.width > 0, target.frame.height > 0,
          let localRect = Geometry.windowLocalRect(global: globalRect, window: target.frame)
        else {
          message = "请框选单个窗口内的可滚动内容。当前区域超出窗口，请取消后重选。"
          paused = true
          record(
            "longNoTarget",
            [
              "hasWindow": watchedWindow != nil, "globalY": globalRect.minY,
              "containerMaxY": container.maxY,
            ])
          return
        }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        // ScreenCaptureKit ignores sourceRect for single-window capture and always
        // delivers the window's full bounds, so the region is cropped per frame.
        let windowSize = CGSize(width: target.frame.width, height: target.frame.height)
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((windowSize.width * scale).rounded())
        config.height = Int((windowSize.height * scale).rounded())
        receiver.setCrop(localRect, windowSize: windowSize)
        // The capture overlay activated Ashot. Return input to the selected
        // document so Stage Manager keeps it expanded and wheel events reach it.
        if let owner = target.owningApplication,
          let application = NSRunningApplication(processIdentifier: owner.processID)
        {
          NSApp.yieldActivation(to: application)
          let accepted = application.activate(from: .current, options: [])
          record("longFocus", ["accepted": accepted])
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
        self.stream = stream
        try await stream.startCapture()
        guard !ended else {
          try await stream.stopCapture()
          return
        }
        message = "缓慢向下滚动，完成后点击结束"
        streamRunning = true
        record(
          "longStart",
          [
            "frameWidth": config.width, "frameHeight": config.height,
            "cropX": localRect.minX, "cropY": localRect.minY, "cropWidth": localRect.width,
            "cropHeight": localRect.height,
            "window": target.owningApplication?.applicationName ?? "",
          ])
        startMonitor()
      } catch {
        message = "无法开始采集：\(error.localizedDescription)"
        paused = true
        record("longStartError", ["message": error.localizedDescription])
      }
    }
  }
  func startMonitor() {
    monitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, !self.ended, !self.paused, let target = self.watchedWindow else { return }
        do {
          let content = try await self.service.content()
          guard let now = content.windows.first(where: { $0.windowID == target.windowID }) else {
            self.pauseForTarget()
            return
          }
          // Background Stage Manager thumbnails have transformed frame bounds,
          // while the desktop-independent stream still captures the document.
          // A genuine user move/resize activates its owner before changing bounds.
          let ownerHasFocus =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
            == target.owningApplication?.processID
          if ownerHasFocus, now.frame != target.frame { self.pauseForTarget() }
        } catch { self.pauseForTarget() }
      }
    }
  }
  func pauseForTarget() {
    paused = true
    message = "目标窗口已变化，请恢复原位置后重试，或结束保存已有部分。"
    receiver.setPaused(true)
    record("longTargetChanged")
  }
  func retry() {
    guard !ended, streamRunning else { return }
    receiver.setPaused(false)
    paused = false
    message = "重新检查对齐，请从上一位置缓慢向下滚动"
    record("longRetry")
  }
  func finish() {
    guard !ended, !finishing else { return }
    finishing = true
    monitor?.invalidate()
    monitor = nil
    Task { [self] in
      if let stream {
        do { try await stream.stopCapture() } catch {
          record("streamStopError", ["message": error.localizedDescription])
        }
      }
      streamRunning = false
      receiver.finish { [weak self] result in
        DispatchQueue.main.async {
          guard let self, !self.ended else { return }
          switch result {
          case .success(let image):
            self.end(image)
            record(
              "longFinish",
              [
                "width": image.image.width, "height": image.image.height,
                "scaleX": image.pixelsPerPoint.width, "scaleY": image.pixelsPerPoint.height,
              ])
          case .failure(let error):
            self.finishing = false
            self.paused = true
            self.message = "图片生成失败，已保留采集数据。请重试结束或取消：\(error.localizedDescription)"
            record("longExportError", ["message": error.localizedDescription])
          }
        }
      }
    }
  }
  func cancel() {
    guard !ended else { return }
    ended = true
    monitor?.invalidate()
    monitor = nil
    panel?.close()
    panel = nil
    receiver.stop()
    Task {
      if let stream { try? await stream.stopCapture() }
      self.stream = nil
    }
    onFinish?(nil)
    record("longCancel")
  }
  func end(_ image: CapturedImage?) {
    guard !ended else { return }
    ended = true
    panel?.close()
    panel = nil
    stream = nil
    onFinish?(image)
  }
  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    Task { @MainActor in
      guard !self.ended else { return }
      self.paused = true
      self.streamRunning = false
      self.receiver.setPaused(true)
      self.message = "采集已中断：\(error.localizedDescription)。可结束保留已有部分。"
      record("longStreamError")
    }
  }
}
struct LongPanel: View {
  @ObservedObject var controller: LongCaptureController
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(controller.paused ? "已暂停" : "长截图").font(.title2.bold())
      Text("累计 \(controller.height) px · \(controller.count) 帧").monospacedDigit()
      Text(controller.message).font(.callout).foregroundStyle(
        controller.paused ? .orange : .secondary)
      ScrollView {
        if let image = controller.preview {
          Image(
            nsImage: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
          ).resizable().scaledToFit()
        }
      }.frame(maxHeight: 320)
      HStack {
        Button("结束并编辑") { controller.finish() }.disabled(
          controller.height == 0 || controller.finishing)
        if controller.paused {
          Button("重试") { controller.retry() }.disabled(!controller.streamRunning)
        }
        Button("取消") { controller.cancel() }
      }
      Text("仅支持静态内容、竖直向下。请勿移动窗口。").font(.caption).foregroundStyle(.secondary)
    }.padding(16).frame(width: 300, height: 530)
  }
}
