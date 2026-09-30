import AshotCore
import CoreGraphics
import XCTest

final class SelectionAdjustTests: XCTestCase {
  let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
  let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

  func testHitCornersBeatEdgesBeatInterior() {
    XCTAssertEqual(SelectionAdjust.hit(CGPoint(x: 102, y: 98), rect: rect), .nw)
    XCTAssertEqual(SelectionAdjust.hit(CGPoint(x: 300, y: 200), rect: rect), .se)
    XCTAssertEqual(SelectionAdjust.hit(CGPoint(x: 200, y: 104), rect: rect), .n)
    XCTAssertEqual(SelectionAdjust.hit(CGPoint(x: 296, y: 150), rect: rect), .e)
    XCTAssertEqual(SelectionAdjust.hit(CGPoint(x: 200, y: 150), rect: rect), .move)
    XCTAssertNil(SelectionAdjust.hit(CGPoint(x: 50, y: 50), rect: rect))
    XCTAssertNil(SelectionAdjust.hit(CGPoint(x: 309, y: 150), rect: rect))
  }
  func testMoveKeepsSizeAndStaysInBounds() {
    let moved = SelectionAdjust.adjusted(
      rect, handle: .move, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 180, y: 120),
      bounds: bounds)
    XCTAssertEqual(moved, CGRect(x: 130, y: 70, width: 200, height: 100))
    let clamped = SelectionAdjust.adjusted(
      rect, handle: .move, from: .zero, to: CGPoint(x: 5000, y: -5000), bounds: bounds)
    XCTAssertEqual(clamped, CGRect(x: 800, y: 0, width: 200, height: 100))
  }
  func testCornerDragResizesAndEdgeDragIsOneAxis() {
    XCTAssertEqual(
      SelectionAdjust.adjusted(
        rect, handle: .se, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 350, y: 260),
        bounds: bounds),
      CGRect(x: 100, y: 100, width: 250, height: 160))
    XCTAssertEqual(
      SelectionAdjust.adjusted(
        rect, handle: .n, from: CGPoint(x: 200, y: 100), to: CGPoint(x: 260, y: 80),
        bounds: bounds),
      CGRect(x: 100, y: 80, width: 200, height: 120))
  }
  func testDraggingPastOppositeEdgeFlipsAndNeverCollapsesOrLeavesBounds() {
    XCTAssertEqual(
      SelectionAdjust.adjusted(
        rect, handle: .w, from: CGPoint(x: 100, y: 150), to: CGPoint(x: 350, y: 150),
        bounds: bounds),
      CGRect(x: 300, y: 100, width: 50, height: 100))
    let collapsed = SelectionAdjust.adjusted(
      rect, handle: .e, from: CGPoint(x: 300, y: 150), to: CGPoint(x: 100, y: 150),
      bounds: bounds)
    XCTAssertEqual(collapsed.width, 1)
    let outside = SelectionAdjust.adjusted(
      rect, handle: .se, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 5000, y: 5000),
      bounds: bounds)
    XCTAssertEqual(outside, CGRect(x: 100, y: 100, width: 900, height: 500))
  }
}
