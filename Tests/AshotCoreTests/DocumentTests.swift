import XCTest

@testable import AshotCore

final class DocumentTests: XCTestCase {
  func testUndoRedoBranchAndMove() {
    var history = AnnotationHistory()
    let a = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 50, y: 60))
    history.commit([a])
    history.undo()
    XCTAssertTrue(history.annotations.isEmpty)
    history.redo()
    XCTAssertEqual(history.annotations, [a])
    history.undo()
    history.commit([Annotation(kind: .cover, start: .zero, end: CGPoint(x: 5, y: 5))])
    XCTAssertFalse(history.canRedo)
  }
  func testMovePreservesDimensions() {
    var a = Annotation(kind: .arrow, start: CGPoint(x: 2, y: 4), end: CGPoint(x: 20, y: 40))
    let size = a.rect.size
    a.move(dx: -10, dy: 9)
    XCTAssertEqual(a.rect.size, size)
    XCTAssertEqual(a.x, -8)
    XCTAssertEqual(a.y, 13)
  }
}
