import AppKit
import AshotCore
import ImageIO
import XCTest

@testable import Ashot

final class ClipboardTests: XCTestCase {
  func whiteImage() -> CGImage {
    let context = CGContext(
      data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
    return context.makeImage()!
  }
  @MainActor func read(_ pasteboard: NSPasteboard) throws -> Raster {
    let data = try XCTUnwrap(pasteboard.data(forType: .png))
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    return try Raster(XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
  }
  @MainActor func testEditorAutomaticallyPlacesPNGOnRealNamedPasteboard() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let model = EditorModel(image: whiteImage(), pasteboard: pasteboard)
    let result = try read(pasteboard)
    XCTAssertEqual(result.width, 100)
    XCTAssertEqual(result.height, 80)
    XCTAssertEqual(
      Array(result.bytes[(25 * 100 + 25) * 4..<(25 * 100 + 25) * 4 + 4]), [255, 255, 255, 255])
    XCTAssertTrue(model.message.contains("自动复制"))
  }
  @MainActor func testAnnotationUndoRedoAutomaticallyUpdatePNG() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let model = EditorModel(image: whiteImage(), pasteboard: pasteboard)
    let index = (25 * 100 + 10) * 4  // on the rectangle's left edge
    model.commit([
      Annotation(
        kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50), color: .black)
    ])
    XCTAssertEqual(Array(try read(pasteboard).bytes[index..<index + 4]), [0, 0, 0, 255])
    model.undo()
    XCTAssertEqual(Array(try read(pasteboard).bytes[index..<index + 4]), [255, 255, 255, 255])
    model.redo()
    XCTAssertEqual(Array(try read(pasteboard).bytes[index..<index + 4]), [0, 0, 0, 255])
  }
  @MainActor func testRetinaScaleSurvivesEditorChanges() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let model = EditorModel(
      image: whiteImage(), pixelsPerPoint: CGSize(width: 2, height: 2), pasteboard: pasteboard)
    func check() throws {
      let data = try XCTUnwrap(pasteboard.data(forType: .png))
      let decoded = try XCTUnwrap(NSImage(data: data))
      XCTAssertEqual(decoded.size.width, 50, accuracy: 0.05)
      XCTAssertEqual(decoded.size.height, 40, accuracy: 0.05)
    }
    try check()
    model.commit([Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10))])
    try check()
    model.undo()
    try check()
    model.redo()
    try check()
  }
}
