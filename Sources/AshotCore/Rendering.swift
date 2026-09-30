import AppKit
import CoreGraphics

public enum AnnotationRenderer {
  public static func draw(_ a: Annotation, in ctx: CGContext) {
    let start = CGPoint(x: a.x, y: a.y)
    let end = CGPoint(x: a.endX, y: a.endY)
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.setStrokeColor(NSColor.systemRed.cgColor)
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    switch a.kind {
    case .rectangle: ctx.stroke(a.rect)
    case .cover:
      ctx.setFillColor(NSColor.black.cgColor)
      ctx.fill(a.rect)
    case .arrow:
      ctx.move(to: start)
      ctx.addLine(to: end)
      ctx.strokePath()
      let angle = atan2(end.y - start.y, end.x - start.x)
      let length: CGFloat = 20
      ctx.move(
        to: CGPoint(x: end.x - length * cos(angle - 0.45), y: end.y - length * sin(angle - 0.45)))
      ctx.addLine(to: end)
      ctx.addLine(
        to: CGPoint(x: end.x - length * cos(angle + 0.45), y: end.y - length * sin(angle + 0.45)))
      ctx.strokePath()
    case .text:
      let previous = NSGraphicsContext.current
      NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
      (a.text as NSString).draw(
        at: start,
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
          .foregroundColor: NSColor.systemRed,
        ])
      NSGraphicsContext.current = previous
    }
  }
  public static func render(base: CGImage, annotations: [Annotation]) throws -> CGImage {
    if annotations.isEmpty { return base }
    guard base.width * base.height <= 16_000_000,
      let ctx = RGBBitmapContext.make(
        width: base.width, height: base.height, space: RGBBitmapContext.space(of: base))
    else { throw CocoaError(.fileWriteOutOfSpace) }
    ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
    ctx.translateBy(x: 0, y: CGFloat(base.height))
    ctx.scaleBy(x: 1, y: -1)
    for a in annotations { draw(a, in: ctx) }
    guard let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    return image
  }
}
