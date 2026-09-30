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
  @Published var color: AnnotationColor = .red
  @Published var lineWidth: Double = 4
  /// Set by the canvas: opens an in-place text field. Nil until a canvas exists.
  var textEditor: ((UUID?, CGPoint) -> Void)?
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
    let start = id.flatMap { wanted in history.annotations.first { $0.id == wanted } }
      .map { CGPoint(x: $0.x, y: $0.y) } ?? point
    textEditor?(id, start)
  }
  /// Called by the canvas when in-place editing ends with a non-empty string.
  func commitText(_ id: UUID?, at point: CGPoint, string: String) {
    var list = history.annotations
    if let id, let index = list.firstIndex(where: { $0.id == id }) {
      list[index].text = string
      Self.fit(&list[index])
      selected = id
    } else {
      var a = Annotation(
        kind: .text, start: point, end: point, text: string, color: color, width: lineWidth)
      Self.fit(&a)
      list.append(a)
      selected = a.id
    }
    commit(list)
  }
  /// A text annotation's box follows its content, so selection and hit-testing match the ink.
  static func fit(_ a: inout Annotation) {
    guard a.kind == .text else { return }
    let size = AnnotationRenderer.textSize(a.text, width: a.width)
    a.endX = a.x + size.width
    a.endY = a.y + size.height
  }
  /// Applies to the selected annotation if there is one, and to everything drawn next.
  func setColor(_ value: AnnotationColor) {
    color = value
    restyleSelected { if $0.kind != .mosaic { $0.color = value } }
  }
  func setWidth(_ value: Double) {
    lineWidth = value
    restyleSelected {
      $0.width = value
      Self.fit(&$0)
    }
  }
  private func restyleSelected(_ change: (inout Annotation) -> Void) {
    guard let selected, var list = Optional(history.annotations),
      let index = list.firstIndex(where: { $0.id == selected }), true
    else { return }
    change(&list[index])
    commit(list)
  }
}
struct EditorRoot: View {
  @ObservedObject var model: EditorModel
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        HStack(spacing: 2) {
          toolButton("选择", "cursorarrow", nil)
          ForEach(AnnotationKind.allCases, id: \.self) { kind in
            toolButton(title(kind), symbol(kind), kind)
          }
        }
        Divider().frame(height: 20)
        HStack(spacing: 6) {
          ForEach(AnnotationColor.allCases, id: \.self) { c in
            Button { model.setColor(c) } label: {
              Circle().fill(Color(nsColor: c.nsColor)).frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
                .overlay(
                  Circle().stroke(Color.accentColor, lineWidth: 2).frame(width: 22, height: 22)
                    .opacity(model.color == c ? 1 : 0))
                .frame(width: 24, height: 24)
            }.buttonStyle(.plain).help(colorName(c))
          }
        }
        Picker("粗细", selection: Binding(get: { model.lineWidth }, set: { model.setWidth($0) })) {
          Text("细").tag(2.0)
          Text("中").tag(4.0)
          Text("粗").tag(8.0)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 96).help("线条粗细 / 文字大小")
        Divider().frame(height: 20)
        HStack(spacing: 2) {
          iconAction("撤销  ⌘Z", "arrow.uturn.backward") { model.undo() }
            .disabled(!model.history.canUndo).keyboardShortcut("z")
          iconAction("重做  ⇧⌘Z", "arrow.uturn.forward") { model.redo() }
            .disabled(!model.history.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
          iconAction("删除选中标注", "trash") { model.removeSelected() }
            .disabled(model.selected == nil)
          iconAction("修改文字（也可双击文字）", "pencil") {
            model.editText(model.selected)
          }.disabled(!model.history.annotations.contains { $0.id == model.selected && $0.kind == .text })
        }
        Spacer(minLength: 8)
        Button { model.save() } label: { Label("保存", systemImage: "square.and.arrow.down") }
          .keyboardShortcut("s").fixedSize()
        Button { model.copy() } label: { Label("复制", systemImage: "doc.on.doc") }
          .keyboardShortcut("c").buttonStyle(.borderedProminent).fixedSize()
      }.padding(.horizontal, 12).padding(.vertical, 10)
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
    }.frame(minWidth: 840, minHeight: 480)
  }
  func toolButton(_ name: String, _ symbol: String, _ kind: AnnotationKind?) -> some View {
    let active = model.tool == kind
    return Button { model.tool = kind } label: {
      glyph(symbol).frame(width: 30, height: 26)
        .background(active ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(active ? Color.accentColor : Color.primary)
    }.buttonStyle(.plain).help(name).accessibilityLabel(name)
  }
  /// "textformat" is localized by SF Symbols into the two characters 格式 on Chinese systems.
  @ViewBuilder func glyph(_ symbol: String) -> some View {
    if symbol == "textformat" {
      Text("T").font(.system(size: 16, weight: .bold, design: .serif))
    } else {
      Image(systemName: symbol)
    }
  }
  func iconAction(_ name: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: 30, height: 26) }
      .buttonStyle(.plain).help(name).accessibilityLabel(name)
  }
  func symbol(_ k: AnnotationKind) -> String {
    switch k {
    case .rectangle: return "rectangle"
    case .arrow: return "arrow.up.right"
    case .text: return "textformat"
    case .mosaic: return "square.grid.3x3.fill"
    }
  }
  func colorName(_ c: AnnotationColor) -> String {
    switch c {
    case .red: return "红"
    case .yellow: return "黄"
    case .green: return "绿"
    case .blue: return "蓝"
    case .white: return "白"
    case .black: return "黑"
    }
  }
  func title(_ k: AnnotationKind) -> String {
    switch k {
    case .rectangle: return "矩形"
    case .arrow: return "箭头"
    case .text: return "文字"
    case .mosaic: return "马赛克"
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
final class CanvasView: NSView, NSTextFieldDelegate {
  let model: EditorModel
  var start: CGPoint?
  var draft: Annotation?
  var original: [Annotation]?
  var resize = false
  var field: NSTextField?
  var editing: (id: UUID?, point: CGPoint)?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  init(model: EditorModel) {
    self.model = model
    super.init(frame: .zero)
    model.textEditor = { [weak self] id, point in self?.beginText(id, at: point) }
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
    for a in model.history.annotations where a.id != draft?.id && a.id != editing?.id {
      AnnotationRenderer.draw(a, in: ctx, base: model.image)
    }
    if let draft {
      AnnotationRenderer.draw(draft, in: ctx, base: model.image)
      // The mosaic has no stroke of its own; show its region while dragging.
      if draft.kind == .mosaic {
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1.5 / model.zoom)
        ctx.setLineDash(phase: 0, lengths: [6 / model.zoom, 4 / model.zoom])
        ctx.stroke(draft.rect)
      }
    }
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
  // MARK: In-place text
  func beginText(_ id: UUID?, at point: CGPoint) {
    finishText(commit: true)
    let existing = id.flatMap { wanted in model.history.annotations.first { $0.id == wanted } }
    let width = existing?.width ?? model.lineWidth
    let f = NSTextField(string: existing?.text ?? "")
    f.isBordered = false
    f.drawsBackground = false
    f.focusRingType = .none
    f.font = .systemFont(
      ofSize: AnnotationRenderer.fontSize(width: width) * model.zoom, weight: .semibold)
    f.textColor = (existing?.color ?? model.color).nsColor
    f.placeholderString = "输入文字，回车确认"
    f.delegate = self
    f.frame = CGRect(
      x: point.x * model.zoom, y: point.y * model.zoom, width: 160,
      height: f.intrinsicContentSize.height)
    fitField(f)
    addSubview(f)
    field = f
    editing = (id, point)
    window?.makeFirstResponder(f)
    needsDisplay = true
  }
  private func fitField(_ f: NSTextField) {
    let text = f.stringValue.isEmpty ? "输入文字，回车确认" : f.stringValue
    let w = (text as NSString).size(withAttributes: [.font: f.font as Any]).width
    f.frame.size.width = max(80, ceil(w) + 24)
  }
  func finishText(commit: Bool) {
    guard let f = field, let target = editing else { return }
    field = nil
    editing = nil
    let string = f.stringValue
    f.removeFromSuperview()
    if commit, !string.isEmpty { model.commitText(target.id, at: target.point, string: string) }
    window?.makeFirstResponder(self)
    needsDisplay = true
  }
  func controlTextDidChange(_ notification: Notification) {
    if let f = field { fitField(f) }
  }
  func controlTextDidEndEditing(_ notification: Notification) { finishText(commit: true) }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if selector == #selector(NSResponder.cancelOperation(_:)) {
      finishText(commit: false)
      return true
    }
    return false
  }
  override func mouseDown(with event: NSEvent) {
    finishText(commit: true)
    window?.makeFirstResponder(self)
    let p = point(event)
    start = p
    if let tool = model.tool {
      if tool == .text {
        model.editText(at: p)
        start = nil
        return
      }
      draft = Annotation(
        kind: tool, start: p, end: p, color: model.color, width: model.lineWidth)
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
