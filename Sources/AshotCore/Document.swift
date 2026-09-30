import CoreGraphics
import Foundation

public enum AnnotationKind: String, Codable, CaseIterable { case rectangle, arrow, text, mosaic }
public enum AnnotationColor: String, Codable, CaseIterable { case red, yellow, green, blue, white, black }
public struct Annotation: Identifiable, Equatable, Codable {
  public var id: UUID
  public var kind: AnnotationKind
  public var x: Double, y: Double, endX: Double, endY: Double
  public var text: String
  public var color: AnnotationColor
  /// Stroke width in image pixels; text size scales with it (see `AnnotationRenderer.fontSize`).
  public var width: Double
  public init(
    kind: AnnotationKind, start: CGPoint, end: CGPoint, text: String = "", id: UUID = UUID(),
    color: AnnotationColor = .red, width: Double = 4
  ) {
    self.id = id
    self.kind = kind
    x = start.x
    y = start.y
    endX = end.x
    endY = end.y
    self.text = text
    self.color = color
    self.width = width
  }
  public var rect: CGRect { CGRect(x: x, y: y, width: endX - x, height: endY - y).standardized }
  public mutating func move(dx: Double, dy: Double) {
    x += dx
    endX += dx
    y += dy
    endY += dy
  }
}
public struct AnnotationHistory {
  public private(set) var annotations: [Annotation] = []
  private var past: [[Annotation]] = []
  private var future: [[Annotation]] = []
  public init() {}
  public var canUndo: Bool { !past.isEmpty }
  public var canRedo: Bool { !future.isEmpty }
  public mutating func commit(_ value: [Annotation]) {
    guard value != annotations else { return }
    past.append(annotations)
    annotations = value
    future.removeAll()
  }
  public mutating func undo() {
    guard let last = past.popLast() else { return }
    future.append(annotations)
    annotations = last
  }
  public mutating func redo() {
    guard let last = future.popLast() else { return }
    past.append(annotations)
    annotations = last
  }
}
