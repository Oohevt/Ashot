import XCTest

@testable import AshotCore

/// Expectations use ScreenCaptureKit's top-left display/window coordinates,
/// including a non-maximized window measured during the software review.
/// GeometryTests is a frozen acceptance artifact, so these live separately.
final class CoordinateTests: XCTestCase {
  func testSelectionConvertsToCaptureDisplaySpace() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 945)
    let selection = CGRect(x: 100, y: 200, width: 400, height: 300)
    XCTAssertEqual(
      Geometry.globalRect(selection, in: screen), CGRect(x: 100, y: 200, width: 400, height: 300))
    XCTAssertEqual(
      Geometry.globalPoint(CGPoint(x: 300, y: 350), in: screen), CGPoint(x: 300, y: 350))
  }
  func testFlippedSelectionOnRaisedSecondaryDisplay() {
    let screen = CGRect(x: -1512, y: -200, width: 1512, height: 945)
    XCTAssertEqual(
      Geometry.globalRect(CGRect(x: 10, y: 20, width: 300, height: 400), in: screen),
      CGRect(x: -1502, y: -180, width: 300, height: 400))
  }
  func testWindowLocalRectUsesTopLeftOrigin() {
    XCTAssertEqual(
      Geometry.windowLocalRect(
        global: CGRect(x: -1100, y: 90, width: 500, height: 300),
        window: CGRect(x: -1200, y: 40, width: 800, height: 600)),
      CGRect(x: 100, y: 50, width: 500, height: 300))
    XCTAssertNil(
      Geometry.windowLocalRect(
        global: CGRect(x: -1300, y: 90, width: 500, height: 300),
        window: CGRect(x: -1200, y: 40, width: 800, height: 600)))
  }
  /// A selected screen point is offset by the window origin exactly once.
  func testSelectionToWindowCropEndToEnd() throws {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 945)
    let window = CGRect(x: 50, y: 25, width: 1400, height: 850)
    let selection = CGRect(x: 100, y: 200, width: 400, height: 300)
    let global = Geometry.globalRect(selection, in: screen)
    XCTAssertTrue(window.contains(global))
    XCTAssertTrue(
      window.contains(
        Geometry.globalPoint(CGPoint(x: selection.midX, y: selection.midY), in: screen)))
    let local = try XCTUnwrap(Geometry.windowLocalRect(global: global, window: window))
    XCTAssertEqual(local, CGRect(x: 50, y: 175, width: 400, height: 300))
    XCTAssertEqual(
      Geometry.pixelRect(
        local, logicalSize: window.size, pixelSize: CGSize(width: 2800, height: 1700)),
      CGRect(x: 100, y: 350, width: 800, height: 600))
  }
  func testReviewedWindowSelectionIsInsideCaptureWindow() throws {
    let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    // NSWindow.frame was (710,286,500,668); the actual SCWindow.frame was below.
    let captureWindow = CGRect(x: 710, y: 126, width: 500, height: 668)
    let selection = CGRect(x: 711, y: 155, width: 498, height: 638)
    let global = Geometry.globalRect(selection, in: display)
    XCTAssertEqual(global, selection)
    XCTAssertTrue(captureWindow.contains(global))
    XCTAssertEqual(
      try XCTUnwrap(Geometry.windowLocalRect(global: global, window: captureWindow)),
      CGRect(x: 1, y: 29, width: 498, height: 638))
  }
}
