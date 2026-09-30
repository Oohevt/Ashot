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
  /// One frozen snapshot per connected display, the display under the mouse first.
  /// A display that cannot be captured is skipped; none captured throws.
  func screenshots() async throws -> [CaptureSnapshot] {
    let content = try await self.content()
    let mouse = NSEvent.mouseLocation
    let screens = NSScreen.screens.sorted { lhs, _ in NSMouseInRect(mouse, lhs.frame, false) }
    var result: [CaptureSnapshot] = []
    var firstError: Error?
    for screen in screens {
      do { result.append(try await capture(screen, content: content)) } catch {
        firstError = firstError ?? error
      }
    }
    if result.isEmpty { throw firstError ?? CocoaError(.coderInvalidValue) }
    return result
  }
  private func capture(_ screen: NSScreen, content: SCShareableContent) async throws
    -> CaptureSnapshot
  {
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
}
final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
final class SelectionView: NSView {
  let snapshot: CaptureSnapshot
  let candidates: [SelectionCandidate]
  var onCapture: ((CapturedImage) -> Void)?
  var onCopy: ((CapturedImage) -> Void)?
  var onSave: ((CapturedImage) -> Void)?
  var onLong: ((CGRect) -> Void)?
  var onCancel: (() -> Void)?
  /// Fired when a press starts a new selection here, so other displays drop theirs.
  var onBegin: (() -> Void)?
  var start: CGPoint?
  var selection: CGRect?
  var toolbar: NSView?
  var sizeLabel: NSView?
  var hover: SelectionCandidate?
  var downCandidate: SelectionCandidate?
  var tracking: NSTrackingArea?
  /// Set while a locked selection is being moved or resized by its handles.
  private var adjust: (handle: SelectionAdjust.Handle, from: CGPoint, origin: CGRect)?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  /// The overlay appears while Ashot is still becoming the frontmost app; without
  /// this, a click landing in that window only activates and never reaches mouseDown.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  init(snapshot: CaptureSnapshot, candidates: [SelectionCandidate] = []) {
    self.snapshot = snapshot
    self.candidates = candidates
    super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if tracking == nil {
      let area = NSTrackingArea(
        rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
      addTrackingArea(area)
      tracking = area
    }
  }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

