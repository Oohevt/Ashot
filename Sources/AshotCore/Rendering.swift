import AppKit
import CoreGraphics

extension AnnotationColor {
  public var nsColor: NSColor {
    switch self {
    case .red: return .systemRed
    case .yellow: return .systemYellow
    case .green: return .systemGreen
    case .blue: return .systemBlue
    case .white: return .white
    case .black: return .black
    }
  }
}
public enum AnnotationRenderer {
  public static func fontSize(width: Double) -> CGFloat { CGFloat(width) * 7 }
  public static func font(width: Double) -> NSFont {
    .systemFont(ofSize: fontSize(width: width), weight: .semibold)
  }
  /// Bounding size of a text annotation; used for hit-testing and selection outlines.
  public static func textSize(_ text: String, width: Double) -> CGSize {
    let size = (text as NSString).size(withAttributes: [.font: font(width: width)])
    return CGSize(width: ceil(size.width), height: ceil(size.height))
  }
  /// `base` is the untouched image the annotations sit on; the mosaic reads its
  /// pixels (annotations are in image pixels, y down, same as the context).
  public static func draw(_ a: Annotation, in ctx: CGContext, base: CGImage? = nil) {
    let start = CGPoint(x: a.x, y: a.y)
    let end = CGPoint(x: a.endX, y: a.endY)
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.setStrokeColor(a.color.nsColor.cgColor)
    ctx.setLineWidth(CGFloat(a.width))
    ctx.setLineCap(.round)
    switch a.kind {
    case .rectangle: ctx.stroke(a.rect)
    case .mosaic:
      if let base { drawMosaic(a, in: ctx, base: base) }
    case .arrow:
      ctx.move(to: start)
      ctx.addLine(to: end)
      ctx.strokePath()
      let angle = atan2(end.y - start.y, end.x - start.x)
      let length = CGFloat(12 + a.width * 2)
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
          .font: font(width: a.width),
          .foregroundColor: a.color.nsColor,
        ])
      NSGraphicsContext.current = previous
    }
  }
  /// Pixelation: average the region into `block`-sized cells, then blow it back up
  /// without interpolation. `width` sets the cell size (4 → 10 px).
  static func drawMosaic(_ a: Annotation, in ctx: CGContext, base: CGImage) {
    let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
    let region = a.rect.integral.intersection(bounds)
    guard !region.isNull, region.width >= 1, region.height >= 1,
      let crop = base.cropping(to: region)
    else { return }
    let block = max(4, a.width * 2.5)
    let cols = max(1, Int((region.width / block).rounded(.up)))
    let rows = max(1, Int((region.height / block).rounded(.up)))
    guard
      let small = CGContext(
        data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    small.interpolationQuality = .high
    small.draw(crop, in: CGRect(x: 0, y: 0, width: cols, height: rows))
    guard let cells = small.makeImage() else { return }
    ctx.saveGState()
    ctx.clip(to: region)
    ctx.interpolationQuality = .none
    // The context is y-down; CGImage drawing is y-up, so flip locally.
    ctx.translateBy(x: region.minX, y: region.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(cells, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
    ctx.restoreGState()
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
    for a in annotations { draw(a, in: ctx, base: base) }
    guard let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    return image
  }
}
