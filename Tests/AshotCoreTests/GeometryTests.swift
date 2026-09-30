import XCTest
@testable import AshotCore
final class GeometryTests: XCTestCase {
    func testRetinaPixelBounds() {
        XCTAssertEqual(Geometry.pixelRect(CGRect(x: 10, y: 20, width: 100, height: 50), logicalSize: CGSize(width: 600, height: 400), pixelSize: CGSize(width: 1200, height: 800)), CGRect(x: 20, y: 40, width: 200, height: 100))
    }
    func testIndependentScaleAndClipping() {
        XCTAssertEqual(Geometry.pixelRect(CGRect(x: -2, y: 1.5, width: 12.2, height: 5), logicalSize: CGSize(width: 100, height: 100), pixelSize: CGSize(width: 150, height: 200)), CGRect(x: 0, y: 3, width: 16, height: 10))
    }
    func testInvalidAreaRejected() {
        XCTAssertNil(Geometry.pixelRect(CGRect(x: 100, y: 100, width: 10, height: 10), logicalSize: CGSize(width: 50, height: 50), pixelSize: CGSize(width: 100, height: 100)))
    }
}
