import AppKit
import AshotCore
import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
  let image: CGImage
  let pixelsPerPoint: CGSize
  private let pasteboard: NSPasteboard
  @Published var history = AnnotationHistory()
  @Published var tool: AnnotationKind? = .arrow
  @Published var selected: UUID?
  @Published var zoom: CGFloat = 0.5
  @Published var message = "拖动绘制；选择工具可移动或调整标注"
  init(
    image: CGImage, pixelsPerPoint: CGSize = CGSize(width: 1, height: 1),
    pasteboard: NSPasteboard = .general
  ) {
    self.image = image
    self.pixelsPerPoint = pixelsPerPoint
    self.pasteboard = pasteboard
    zoom = min(1, 900 / CGFloat(image.width))
    copy(automatic: true)
  }
  func commit(_ annotations: [Annotation]) {
    history.commit(annotations)
    record("annotation", ["count": annotations.count])
    copy(automatic: true)
  }
  func undo() {
    guard history.canUndo else { return }
    history.undo()
    copy(automatic: true)
  }
  func redo() {
    guard history.canRedo else { return }
    history.redo()
    copy(automatic: true)
  }
  func rendered() throws -> CGImage {
    try AnnotationRenderer.render(base: image, annotations: history.annotations)
  }
  func copy(automatic: Bool = false) {
    do {
      try ImageExport.copy(rendered(), pixelsPerPoint: pixelsPerPoint, pasteboard: pasteboard)
      message = automatic ? "已自动复制，可直接 ⌘ V 粘贴" : "已复制，可粘贴到其他应用"
    } catch {
      message = "复制失败，截图仍在，请重试复制。"
      if !automatic { presentError(error.localizedDescription) }
      record("clipboardError", ["automatic": automatic, "message": error.localizedDescription])
    }
  }
  func save() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "Ashot-\(Int(Date().timeIntervalSince1970)).png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try ImageExport.save(rendered(), pixelsPerPoint: pixelsPerPoint, to: url)
      message = "已保存：\(url.lastPathComponent)"
    } catch { presentError(error.localizedDescription) }
  }
  func removeSelected() {
    guard let selected else { return }
    commit(history.annotations.filter { $0.id != selected })
    self.selected = nil
  }
  func editText(_ id: UUID? = nil, at point: CGPoint = .zero) {
    let existing = id.flatMap { wanted in history.annotations.first { $0.id == wanted } }
    let alert = NSAlert()
    alert.messageText = existing == nil ? "添加文字" : "修改文字"
    alert.informativeText = "支持中文输入；确认后可用选择工具移动。"
    let input = NSTextField(string: existing?.text ?? "")
    input.frame = CGRect(x: 0, y: 0, width: 360, height: 28)
    alert.accessoryView = input
    alert.addButton(withTitle: "确认")
    alert.addButton(withTitle: "取消")
    alert.window.initialFirstResponder = input
    guard alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty else { return }
    var list = history.annotations
    if var existing, let index = list.firstIndex(where: { $0.id == existing.id }) {
      existing.text = input.stringValue
      list[index] = existing
      selected = existing.id
    } else {
      let a = Annotation(
        kind: .text, start: point, end: CGPoint(x: point.x + 300, y: point.y + 40),
        text: input.stringValue)
      list.append(a)
      selected = a.id
    }
    commit(list)
  }
}
struct EditorRoot: View {
  @ObservedObject var model: EditorModel
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button("选择") { model.tool = nil }
        ForEach(AnnotationKind.allCases, id: \.self) { kind in
          Button(title(kind)) { model.tool = kind }.tint(
            model.tool == kind ? .accentColor : .secondary)
        }
        Divider().frame(height: 20)
        Button("撤销") { model.undo() }.disabled(!model.history.canUndo).keyboardShortcut("z")
        Button("重做") { model.redo() }.disabled(!model.history.canRedo).keyboardShortcut(
          "z", modifiers: [.command, .shift])
        Button("删除") { model.removeSelected() }.disabled(model.selected == nil)
        Button("修改文字") { model.editText(model.selected) }.disabled(
          !model.history.annotations.contains { $0.id == model.selected && $0.kind == .text })
        Spacer()
        Button("保存") { model.save() }.keyboardShortcut("s")
        Button("复制") { model.copy() }.keyboardShortcut("c")
      }.padding(12)
      Divider()
      CanvasHost(model: model)
      Divider()
      HStack {
        Text("\(model.image.width) × \(model.image.height) px").monospacedDigit()
        Text(model.message).foregroundStyle(.secondary).lineLimit(1)
        Spacer()
        Slider(value: $model.zoom, in: 0.1...1).frame(width: 100)
        Text("\(Int(model.zoom*100))%").frame(width: 44)
      }.font(.caption).padding(10)
    }.frame(minWidth: 880, minHeight: 480)
  }
  func title(_ k: AnnotationKind) -> String {
    switch k {
    case .rectangle: return "矩形"
    case .arrow: return "箭头"
    case .text: return "文字"
    case .cover: return "遮盖"
    }
  }
}
struct CanvasHost: NSViewRepresentable {
  @ObservedObject var model: EditorModel
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.documentView = CanvasView(model: model)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let canvas = scroll.documentView as? CanvasView else { return }
    canvas.frame.size = CGSize(
      width: CGFloat(model.image.width) * model.zoom,
      height: CGFloat(model.image.height) * model.zoom)
    canvas.needsDisplay = true
  }
}
final class CanvasView: NSView {
  let model: EditorModel
  var start: CGPoint?
  var draft: Annotation?
  var original: [Annotation]?
  var resize = false
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  init(model: EditorModel) {
    self.model = model
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { fatalError() }
  func point(_ event: NSEvent) -> CGPoint {
    let p = convert(event.locationInWindow, from: nil)
    return CGPoint(x: p.x / model.zoom, y: p.y / model.zoom)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    NSImage(cgImage: model.image, size: bounds.size).draw(in: bounds)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.scaleBy(x: model.zoom, y: model.zoom)
    for a in model.history.annotations where a.id != draft?.id {
      AnnotationRenderer.draw(a, in: ctx)
    }
    if let draft { AnnotationRenderer.draw(draft, in: ctx) }
    if let selected = model.selected,
      let a = model.history.annotations.first(where: { $0.id == selected })
    {
      ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
      ctx.setLineWidth(1 / model.zoom)
      ctx.setLineDash(phase: 0, lengths: [5, 3])
      ctx.stroke(a.rect.insetBy(dx: -5, dy: -5))
      ctx.setFillColor(NSColor.controlAccentColor.cgColor)
      ctx.fill(CGRect(x: a.endX - 6, y: a.endY - 6, width: 12, height: 12))
    }
    ctx.restoreGState()
  }
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let p = point(event)
    start = p
    if let tool = model.tool {
      if tool == .text {
        model.editText(at: p)
        start = nil
        return
      }
      draft = Annotation(kind: tool, start: p, end: p)
    } else {
      let found = model.history.annotations.reversed().first {
        $0.rect.insetBy(dx: -14, dy: -14).contains(p)
      }
      model.selected = found?.id
      original = model.history.annotations
      if let found {
        resize = hypot(p.x - found.endX, p.y - found.endY) < 20
        if event.clickCount == 2 && found.kind == .text {
          model.editText(found.id)
          start = nil
        }
      }
    }
    needsDisplay = true
  }
  override func mouseDragged(with event: NSEvent) {
    guard let start else { return }
    let p = point(event)
    if let original, let selected = model.selected,
      var a = original.first(where: { $0.id == selected })
    {
      if resize {
        a.endX = p.x
        a.endY = p.y
      } else {
        a.move(dx: p.x - start.x, dy: p.y - start.y)
      }
      draft = a
    } else if var draft {
      draft.endX = p.x
      draft.endY = p.y
      self.draft = draft
    }
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    if let draft {
      var list = original ?? model.history.annotations
      if let index = list.firstIndex(where: { $0.id == draft.id }) {
        list[index] = draft
      } else if draft.rect.width + draft.rect.height > 3 {
        list.append(draft)
      }
      model.commit(list)
      model.selected = draft.id
    }
    draft = nil
    start = nil
    original = nil
    needsDisplay = true
  }
}