  // MARK: Drawing
  private func revealed(_ rect: CGRect) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: rect).addClip()
    NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds)
    NSGraphicsContext.restoreGraphicsState()
  }
  private func caption(_ text: String, in rect: CGRect) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
    ]
    let size = (text as NSString).size(withAttributes: attrs)
    let pill = CGRect(
      x: max(rect.minX + 6, rect.maxX - size.width - 18), y: max(rect.minY + 6, rect.maxY - 26),
      width: size.width + 12, height: 20)
    NSColor.black.withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
    (text as NSString).draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 3), withAttributes: attrs)
  }
  private func title(for kind: SelectionCandidate.Kind) -> String {
    switch kind {
    case .window: return "窗口"
    case .menuBar: return "菜单栏"
    case .dock: return "程序坞"
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds)
    NSColor.black.withAlphaComponent(0.35).setFill()
    bounds.fill()
    if selection == nil, let hover {
      revealed(hover.rect)
      NSColor.controlAccentColor.setStroke()
      let path = NSBezierPath(rect: hover.rect.insetBy(dx: 1, dy: 1))
      path.lineWidth = 2
      path.stroke()
      caption(title(for: hover.kind), in: hover.rect)
    }
    if let selection {
      revealed(selection)
      NSColor.controlAccentColor.setStroke()
      let path = NSBezierPath(rect: selection)
      path.lineWidth = 2
      path.stroke()
      if selection.width > 24, selection.height > 24 { drawHandles(selection) }
    }
  }
  private func drawHandles(_ r: CGRect) {
    let points = [
      CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
      CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
      CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
    ]
    for p in points {
      let dot = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
      NSColor.white.setFill()
      NSBezierPath(ovalIn: dot).fill()
      NSColor.controlAccentColor.setStroke()
      let ring = NSBezierPath(ovalIn: dot)
      ring.lineWidth = 1.5
      ring.stroke()
    }
  }

  // MARK: Mouse
  override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if let selection, let handle = SelectionAdjust.hit(p, rect: selection) {
      toolbar?.removeFromSuperview()
      toolbar = nil
      adjust = (handle, p, selection)
      return
    }
    onBegin?()
    clearSelection()
    start = p
    downCandidate = SmartSelectionGeometry.pick(at: p, candidates: candidates)
    hover = nil
    selection = nil
    needsDisplay = true
  }
  /// Drops the selection and its chrome; used when another display takes over.
  func clearSelection() {
    toolbar?.removeFromSuperview()
    toolbar = nil
    sizeLabel?.removeFromSuperview()
    sizeLabel = nil
    selection = nil
    adjust = nil
    needsDisplay = true
  }
  override func mouseMoved(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if let selection {
      cursor(for: SelectionAdjust.hit(p, rect: selection)).set()
      return
    }
    hover = SmartSelectionGeometry.pick(at: p, candidates: candidates)
    needsDisplay = true
  }
  private func cursor(for handle: SelectionAdjust.Handle?) -> NSCursor {
    switch handle {
    case .move: return .openHand
    case .n, .s: return .resizeUpDown
    case .e, .w: return .resizeLeftRight
    case .ne, .nw, .se, .sw: return .crosshair
    case nil: return .crosshair
    }
  }
  override func mouseDragged(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if let adjust {
      selection = SelectionAdjust.adjusted(
        adjust.origin, handle: adjust.handle, from: adjust.from, to: p, bounds: bounds)
      layoutChrome(toolbarVisible: false)
      needsDisplay = true
      return
    }
    guard let start else { return }
    hover = nil
    selection = CGRect(
      x: min(start.x, p.x), y: min(start.y, p.y), width: abs(start.x - p.x),
      height: abs(start.y - p.y)
    ).intersection(bounds)
    // Drag-vs-click is decided once: crossing the threshold on either axis
    // permanently drops the pressed candidate, so mouse-up can never fall
    // back to locking the window the press started in — not even after the
    // pointer returns near the start point.
    if let selection,
      selection.width > SmartSelectionGeometry.minimumDrag
        || selection.height > SmartSelectionGeometry.minimumDrag
    {
      downCandidate = nil
      layoutChrome(toolbarVisible: false)
    }
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    if let done = adjust {
      adjust = nil
      guard let selection else { return }
      presentToolbar()
      record(
        "selectionAdjust",
        [
          "handle": done.handle.rawValue, "x": selection.minX, "y": selection.minY,
          "width": selection.width, "height": selection.height,
        ])
      return
    }
    mouseDragged(with: event)
    guard
      let resolved = SmartSelectionGeometry.resolvedSelection(
        dragged: selection, candidate: downCandidate)
    else {
      sizeLabel?.removeFromSuperview()
      sizeLabel = nil
      return
    }
    selection = resolved.rect
    presentToolbar()
    record(
      "selection",
      [
        "x": resolved.rect.minX, "y": resolved.rect.minY, "width": resolved.rect.width,
        "height": resolved.rect.height,
        "pixelWidth": Int(snapshot.image.width), "pixelHeight": Int(snapshot.image.height),
        "source": resolved.kind?.rawValue ?? "drag",
      ])
  }

  // MARK: Toolbar
  private func hud(_ content: NSView, radius: CGFloat) -> NSVisualEffectView {
    let box = NSVisualEffectView()
    box.material = .hudWindow
    box.blendingMode = .withinWindow
    box.state = .active
    box.appearance = NSAppearance(named: .darkAqua)
    box.wantsLayer = true
    box.layer?.cornerRadius = radius
    box.layer?.masksToBounds = true
    box.layer?.borderWidth = 1
    box.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    content.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
      content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
      content.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
      content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
    ])
    box.frame.size = box.fittingSize
    return box
  }
  private func iconButton(
    _ symbol: String, _ tip: String, _ action: Selector, label: String? = nil
  ) -> NSButton {
    let button = ToolButton(symbol: symbol, label: label)
    button.target = self
    button.action = action
    button.toolTip = tip
    button.setAccessibilityLabel(tip)
    return button
  }
  func presentToolbar() {
    guard selection != nil else { return }
    toolbar?.removeFromSuperview()
    let divider = NSBox()
    divider.boxType = .separator
    divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
    divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
    let stack = NSStackView(views: [
      iconButton("doc.on.doc", "复制  W", #selector(copySelection)),
      iconButton("square.and.arrow.down", "保存  ⌘S", #selector(saveSelection)),
      iconButton("pencil.tip.crop.circle", "编辑标注  ↩", #selector(capture), label: "编辑"),
      iconButton("arrow.down.to.line.compact", "长截图：框选可滚动内容后，缓慢向下滚动", #selector(longCapture), label: "长截图"),
      divider,
      iconButton("xmark", "取消  Esc", #selector(cancel)),
    ])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .gravityAreas
    stack.spacing = 6
    let bar = hud(stack, radius: 10)
    addSubview(bar)
    toolbar = bar
    layoutChrome(toolbarVisible: true)
  }
  /// Places the size pill above the selection's top-left and the toolbar below its
  /// bottom-right, flipping to the other side or inside when the screen edge is near.
  private func layoutChrome(toolbarVisible: Bool) {
    guard let selection else { return }
    if sizeLabel == nil {
      let text = NSTextField(labelWithString: "")
      text.textColor = .white
      text.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
      let pill = hud(text, radius: 8)
      addSubview(pill)
      sizeLabel = pill
    }
    if let pill = sizeLabel, let text = pill.subviews.first as? NSTextField {
      text.stringValue = "\(Int(selection.width)) × \(Int(selection.height))"
      pill.frame.size = pill.fittingSize
      let above = selection.minY - pill.frame.height - 6
      pill.frame.origin = CGPoint(
        x: min(max(8, selection.minX), bounds.width - pill.frame.width - 8),
        y: above >= 8 ? above : selection.minY + 6)
    }
    guard toolbarVisible, let bar = toolbar else { return }
    let size = bar.frame.size
    let below = selection.maxY + 10
    var y = below
    if below + size.height > bounds.height - 8 {
      let above = selection.minY - size.height - 10
      y = above >= 8 ? above : selection.maxY - size.height - 10
    }
    bar.frame.origin = CGPoint(
      x: min(max(8, selection.maxX - size.width), bounds.width - size.width - 8), y: y)
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      cancel()
    } else if event.keyCode == 36 {
      capture()
    } else if event.keyCode == UInt16(kVK_ANSI_W) {
      copySelection()
    } else if event.keyCode == UInt16(kVK_ANSI_S), event.modifierFlags.contains(.command) {
      saveSelection()
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
  @objc func saveSelection() { if let image = croppedSelection() { onSave?(image) } }
  @objc func longCapture() { if let selection { onLong?(selection) } }
  @objc func cancel() { onCancel?() }
}

/// Toolbar button that draws its glyph and optional label itself, both centered on
/// the same midline; NSButton's own layout puts each SF Symbol at a different height.
final class ToolButton: NSButton {
  private let glyph: NSImage?
  private let text: NSAttributedString?
  private var hovering = false
  private static let glyphSize: CGFloat = 19
  init(symbol: String, label: String?) {
    glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        // Beside a label the glyph is sized to the text's height so both share top and bottom.
        NSImage.SymbolConfiguration(
          pointSize: label == nil ? 16 : 13, weight: .medium, scale: .medium)
          .applying(NSImage.SymbolConfiguration(paletteColors: [.white])))
    text = label.map {
      NSAttributedString(
        string: $0,
        attributes: [
          .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        ])
    }
    super.init(frame: .zero)
    isBordered = false
    title = ""
    addTrackingArea(
      NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: NSSize {
    NSSize(width: 14 + Self.glyphSize + (text.map { $0.size().width + 6 } ?? 0), height: 28)
  }
  override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
  override func draw(_ dirtyRect: NSRect) {
    if hovering || isHighlighted {
      NSColor.white.withAlphaComponent(isHighlighted ? 0.28 : 0.16).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    var x = 7.0
    if let glyph {
      let side = Self.glyphSize
      let box = CGRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
      let fit = glyph.size
      let scale = min(side / fit.width, side / fit.height, 1)
      let size = CGSize(width: fit.width * scale, height: fit.height * scale)
      let rect = CGRect(
        x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width,
        height: size.height)
      glyph.draw(in: rect)
      x += side + 6
    }
    if let text {
      // Centre the cap-height band, not the line box: the line box includes the
      // descender, which pushes the label below the glyph's midline.
      let font = NSFont.systemFont(ofSize: 13, weight: .medium)
      let baseline = bounds.midY - font.capHeight / 2
      text.draw(at: CGPoint(x: x, y: baseline + font.descender))
    }
  }
}
