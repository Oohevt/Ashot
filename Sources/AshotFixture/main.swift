import AppKit
import ScreenCaptureKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = FixtureDelegate()
app.delegate = delegate
app.run()
final class FixtureDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  var dialog: NSPanel?
  var scroll: NSScrollView!
  var imageView: NSImageView!
  var dynamicView: NSView?
  let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
  func applicationDidFinishLaunching(_ notification: Notification) {
    window = NSWindow(
      contentRect: CGRect(x: 80, y: 80, width: 500, height: 640),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Ashot 测试文档"
    let path = root.appendingPathComponent("fixtures/article.png").path
    guard let image = NSImage(contentsOfFile: path) else {
      window.title = "未找到测试文档：\(path)"
      window.makeKeyAndOrderFront(nil)
      return
    }
    scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    let v = NSImageView(frame: CGRect(x: 0, y: 0, width: 500, height: 3840))
    v.image = image
    v.imageScaling = .scaleAxesIndependently
    imageView = v
    scroll.documentView = v
    window.contentView!.addSubview(scroll)
    scroll.contentView.scroll(to: CGPoint(x: 0, y: 3200))
    scroll.reflectScrolledClipView(scroll.contentView)
    let menu = NSMenu()
    let item = NSMenuItem()
    menu.addItem(item)
    let sub = NSMenu()
    item.submenu = sub
    for (title, action, key) in [
      ("文章", #selector(article), "1"), ("表格", #selector(table), "2"), ("代码", #selector(code), "3"),
      ("回到顶部", #selector(top), "t"), ("跳到底部", #selector(bottom), "b"),
      ("切换动态干扰", #selector(dynamic), "d"),
      ("恢复测试窗口", #selector(restoreLayout), "r"),
      ("独立对话框", #selector(toggleDialog), "j"),
    ] { sub.addItem(withTitle: title, action: action, keyEquivalent: key).target = self }
    app.mainMenu = menu
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(scroll)
    app.activate(ignoringOtherApps: true)
  }
  func load(_ kind: String) {
    imageView.image = NSImage(contentsOf: root.appendingPathComponent("fixtures/\(kind).png"))
    window.title = "Ashot 测试文档 · \(kind)"
    top()
  }
  @objc func article() { load("article") }
  @objc func table() { load("table") }
  @objc func code() { load("code") }
  @objc func top() {
    scroll.contentView.scroll(to: CGPoint(x: 0, y: 3200))
    scroll.reflectScrolledClipView(scroll.contentView)
  }
  @objc func restoreLayout() {
    window.collectionBehavior = [.moveToActiveSpace]
    window.setContentSize(CGSize(width:500,height:640))
    window.center()
    app.activate(ignoringOtherApps:true)
    window.makeKeyAndOrderFront(nil)
    top()
    if #available(macOS 14.4,*) {
      Task { @MainActor in
        do {
          let content=try await SCShareableContent.currentProcess
          let scWindow=content.windows.first{$0.windowID==UInt32(window.windowNumber)}
          let report:[String:Any] = [
            "appkitFrame":NSStringFromRect(window.frame),
            "captureKitFrame":scWindow.map{NSStringFromRect($0.frame)} ?? "missing",
            "screenFrame":window.screen.map{NSStringFromRect($0.frame)} ?? "missing",
            "windowId":window.windowNumber
          ]
          let dir=root.appendingPathComponent("evidence")
          try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
          try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("review-fixture-geometry.json"))
        } catch {NSLog("Fixture geometry: %@",error.localizedDescription)}
      }
    }
  }
  @objc func bottom() {
    scroll.contentView.scroll(to: CGPoint(x: 0, y: 0))
    scroll.reflectScrolledClipView(scroll.contentView)
  }
  /// A separate floating panel so hover-selection of an "independent dialog"
  /// can be exercised without touching the scrolled document window.
  @objc func toggleDialog() {
    if let dialog {
      dialog.close()
      self.dialog = nil
      return
    }
    let panel = NSPanel(
      contentRect: CGRect(x: 640, y: 420, width: 320, height: 150),
      styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = "独立对话框"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.isReleasedWhenClosed = false
    let label = NSTextField(
      labelWithString: "这是一个独立于主窗口的悬浮对话框，\n用于验证悬停自动框选。")
    label.frame = CGRect(x: 20, y: 45, width: 280, height: 60)
    panel.contentView?.addSubview(label)
    panel.orderFrontRegardless()
    dialog = panel
  }
  @objc func dynamic() {
    if let dynamicView {
      dynamicView.removeFromSuperview()
      self.dynamicView = nil
      return
    }
    let v = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 320))
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor.systemRed.cgColor
    window.contentView!.addSubview(v)
    dynamicView = v
    let animation = CABasicAnimation(keyPath: "backgroundColor")
    animation.fromValue = NSColor.systemRed.cgColor
    animation.toValue = NSColor.systemBlue.cgColor
    animation.duration = 0.2
    animation.autoreverses = true
    animation.repeatCount = .infinity
    v.layer?.add(animation, forKey: "color")
  }
}
