import AppKit
import AshotCore

/// A screenshot pinned on top of everything, at the size and place it was taken.
/// Drag to move, scroll or pinch to resize, double-click / Esc / ⌘W / right-click → close.
final class PinWindow: NSWindow {
  let capture: CapturedImage
  init(capture: CapturedImage, frame: CGRect) {
    self.capture = capture
    super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = .floating
    isMovableByWindowBackground = true
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    contentView = PinView(capture: capture)
  }
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { close() }
  /// A borderless window has no close button, so the menu's ⌘W would only beep.
  override func performClose(_ sender: Any?) { close() }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
      event.charactersIgnoringModifiers == "w"
    {
      close()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  /// Resizes about the window's center, keeping the image's aspect ratio.
  func scale(by factor: CGFloat) {
    let aspect = capture.image.width > 0 ? CGFloat(capture.image.height) / CGFloat(capture.image.width) : 1
    let width = min(max(frame.width * factor, 48), 6000)
    let size = CGSize(width: width, height: width * aspect)
    setFrame(
      CGRect(
        x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width,
        height: size.height), display: true)
  }
}

final class PinView: NSView {
  let capture: CapturedImage
  init(capture: CapturedImage) {
    self.capture = capture
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 4
    layer?.masksToBounds = true
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
  }
  required init?(coder: NSCoder) { fatalError() }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSImage(cgImage: capture.image, size: bounds.size).draw(in: bounds)
  }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      window?.close()
    } else {
      window?.makeKey()
      super.mouseDown(with: event)
    }
  }
  override func scrollWheel(with event: NSEvent) {
    let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 4
    (window as? PinWindow)?.scale(by: 1 + delta * 0.01)
  }
  override func magnify(with event: NSEvent) {
    (window as? PinWindow)?.scale(by: 1 + event.magnification)
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = NSMenu()
    menu.addItem(withTitle: "复制", action: #selector(copyImage), keyEquivalent: "").target = self
    for (title, alpha) in [("不透明", 1.0), ("透明度 70%", 0.7), ("透明度 40%", 0.4)] {
      let item = NSMenuItem(title: title, action: #selector(setAlpha(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = alpha
      item.state = abs((window?.alphaValue ?? 1) - alpha) < 0.01 ? .on : .off
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(withTitle: "关闭  ⌘W", action: #selector(closePin), keyEquivalent: "").target = self
    return menu
  }
  @objc func copyImage() {
    try? ImageExport.copy(capture.image, pixelsPerPoint: capture.pixelsPerPoint)
  }
  @objc func setAlpha(_ sender: NSMenuItem) {
    window?.alphaValue = CGFloat((sender.representedObject as? Double) ?? 1)
  }
  @objc func closePin() { window?.close() }
}
