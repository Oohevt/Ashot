import ImageIO
import XCTest

@testable import AshotCore

final class StitchTests: XCTestCase {
  func fixture() -> CGImage {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    return CGImageSourceCreateImageAtIndex(
      CGImageSourceCreateWithURL(
        root.appendingPathComponent("fixtures/article.png") as CFURL, nil)!, 0, nil)!
  }
  func testKnownDisplacementAndCompleteReconstruction() throws {
    let image = fixture()
    let acc = StitchAccumulator()
    var top = 0
    while top <= image.height - 1200 {
      let frame = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: 1200))!
      try acc.accept(frame)
      if top == image.height - 1200 { break }
      top = min(top + 600, image.height - 1200)
    }
    let result = try acc.result()
    XCTAssertEqual(result.width, image.width)
    XCTAssertEqual(result.height, image.height)
    XCTAssertEqual(try Raster(result).bytes, try Raster(image).bytes)
  }
  func testMissingOverlapFailsAndPreservesResult() throws {
    let image = fixture()
    let acc = StitchAccumulator()
    try acc.accept(image.cropping(to: CGRect(x: 0, y: 0, width: 1000, height: 1200))!)
    XCTAssertThrowsError(
      try acc.accept(image.cropping(to: CGRect(x: 0, y: 2000, width: 1000, height: 1200))!))
    XCTAssertEqual(acc.height, 1200)
    XCTAssertEqual(try acc.result().height, 1200)
  }
  func testDuplicatesDoNotAppend() throws {
    let a = fixture().cropping(to: CGRect(x: 0, y: 0, width: 1000, height: 1200))!
    let acc = StitchAccumulator()
    try acc.accept(a)
    XCTAssertEqual(try acc.accept(a), .unchanged)
    XCTAssertEqual(acc.height, 1200)
    XCTAssertEqual(acc.frameCount, 1)
  }
  func testHorizontalShiftRejected() throws {
    let image = fixture()
    let a = image.cropping(to: CGRect(x: 0, y: 0, width: 900, height: 1200))!
    let b = image.cropping(to: CGRect(x: 30, y: 600, width: 900, height: 1200))!
    XCTAssertThrowsError(try VerticalMatcher.match(previous: a, next: b))
  }
  func testDimensionsRejected() throws {
    let image = fixture()
    let a = image.cropping(to: CGRect(x: 0, y: 0, width: 1000, height: 1000))!
    let b = image.cropping(to: CGRect(x: 0, y: 100, width: 900, height: 1000))!
    XCTAssertThrowsError(try VerticalMatcher.match(previous: a, next: b)) {
      XCTAssertEqual($0 as? StitchError, .dimensions)
    }
  }
  func testLargeDynamicChangeRejected() throws {
    let a = fixture().cropping(to: CGRect(x: 0, y: 0, width: 1000, height: 1200))!
    let ctx = CGContext(
      data: nil, width: 1000, height: 1200, bitsPerComponent: 8, bytesPerRow: 4000,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(a, in: CGRect(x: 0, y: 0, width: 1000, height: 1200))
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
    XCTAssertThrowsError(try VerticalMatcher.match(previous: a, next: ctx.makeImage()!))
  }
  func testOversizedInputRejected() throws {
    let ctx = CGContext(
      data: nil, width: 9000, height: 10, bitsPerComponent: 8, bytesPerRow: 36000,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    XCTAssertThrowsError(try Raster(ctx.makeImage()!)) {
      XCTAssertEqual($0 as? StitchError, .limit)
    }
  }
  /// Display P3 captures must survive the strip compositing instead of being
  /// flattened to sRGB, which would make long shots duller than normal shots.
  func testWideGamutSourceSurvivesStrips() throws {
    let p3 = CGColorSpace.displayP3 as String
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let source = fixture()
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: source.width, height: 1800, bitsPerComponent: 8,
        bytesPerRow: source.width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(
      try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: source.width, height: 1800))),
      in: CGRect(x: 0, y: 0, width: source.width, height: 1800))
    let image = try XCTUnwrap(ctx.makeImage())
    XCTAssertEqual(image.colorSpace?.name as String?, p3)
    let acc = StitchAccumulator()
    _ = try acc.accept(
      try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 1200))))
    _ = try acc.accept(
      try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 600, width: image.width, height: 1200))))
    let result = try acc.result()
    XCTAssertEqual(result.height, 1800)
    XCTAssertEqual(result.colorSpace?.name as String?, p3)
  }
}
