import AppKit
import Carbon
import ServiceManagement
import SwiftUI

enum AppSettings {
  private static let iconKey = "hideAppIcon"

  static var hideAppIcon: Bool {
    get { UserDefaults.standard.bool(forKey: iconKey) }
    set {
      UserDefaults.standard.set(newValue, forKey: iconKey)
      applyDockIcon()
      record("settingHideIcon", ["hidden": newValue])
    }
  }

  /// Storing the preference alone changes nothing on screen; the policy has to be applied.
  static func applyDockIcon() {
    NSApp.setActivationPolicy(hideAppIcon ? .accessory : .regular)
  }

  static var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

  /// Returns nil on success, otherwise the reason to show the user.
  static func setLaunchAtLogin(_ on: Bool) -> String? {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      return nil
    } catch { return error.localizedDescription }
  }

  static var loginItemStatus: String {
    switch SMAppService.mainApp.status {
    case .enabled: return "已启用"
    case .requiresApproval: return "已登记，等待你在系统设置 → 通用 → 登录项与扩展 里批准"
    case .notRegistered: return "未登记"
    case .notFound: return "系统暂时查不到登录项状态（首次登记前此查询可能失败）；打开开关即可登记"
    @unknown default: return "未知"
    }
  }
}

struct SettingsView: View {
  let controller: AppController
  @State private var note = ""
  @State private var status = AppSettings.loginItemStatus
  @State private var key = HotKey.defaultKey
  @State private var modifiers = HotKey.defaultModifiers
  @State private var shortcutNote = ""

  var body: some View {
    Form {
      Section {
        HStack {
          Picker("修饰键", selection: $modifiers) {
            Text("⌥").tag(UInt32(optionKey))
            Text("⌃ ⇧").tag(UInt32(controlKey | shiftKey))
            Text("⌘ ⇧").tag(UInt32(cmdKey | shiftKey))
            Text("⌃ ⌥").tag(UInt32(controlKey | optionKey))
          }.frame(width: 160)
          Picker("按键", selection: $key) {
            ForEach(controller.hotKey.choices, id: \.1) { item in Text(item.0).tag(item.1) }
          }.frame(width: 140)
          Spacer()
          Button("应用") { applyShortcut() }
        }
        if !shortcutNote.isEmpty {
          Text(shortcutNote).font(.caption).foregroundStyle(.secondary)
        }
      } header: { Text("截图快捷键") }

      Section {
        Toggle(
          isOn: Binding(
            get: { AppSettings.hideAppIcon },
            set: {
              AppSettings.hideAppIcon = $0
              controller.applyIconVisibility()
            }
          )
        ) { Text("不显示应用图标（Dock 和顶部菜单栏）") }
        Text("开启后 Dock 和顶部菜单栏都没有 Ashot 图标，只能用截图快捷键呼出。请先确认快捷键可用再开启。")
          .font(.caption).foregroundStyle(.secondary)
      } header: { Text("图标") }

      Section {
        Toggle(
          isOn: Binding(get: { AppSettings.launchAtLogin }, set: { changeLaunchAtLogin($0) })
        ) { Text("开机时自动启动") }
        Text("当前状态：\(status)").font(.caption).foregroundStyle(.secondary)
      } header: { Text("启动") }

      if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.orange) }
    }
    .formStyle(.grouped)
    .frame(minWidth: 470, minHeight: 420)
    .onAppear {
      status = AppSettings.loginItemStatus
      if controller.hotKey.currentKey == nil {
        shortcutNote = "快捷键注册失败。请解决冲突后点击“应用”，或换一个组合。"
      }
      if UserDefaults.standard.object(forKey: "hotKeyCode") != nil {
        key = UInt32(UserDefaults.standard.integer(forKey: "hotKeyCode"))
      }
      let mods = UserDefaults.standard.integer(forKey: "hotKeyModifiers")
      if mods != 0 { modifiers = UInt32(mods) }
    }
  }

  private func applyShortcut() {
    record("shortcutApplyRequested", ["key": key, "modifiers": modifiers])
    if controller.hotKey.register(key: key, modifiers: modifiers) {
      UserDefaults.standard.set(Int(key), forKey: "hotKeyCode")
      UserDefaults.standard.set(Int(modifiers), forKey: "hotKeyModifiers")
      shortcutNote = "快捷键已保存"
      record("shortcutStored", ["key": key, "modifiers": modifiers])
    } else {
      shortcutNote = "快捷键被占用，请选择其他组合"
    }
  }

  private func changeLaunchAtLogin(_ on: Bool) {
    if let failure = AppSettings.setLaunchAtLogin(on) {
      note = (on ? "登记开机自启失败：" : "取消开机自启失败：") + failure
    } else {
      note = ""
    }
    status = AppSettings.loginItemStatus
    record("settingLaunchAtLogin", ["requested": on, "status": status])
  }
}
