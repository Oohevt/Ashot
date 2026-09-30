import AppKit
import XCTest

@testable import AshotCore

final class RenderingTests: XCTestCase {
  func base() -> CGImage {
    let ctx = CGContext(
      data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 800,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
    return ctx.makeImage()!
  }
  func testNoAnnotationsPreservesPixels() throws {
    let image = base()
    XCTAssertEqual(
      try Raster(AnnotationRenderer.render(base: image, annotations: [])).bytes,
      try Raster(image).bytes)
  }
  func testP3AnnotationPreservesUncoveredPixelAndProfile() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 800, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [1, 0.2, 0.1, 1])))
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
    let source = try XCTUnwrap(ctx.makeImage())
    let rendered = try AnnotationRenderer.render(
      base: source,
      annotations: [Annotation(kind: .cover, start: .zero, end: CGPoint(x: 10, y: 10))])
    XCTAssertEqual(rendered.colorSpace?.name, source.colorSpace?.name)
    let before = try XCTUnwrap(source.dataProvider?.data) as Data
    let after = try XCTUnwrap(rendered.dataProvider?.data) as Data
    let sourceIndex = 80 * source.bytesPerRow + 100 * 4
    let outputIndex = 80 * rendered.bytesPerRow + 100 * 4
    XCTAssertEqual(
      Array(before[sourceIndex..<sourceIndex + 4]), Array(after[outputIndex..<outputIndex + 4]))
  }
  func testOpaqueCoverFlattensAtCorrectTopLeftCoordinates() throws {
    let image = try AnnotationRenderer.render(
      base: base(),
      annotations: [
        Annotation(kind: .cover, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 60, y: 50))
      ])
    let raster = try Raster(image)
    let covered = (30 * 200 + 30) * 4
    let uncovered = (130 * 200 + 30) * 4
    XCTAssertEqual(Array(raster.bytes[covered..<covered + 4]), [0, 0, 0, 255])
    XCTAssertEqual(Array(raster.bytes[uncovered..<uncovered + 4]), [255, 255, 255, 255])
  }
  func testRectangleAndArrowAffectExpectedRegion() throws {
    let image = try AnnotationRenderer.render(
      base: base(),
      annotations: [
        Annotation(kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80)),
        Annotation(kind: .arrow, start: CGPoint(x: 100, y: 30), end: CGPoint(x: 160, y: 90)),
      ])
    let r = try Raster(image)
    for p in [CGPoint(x: 20, y: 40), CGPoint(x: 130, y: 60)] {
      let i = (Int(p.y) * 200 + Int(p.x)) * 4
      XCTAssertLessThan(r.bytes[i + 1], 200)
    }
    let i = (140 * 200 + 10) * 4
    XCTAssertEqual(Array(r.bytes[i..<i + 4]), [255, 255, 255, 255])
  }
  @MainActor func testChineseTextRendersIntoOutput() async throws {
    let image = try AnnotationRenderer.render(
      base: base(),
      annotations: [
        Annotation(
          kind: .text, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 170, y: 50), text: "中文标注")
      ])
    let b = try Raster(image).bytes
    let changed = stride(from: 0, to: b.count, by: 4).filter { b[$0 + 1] < 200 }.count
    XCTAssertGreaterThan(changed, 50)
  }
}
