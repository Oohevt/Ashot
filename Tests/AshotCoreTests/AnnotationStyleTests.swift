import AppKit
import XCTest

@testable import AshotCore

final class AnnotationStyleTests: XCTestCase {
  private func white() -> CGImage {
    let ctx = CGContext(
      data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 800,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
    return ctx.makeImage()!
  }
  private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let raster = try Raster(image)
    let i = (y * raster.width + x) * 4
    return Array(raster.bytes[i..<i + 4])
  }
  func testDefaultsKeepTheOriginalRedFourPointLook() {
    let a = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 5, y: 5))
    XCTAssertEqual(a.color, .red)
    XCTAssertEqual(a.width, 4)
  }
  func testColorChangesTheStrokePixels() throws {
    let rect = { (c: AnnotationColor) in
      try AnnotationRenderer.render(
        base: self.white(),
        annotations: [
          Annotation(
            kind: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80), color: c)
        ])
    }
    let red = try pixel(rect(.red), 20, 50)
    let blue = try pixel(rect(.blue), 20, 50)
    XCTAssertGreaterThan(red[0], red[2] + 100)
    XCTAssertGreaterThan(blue[2], blue[0] + 100)
  }
  func testWidthChangesStrokeThickness() throws {
    let stroke = { (w: Double) in
      try AnnotationRenderer.render(
        base: self.white(),
        annotations: [
          Annotation(
            kind: .rectangle, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 150, y: 120),
            color: .black, width: w)
        ])
    }
    // 5 px inside the left edge: only the thick stroke reaches it.
    XCTAssertEqual(try pixel(stroke(2), 55, 85), [255, 255, 255, 255])
    XCTAssertEqual(try pixel(stroke(12), 55, 85), [0, 0, 0, 255])
  }
  func testTextBoxFollowsContentAndWidth() {
    let small = AnnotationRenderer.textSize("Hello", width: 4)
    let big = AnnotationRenderer.textSize("Hello", width: 8)
    XCTAssertEqual(big.width / small.width, 2, accuracy: 0.1)
    XCTAssertGreaterThan(AnnotationRenderer.textSize("Hello world", width: 4).width, small.width)
  }
  func testMosaicPixelatesInsideOnlyAndIsBlockyAtItsWidth() throws {
    // Horizontal gradient: every column differs, so any equal neighbours are the mosaic's doing.
    let ctx = CGContext(
      data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 800,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<200 {
      ctx.setFillColor(CGColor(red: CGFloat(x) / 200, green: 0.3, blue: 0.6, alpha: 1))
      ctx.fill(CGRect(x: x, y: 0, width: 1, height: 160))
    }
    let base = ctx.makeImage()!
    let out = try AnnotationRenderer.render(
      base: base,
      annotations: [
        Annotation(kind: .mosaic, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 140, y: 120))
      ])
    // Inside: the first 10 px cell is one flat colour, and it differs from the next cell.
    XCTAssertEqual(try pixel(out, 41, 60), try pixel(out, 48, 60))
    XCTAssertNotEqual(try pixel(out, 45, 60), try pixel(out, 55, 60))
    // Outside: untouched.
    XCTAssertEqual(try pixel(out, 20, 60), try pixel(base, 20, 60))
    XCTAssertEqual(try pixel(out, 160, 60), try pixel(base, 160, 60))
    // Coarser width, coarser cells.
    let coarse = try AnnotationRenderer.render(
      base: base,
      annotations: [
        Annotation(
          kind: .mosaic, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 140, y: 120), width: 8)
      ])
    XCTAssertEqual(try pixel(coarse, 45, 60), try pixel(coarse, 55, 60))
  }
}
