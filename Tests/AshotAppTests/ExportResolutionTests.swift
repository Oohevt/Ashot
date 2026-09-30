import AppKit
import ImageIO
import XCTest

@testable import Ashot

final class ExportResolutionTests: XCTestCase {
  func image() throws -> CGImage {
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
    return try XCTUnwrap(ctx.makeImage())
  }
  @MainActor func check(scale: CGSize, dpiX: Double, dpiY: Double, logical: CGSize) throws {
    let data = try ImageExport.png(image(), pixelsPerPoint: scale)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    XCTAssertEqual(props[kCGImagePropertyPixelWidth as String] as? Int, 100)
    XCTAssertEqual(props[kCGImagePropertyPixelHeight as String] as? Int, 80)
    XCTAssertEqual(
      try XCTUnwrap(props[kCGImagePropertyDPIWidth as String] as? Double), dpiX, accuracy: 0.02)
    XCTAssertEqual(
      try XCTUnwrap(props[kCGImagePropertyDPIHeight as String] as? Double), dpiY, accuracy: 0.02)
    let decoded = try XCTUnwrap(NSImage(data: data))
    XCTAssertEqual(decoded.size.width, logical.width, accuracy: 0.05)
    XCTAssertEqual(decoded.size.height, logical.height, accuracy: 0.05)
  }
  @MainActor func testRetinaExportRetainsLogicalSize() async throws {
    try check(
      scale: CGSize(width: 2, height: 2), dpiX: 144, dpiY: 144,
      logical: CGSize(width: 50, height: 40))
  }
  @MainActor func testOneXExportRemainsOneX() async throws {
    try check(
      scale: CGSize(width: 1, height: 1), dpiX: 72, dpiY: 72,
      logical: CGSize(width: 100, height: 80))
  }
  @MainActor func testPerAxisAndFractionalScale() async throws {
    try check(
      scale: CGSize(width: 1.25, height: 2), dpiX: 90, dpiY: 144,
      logical: CGSize(width: 80, height: 40))
  }
  func testInvalidScaleCannotProduceMisleadingMetadata() throws {
    XCTAssertThrowsError(try ImageExport.png(image(), pixelsPerPoint: CGSize(width: 0, height: 2)))
    XCTAssertThrowsError(
      try ImageExport.png(image(), pixelsPerPoint: CGSize(width: Double.nan, height: 2)))
  }
  @MainActor func testSavedFileRetainsSameResolutionAsClipboard() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let dir = root.appendingPathComponent("evidence")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("unit-retina-export.png")
    try ImageExport.save(image(), pixelsPerPoint: CGSize(width: 2, height: 2), to: url)
    let data = try Data(contentsOf: url)
    let decoded = try XCTUnwrap(NSImage(data: data))
    XCTAssertEqual(decoded.size.width, 50, accuracy: 0.05)
    XCTAssertEqual(decoded.size.height, 40, accuracy: 0.05)
    XCTAssertEqual(data, try ImageExport.png(image(), pixelsPerPoint: CGSize(width: 2, height: 2)))
  }
}
