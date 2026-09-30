import AppKit
import Carbon
import ScreenCaptureKit
import SwiftUI

@main
struct AshotEntry {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(AppSettings.hideAppIcon ? .accessory : .regular)
    let delegate = AppController()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let captureService = CaptureService()
  var status: NSStatusItem!
  var home: NSWindow!
  var settingsWindow: NSWindow?
  var overlay: NSWindow?
  var editors: [NSWindow] = []
  var hotKey: HotKey!
  var busy = false
  var session = UUID()
  var previousApp: NSRunningApplication?
  var longController: LongCaptureController?
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Two instances would share the hotkey and stack two overlays, the top one
    // swallowing clicks. The newest launch replaces any older one, so a fresh
    // dev build also supersedes the login-item copy in /Applications.
    let others = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.oohevt.Ashot"
    ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    others.forEach { $0.terminate() }
    for _ in 0..<20 where others.contains(where: { !$0.isTerminated }) {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.image = NSImage(
      systemSymbolName: "viewfinder", accessibilityDescription: "Ashot 截图")
    let menu = NSMenu()
    menu.addItem(withTitle: "区域截图", action: #selector(startCapture), keyEquivalent: "").target =
      self
    menu.addItem(withTitle: "打开 Ashot", action: #selector(showHome), keyEquivalent: "").target =
      self
    menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: "").target =
      self
    menu.addItem(.separator())
    menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q").target = self
    status.menu = menu
    hotKey = HotKey { [weak self] in self?.startCapture() }
    applyIconVisibility()
    // Apply the user's explicitly requested shortcut once; later choices remain configurable.
    if UserDefaults.standard.integer(forKey: "shortcutPreferenceRevision") < 2 {
      UserDefaults.standard.set(Int(HotKey.defaultKey), forKey: "hotKeyCode")
      UserDefaults.standard.set(Int(HotKey.defaultModifiers), forKey: "hotKeyModifiers")
      UserDefaults.standard.set(2, forKey: "shortcutPreferenceRevision")
    }
    let key = UInt32(UserDefaults.standard.integer(forKey: "hotKeyCode"))
    let mods = UInt32(UserDefaults.standard.integer(forKey: "hotKeyModifiers"))
    let okay = hotKey.register(
      key: UserDefaults.standard.object(forKey: "hotKeyCode") == nil ? HotKey.defaultKey : key,
      modifiers: mods == 0 ? HotKey.defaultModifiers : mods)
    record(
      "launch",
      [
        "hotkeyRegistered": okay, "key": hotKey.currentKey ?? key,
        "modifiers": hotKey.currentModifiers ?? mods,
        "screenAccess": CGPreflightScreenCaptureAccess(),
        "hideAppIcon": AppSettings.hideAppIcon,
        "loginItem": AppSettings.loginItemStatus,
      ])
    buildMainMenu()
    showHome()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag { showHome() }
    return true
  }
  func buildMainMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(withTitle: "打开 Ashot", action: #selector(showHome), keyEquivalent: "n").target =
      self
    appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target =
      self
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "退出 Ashot", action: #selector(quit), keyEquivalent: "q").target =
      self
    let fileItem = NSMenuItem()
    fileItem.title = "文件"
    main.addItem(fileItem)
    let fileMenu = NSMenu(title: "文件")
    fileItem.submenu = fileMenu
    fileMenu.addItem(
      withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let editItem = NSMenuItem()
    editItem.title = "编辑"
    main.addItem(editItem)
    let editMenu = NSMenu(title: "编辑")
    editItem.submenu = editMenu
    for (title, action, key) in [
      ("拷贝", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
      ("全选", #selector(NSText.selectAll(_:)), "a"),
    ] { editMenu.addItem(withTitle: title, action: action, keyEquivalent: key) }
    NSApp.mainMenu = main
  }
  @objc func showHome() {
    if home == nil {
      home = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 520, height: 330),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      home.title = "Ashot"
      home.isReleasedWhenClosed = false
      home.contentView = NSHostingView(rootView: HomeView(controller: self))
      home.center()
    }
    home.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  /// "Hide the icon" covers both surfaces; after this the hotkey is the only way in.
  func applyIconVisibility() {
    AppSettings.applyDockIcon()
    status.isVisible = !AppSettings.hideAppIcon
  }
  @objc func showSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 470, height: 420),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "Ashot · 设置"
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: SettingsView(controller: self))
      window.center()
      settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    record("settingsOpen")
  }
  func cleanup() {
    overlay?.close()
    overlay = nil
    busy = false
    session = UUID()
    record(
      "captureCleanup",
      ["visibleOverlayCount": NSApp.windows.filter { $0 is OverlayWindow && $0.isVisible }.count])
  }
  func windowWillClose(_ notification: Notification) {
    if let window = notification.object as? NSWindow { editors.removeAll { $0 === window } }
  }
  func requestScreenAccess() {
    let accepted = CGRequestScreenCaptureAccess()
    record("permissionRequest", ["accepted": accepted])
    if !accepted { presentError("请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Ashot，再重新打开应用。") }
  }
  @objc func startCapture() {
    guard !busy, longController == nil else {
      record("duplicateTriggerIgnored")
      return
    }
    previousApp = NSWorkspace.shared.frontmostApplication
    home?.orderOut(nil)
    busy = true
    session = UUID()
    let token = session
    record("captureStart")
    Task { [self] in
      do {
        let snapshot = try await captureService.screenshot()
        guard busy, session == token else { return }
        let view = SelectionView(
          snapshot: snapshot, candidates: SmartSelection.candidates(for: snapshot))
        let window = OverlayWindow(
          contentRect: snapshot.screen.frame, styleMask: .borderless, backing: .buffered,
          defer: false)
        window.backgroundColor = .clear
        window.isOpaque = true
        window.level = .statusBar
        window.contentView = view
        window.isReleasedWhenClosed = false
        view.onCapture = { [weak self] image in
          self?.cleanup()
          self?.openEditor(image)
        }
        view.onCopy = { [weak self] image in self?.copyAndDismiss(image) }
        view.onSave = { [weak self] image in self?.saveAndDismiss(image) }
        view.onCancel = { [weak self] in self?.cancelCapture() }
        view.onLong = { [weak self] rect in self?.beginLong(snapshot: snapshot, rect: rect) }
        overlay = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        record("overlayReady", ["width": snapshot.image.width, "height": snapshot.image.height])
      } catch {
        guard session == token else { return }
        cleanup()
        presentError(
          "无法读取屏幕。请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Ashot，然后重试。\n\(error.localizedDescription)")
        showHome()
      }
    }
  }
  func cancelCapture() {
    cleanup()
    previousApp?.activate(options: [])
    record("cancel")
  }
  /// W confirms without opening the editor: copy, confirm audibly, hand focus back.
  func copyAndDismiss(_ capture: CapturedImage) {
    cleanup()
    do {
      try ImageExport.copy(capture.image, pixelsPerPoint: capture.pixelsPerPoint)
      NSSound(named: "Tink")?.play()
      previousApp?.activate(options: [])
      record(
        "quickCopy",
        [
          "width": capture.image.width, "height": capture.image.height,
          "scaleX": capture.pixelsPerPoint.width, "scaleY": capture.pixelsPerPoint.height,
        ])
    } catch {
      presentError("复制到剪贴板失败，请重试。\(error.localizedDescription)")
      showHome()
    }
  }
  /// Save straight from the overlay. The panel cannot sit under the status-level
  /// overlay, so it closes first; a cancelled panel opens the editor so the shot survives.
  func saveAndDismiss(_ capture: CapturedImage) {
    cleanup()
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "Ashot-\(Int(Date().timeIntervalSince1970)).png"
    guard panel.runModal() == .OK, let url = panel.url else {
      openEditor(capture)
      return
    }
    do {
      try ImageExport.save(capture.image, pixelsPerPoint: capture.pixelsPerPoint, to: url)
      previousApp?.activate(options: [])
    } catch {
      presentError(error.localizedDescription)
      openEditor(capture)
    }
  }
  func openEditor(_ capture: CapturedImage) {
    let image = capture.image
    let model = EditorModel(image: image, pixelsPerPoint: capture.pixelsPerPoint)
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 1050, height: 740),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Ashot · 编辑截图"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: EditorRoot(model: model))
    window.center()
    editors.append(window)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    record("editor", ["width": image.width, "height": image.height])
  }
  func beginLong(snapshot: CaptureSnapshot, rect: CGRect) {
    cleanup()
    // Leave only the nonactivating capture panel visible while the source app
    // owns input; a home window keeps Ashot's Stage Manager group on screen.
    home?.orderOut(nil)
    let controller = LongCaptureController(service: captureService, snapshot: snapshot, rect: rect)
    longController = controller
    controller.onFinish = { [weak self] image in
      self?.longController = nil
      if let image { self?.openEditor(image) } else { self?.previousApp?.activate(options: []) }
    }
    controller.start()
  }
  @objc func quit() {
    longController?.cancel()
    cleanup()
    NSApp.terminate(nil)
  }
}
struct HomeView: View {
  let controller: AppController
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Ashot", systemImage: "viewfinder").font(.largeTitle.bold())
      Text("截图、标注和长截图，在本机完成。").foregroundStyle(.secondary)
      HStack {
        Button("区域截图") { controller.startCapture() }.buttonStyle(.borderedProminent)
        Button("屏幕权限") { controller.requestScreenAccess() }
        Button("设置…") { controller.showSettings() }
      }
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        Text("框选：鼠标悬停在窗口、菜单栏上会高亮，单击直接选中；也可拖动自由框选，框完还能拖边拖角调整。")
        Text("框选后：W 复制 · ⌘S 保存 · Enter 进入标注 · Esc 取消。")
        Text("长截图：框选可滚动的静态内容，点“长截图”后缓慢向下滚动。")
        Text("标注、撤销和重做后自动更新剪贴板，可直接 ⌘ V 粘贴。")
      }.font(.callout).foregroundStyle(.secondary)
    }.padding(28).frame(width: 520)
  }
}
