import AppKit
import XCTest

@testable import Ashot

final class PinTests: XCTestCase {
  @MainActor private func pin() throws -> PinWindow {
    let ctx = try XCTUnwrap(
      CGContext(
        data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let capture = CapturedImage(
      image: try XCTUnwrap(ctx.makeImage()), pixelsPerPoint: CGSize(width: 2, height: 2))
    return PinWindow(capture: capture, frame: CGRect(x: 100, y: 100, width: 200, height: 100))
  }
  @MainActor func testScaleKeepsAspectAndCenter() throws {
    let window = try pin()
    let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
    window.scale(by: 2)
    XCTAssertEqual(window.frame.width, 400, accuracy: 0.5)
    XCTAssertEqual(window.frame.height, 200, accuracy: 0.5)
    XCTAssertEqual(window.frame.midX, center.x, accuracy: 0.5)
    XCTAssertEqual(window.frame.midY, center.y, accuracy: 0.5)
  }
  @MainActor func testScaleIsClamped() throws {
    let window = try pin()
    window.scale(by: 0.0001)
    XCTAssertGreaterThanOrEqual(window.frame.width, 48)
    window.scale(by: 1_000_000)
    XCTAssertLessThanOrEqual(window.frame.width, 6000)
  }
  @MainActor func testPinFloatsAndCanTakeKeys() throws {
    let window = try pin()
    XCTAssertEqual(window.level, .floating)
    XCTAssertTrue(window.canBecomeKey)
  }
}
