import AppKit
import AshotCore
import XCTest

@testable import Ashot

/// ScreenCaptureKit ignores sourceRect for single-window capture, so frames arrive
/// as the whole window and the selected region is cut out per frame.
final class LongCaptureTests: XCTestCase {
  let windowSize = CGSize(width: 1400, height: 850)
  let local = CGRect(x: 50, y: 130, width: 400, height: 300)
  func frame(width: Int, height: Int, blackAt rect: CGRect) throws -> CGImage {
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(rect)
    return try XCTUnwrap(ctx.makeImage())
  }
  func blackFraction(_ image: CGImage) throws -> Double {
    let raster = try Raster(image)
    var black = 0
    for i in stride(from: 0, to: raster.bytes.count, by: 4) where raster.bytes[i] < 16 {
      black += 1
    }
    return Double(black) / Double(raster.width * raster.height)
  }
  func testRegionCutsSelectedAreaOutOfFullWindowFrame() throws {
    // The expected pixel rect is (100, 260, 800, 600) from the frame's top-left;
    // CGContext fills from the bottom-left, so the marker sits at y = 1700-260-600.
    let marked = try frame(
      width: 2800, height: 1700, blackAt: CGRect(x: 100, y: 840, width: 800, height: 600))
    let region = try XCTUnwrap(LongReceiver.region(of: marked, crop: local, windowSize: windowSize))
    XCTAssertEqual(region.width, 800)
    XCTAssertEqual(region.height, 600)
    XCTAssertEqual(try blackFraction(region), 1, accuracy: 0.001)
  }
  /// Negative control: a vertically mirrored crop must miss the marker, which is
  /// exactly the failure the coordinate fix removes.
  func testRegionIsNotVerticallyMirrored() throws {
    let marked = try frame(
      width: 2800, height: 1700, blackAt: CGRect(x: 100, y: 840, width: 800, height: 600))
    let mirrored = CGRect(
      x: local.minX, y: windowSize.height - local.maxY, width: local.width, height: local.height)
    XCTAssertNotEqual(mirrored, local)
    let region = try XCTUnwrap(
      LongReceiver.region(of: marked, crop: mirrored, windowSize: windowSize))
    XCTAssertLessThan(try blackFraction(region), 0.5)
  }
  func testRegionFollowsActualFrameScale() throws {
    let marked = try frame(
      width: 1400, height: 850, blackAt: CGRect(x: 50, y: 850 - 130 - 300, width: 400, height: 300))
    let region = try XCTUnwrap(LongReceiver.region(of: marked, crop: local, windowSize: windowSize))
    XCTAssertEqual(region.width, 400)
    XCTAssertEqual(region.height, 300)
    XCTAssertEqual(try blackFraction(region), 1, accuracy: 0.001)
  }
  func testRegionRejectsDegenerateCrop() throws {
    let plain = try frame(width: 400, height: 300, blackAt: .zero)
    XCTAssertNil(LongReceiver.region(of: plain, crop: .zero, windowSize: windowSize))
    XCTAssertNil(
      LongReceiver.region(
        of: plain, crop: CGRect(x: 10, y: 10, width: 10, height: 10), windowSize: .zero))
  }
  func finish(_ receiver: LongReceiver) async throws -> CapturedImage {
    try await withCheckedThrowingContinuation { continuation in
      receiver.finish { continuation.resume(with: $0) }
    }
  }
  func testFinishedLongImageRetainsAcceptedFrameResolution() async throws {
    let receiver = LongReceiver()
    let image = try frame(width: 400, height: 300, blackAt: .zero)
    receiver.setCrop(
      CGRect(x: 10, y: 10, width: 80, height: 60), windowSize: CGSize(width: 200, height: 150))
    receiver.queue.async { receiver.acceptFrame(image) }
    let output = try await finish(receiver)
    XCTAssertEqual(output.image.width, 160)
    XCTAssertEqual(output.image.height, 120)
    XCTAssertEqual(output.pixelsPerPoint, CGSize(width: 2, height: 2))
  }
  func testRejectedResizedFrameDoesNotChangeStoredResolution() async throws {
    let receiver = LongReceiver()
    let first = try frame(width: 400, height: 300, blackAt: .zero)
    let resized = try frame(width: 600, height: 450, blackAt: .zero)
    receiver.setCrop(
      CGRect(x: 10, y: 10, width: 80, height: 60), windowSize: CGSize(width: 200, height: 150))
    receiver.queue.async {
      receiver.acceptFrame(first)
      receiver.acceptFrame(resized)
    }
    let output = try await finish(receiver)
    XCTAssertEqual(output.image.width, 160)
    XCTAssertEqual(output.image.height, 120)
    XCTAssertEqual(output.pixelsPerPoint, CGSize(width: 2, height: 2))
  }
}
