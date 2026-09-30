import AppKit
import Carbon

final class HotKey {
  static let defaultKey = UInt32(kVK_ANSI_A)
  static let defaultModifiers = UInt32(optionKey)
  var ref: EventHotKeyRef?
  var handler: EventHandlerRef?
  var action: (() -> Void)?
  var currentKey: UInt32?
  var currentModifiers: UInt32?
  let choices: [(String, UInt32)] = [
    ("W", UInt32(kVK_ANSI_W)),
    ("2", UInt32(kVK_ANSI_2)), ("A", UInt32(kVK_ANSI_A)), ("X", UInt32(kVK_ANSI_X)),
    ("S", UInt32(kVK_ANSI_S)), ("Q", UInt32(kVK_ANSI_Q)),
  ]
  init(action: @escaping () -> Void) {
    self.action = action
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let object = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async { object.action?() }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }
  func register(key: UInt32, modifiers: UInt32) -> Bool {
    if currentKey == key, currentModifiers == modifiers { return true }
    var next: EventHotKeyRef?
    let status = RegisterEventHotKey(
      key, modifiers, EventHotKeyID(signature: 0x4153_4854, id: UInt32.random(in: 1...UInt32.max)),
      GetApplicationEventTarget(), 0, &next)
    guard status == noErr else { return false }
    if let ref { UnregisterEventHotKey(ref) }
    ref = next
    currentKey = key
    currentModifiers = modifiers
    return true
  }
  deinit {
    if let ref { UnregisterEventHotKey(ref) }
    if let handler { RemoveEventHandler(handler) }
  }
}
