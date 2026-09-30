import AppKit
import AshotCore
import Carbon
import ScreenCaptureKit

struct CaptureSnapshot {
  let image: CGImage
  let display: SCDisplay
  let screen: NSScreen
  let content: SCShareableContent
  var pixelsPerPoint: CGSize {
    CGSize(
      width: CGFloat(image.width) / screen.frame.width,
      height: CGFloat(image.height) / screen.frame.height)
  }
}
/// Pixel data and its source resolution travel together through crop, edit and export.
struct CapturedImage {
  let image: CGImage
  let pixelsPerPoint: CGSize
}
@MainActor
final class CaptureService {
  func content() async throws -> SCShareableContent {
    try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
  }
  func filter(for display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
    SCContentFilter(
      display: display,
      excludingWindows: content.windows.filter {
        $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
      })
  }
  func screenshot() async throws -> CaptureSnapshot {
    let content = try await self.content()
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main!
    let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber)
      .uint32Value
    guard let display = content.displays.first(where: { $0.displayID == id }) else {
      throw CocoaError(.coderInvalidValue)
    }
    let filter = self.filter(for: display, content: content)
    let config = SCStreamConfiguration()
    config.width = Int(screen.frame.width * CGFloat(filter.pointPixelScale))
    config.height = Int(screen.frame.height * CGFloat(filter.pointPixelScale))
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: config)
    return CaptureSnapshot(image: image, display: display, screen: screen, content: content)
  }
  func windowImage(_ window: SCWindow) async throws -> CapturedImage {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
    config.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: config)
    return CapturedImage(
      image: image,
      pixelsPerPoint: CGSize(
        width: CGFloat(image.width) / window.frame.width,
        height: CGFloat(image.height) / window.frame.height))
  }
}
final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
final class SelectionView: NSView {
  let snapshot: CaptureSnapshot
  var onCapture: ((CapturedImage) -> Void)?
  var onCopy: ((CapturedImage) -> Void)?
  var onLong: ((CGRect) -> Void)?
  var onCancel: (() -> Void)?
  var start: CGPoint?
  var selection: CGRect?
  var toolbar: NSStackView?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  init(snapshot: CaptureSnapshot) {
    self.snapshot = snapshot
    super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ dirtyRect: NSRect) {
    NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds)
    NSColor.black.withAlphaComponent(0.35).setFill()
    bounds.fill()
    if let selection {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: selection).addClip()
      NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds)
      NSGraphicsContext.restoreGraphicsState()
      NSColor.controlAccentColor.setStroke()
      let path = NSBezierPath(rect: selection)
      path.lineWidth = 2
      path.stroke()
    }
  }
  override func mouseDown(with event: NSEvent) {
    toolbar?.removeFromSuperview()
    toolbar = nil
    start = convert(event.locationInWindow, from: nil)
    selection = nil
    needsDisplay = true
  }
  override func mouseDragged(with event: NSEvent) {
    guard let start else { return }
    let p = convert(event.locationInWindow, from: nil)
    selection = CGRect(
      x: min(start.x, p.x), y: min(start.y, p.y), width: abs(start.x - p.x),
      height: abs(start.y - p.y)
    ).intersection(bounds)
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    mouseDragged(with: event)
    guard let selection, selection.width > 8, selection.height > 8 else { return }
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.spacing = 8
    let size = NSTextField(labelWithString: "\(Int(selection.width)) × \(Int(selection.height)) pt")
    size.textColor = .white
    stack.addArrangedSubview(size)
    stack.addArrangedSubview(NSButton(title: "编辑截图", target: self, action: #selector(capture)))
    stack.addArrangedSubview(NSButton(title: "长截图", target: self, action: #selector(longCapture)))
    stack.addArrangedSubview(NSButton(title: "取消", target: self, action: #selector(cancel)))
    stack.frame = CGRect(
      x: min(max(12, selection.minX), bounds.width - 410),
      y: min(selection.maxY + 10, bounds.height - 44), width: 400, height: 32)
    addSubview(stack)
    toolbar = stack
    record(
      "selection",
      [
        "x": selection.minX, "y": selection.minY, "width": selection.width,
        "height": selection.height,
        "pixelWidth": Int(snapshot.image.width), "pixelHeight": Int(snapshot.image.height),
      ])
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      cancel()
    } else if event.keyCode == 36 {
      capture()
    } else if event.keyCode == UInt16(kVK_ANSI_W) {
      copySelection()
    } else {
      super.keyDown(with: event)
    }
  }
  func croppedSelection() -> CapturedImage? {
    guard let selection,
      let pixels = Geometry.pixelRect(
        selection, logicalSize: bounds.size,
        pixelSize: CGSize(width: snapshot.image.width, height: snapshot.image.height)),
      let image = snapshot.image.cropping(to: pixels)
    else { return nil }
    return CapturedImage(image: image, pixelsPerPoint: snapshot.pixelsPerPoint)
  }
  @objc func capture() { if let image = croppedSelection() { onCapture?(image) } }
  /// Confirms without opening the editor: copy to the pasteboard and return focus.
  @objc func copySelection() { if let image = croppedSelection() { onCopy?(image) } }
  @objc func longCapture() { if let selection { onLong?(selection) } }
  @objc func cancel() { onCancel?() }
}
