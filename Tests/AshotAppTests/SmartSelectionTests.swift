import AppKit
import AshotCore
import ScreenCaptureKit
import XCTest

@testable import Ashot

final class SmartSelectionAppTests: XCTestCase {
  /// The live on-screen query must assign each window a unique non-negative
  /// rank (0 = frontmost) and report usable bounds for every ID, without any
  /// extra permission.
  func testOnScreenWindowsRanksUniqueAndBoundsUsable() {
    let (order, bounds) = SmartSelection.onScreenWindows()
    for (id, rank) in order {
      XCTAssertGreaterThanOrEqual(rank, 0, "window \(id)")
    }
    XCTAssertEqual(Set(order.values).count, order.values.count)
    XCTAssertFalse(bounds.isEmpty)
    for (id, rect) in bounds {
      XCTAssertEqual(Set(order.keys).contains(Int(id)), true, "bounds id \(id) missing rank")
      XCTAssertGreaterThan(rect.width, 0, "window \(id)")
      XCTAssertGreaterThan(rect.height, 0, "window \(id)")
    }
  }
  /// Gaps measured from the real main screen can only be zero or positive;
  /// a fullscreen or auto-hidden configuration simply reports zero.
  func testGapsFromRealScreenAreNonNegative() {
    guard let screen = NSScreen.main else { return }
    let gaps = SmartSelectionGeometry.SystemGaps.from(
      frame: screen.frame, visibleFrame: screen.visibleFrame)
    XCTAssertGreaterThanOrEqual(gaps.top, 0)
    XCTAssertGreaterThanOrEqual(gaps.bottom, 0)
    XCTAssertGreaterThanOrEqual(gaps.left, 0)
    XCTAssertGreaterThanOrEqual(gaps.right, 0)
  }
  /// Clicking a candidate must reuse the exact pixel mapping the crop path
  /// uses, so a locked candidate renders as the pixels seen at trigger time.
  func testLockedCandidateCropsThroughPixelRectAt2x() throws {
    let candidate = SelectionCandidate(
      rect: CGRect(x: 96, y: 48, width: 400, height: 300), kind: .window, precedence: 0)
    let resolved = try XCTUnwrap(
      SmartSelectionGeometry.resolvedSelection(dragged: nil, candidate: candidate))
    let pixels = try XCTUnwrap(
      Geometry.pixelRect(
        resolved.rect, logicalSize: CGSize(width: 1512, height: 982),
        pixelSize: CGSize(width: 3024, height: 1964)))
    XCTAssertEqual(pixels, CGRect(x: 192, y: 96, width: 800, height: 600))
  }

  // MARK: Behavior: SelectionView driven with constructed events over a real
  // SCShareableContent listing and a generated 2x frozen image.

  /// Real display/content objects from the live system plus a synthetic 2x
  /// image, so crop math runs against the true screen geometry.
  @MainActor
  private func makeView(candidates: [SelectionCandidate]) async throws -> SelectionView {
    let content = try await SCShareableContent.excludingDesktopWindows(
      true, onScreenWindowsOnly: true)
    let screen = try XCTUnwrap(NSScreen.main)
    let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber)
      .uint32Value
    let display = try XCTUnwrap(content.displays.first { $0.displayID == id })
    let width = Int(screen.frame.width * 2)
    let height = Int(screen.frame.height * 2)
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.displayP3)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    let image = try XCTUnwrap(context.makeImage())
    let view = SelectionView(
      snapshot: CaptureSnapshot(
        image: image, display: display, screen: screen, content: content),
      candidates: candidates)
    let window = OverlayWindow(
      contentRect: CGRect(origin: .zero, size: screen.frame.size),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    return view
  }

  /// `point` is display-local top-left like candidate rects; the event is
  /// built in bottom-left window coordinates and routed through the view.
  @MainActor
  private func mouse(_ view: SelectionView, _ type: NSEvent.EventType, _ point: CGPoint) {
    let location = CGPoint(x: point.x, y: view.bounds.height - point.y)
    let event = NSEvent.mouseEvent(
      with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    switch type {
    case .leftMouseDown: view.mouseDown(with: event)
    case .leftMouseDragged: view.mouseDragged(with: event)
    case .leftMouseUp: view.mouseUp(with: event)
    default: view.mouseMoved(with: event)
    }
  }

  @MainActor
  private func key(_ view: SelectionView, keyCode: UInt16) {
    let characters = keyCode == 36 ? "\r" : (keyCode == 13 ? "w" : "\u{1b}")
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
      context: nil, characters: characters, charactersIgnoringModifiers: characters,
      isARepeat: false, keyCode: keyCode)!
    view.keyDown(with: event)
  }

  @MainActor func testHoverOutlinesThenClickLocksAndEnterCropsFrozenPixels() async throws {
    let rect = CGRect(x: 640, y: 482, width: 320, height: 178)
    let view = try await makeView(
      candidates: [SelectionCandidate(rect: rect, kind: .window, precedence: 0)])
    mouse(view, .mouseMoved, CGPoint(x: rect.midX, y: rect.midY))
    XCTAssertEqual(view.hover?.rect, rect)
    XCTAssertNil(view.selection)
    mouse(view, .leftMouseDown, CGPoint(x: rect.midX, y: rect.midY))
    mouse(view, .leftMouseUp, CGPoint(x: rect.midX, y: rect.midY))
    XCTAssertEqual(view.selection, rect)
    XCTAssertNotNil(view.toolbar)
    var captured: CapturedImage?
    view.onCapture = { captured = $0 }
    key(view, keyCode: 36)
    let image = try XCTUnwrap(captured)
    XCTAssertEqual(image.image.width, 640)
    XCTAssertEqual(image.image.height, 356)
    XCTAssertEqual(image.pixelsPerPoint, CGSize(width: 2, height: 2))
  }

  @MainActor func testDragBeyondEightPointsOverridesCandidateLock() async throws {
    let rect = CGRect(x: 640, y: 482, width: 320, height: 178)
    let view = try await makeView(
      candidates: [SelectionCandidate(rect: rect, kind: .window, precedence: 0)])
    mouse(view, .leftMouseDown, CGPoint(x: 700, y: 500))
    mouse(view, .leftMouseDragged, CGPoint(x: 1000, y: 700))
    mouse(view, .leftMouseUp, CGPoint(x: 1000, y: 700))
    XCTAssertEqual(view.selection, CGRect(x: 700, y: 500, width: 300, height: 200))
    var captured: CapturedImage?
    view.onCapture = { captured = $0 }
    key(view, keyCode: 36)
    XCTAssertEqual(try XCTUnwrap(captured).image.width, 600)
  }

  @MainActor func testEmptyClickSelectsNothingAndKeysDoNothing() async throws {
    let view = try await makeView(candidates: [])
    mouse(view, .leftMouseDown, CGPoint(x: 300, y: 300))
    mouse(view, .leftMouseUp, CGPoint(x: 300, y: 300))
    // An empty click may leave a zero-size internal rect, but it must never
    // behave as a selection: no toolbar, no full-screen crop, no callbacks.
    XCTAssertTrue(
      view.selection == nil || (view.selection!.width == 0 && view.selection!.height == 0),
      "empty click produced \(String(describing: view.selection))")
    XCTAssertNil(view.toolbar)
    var fired = false
    view.onCapture = { _ in fired = true }
    view.onCopy = { _ in fired = true }
    key(view, keyCode: 36)
    key(view, keyCode: 13)
    XCTAssertFalse(fired)
    var cancelled = false
    view.onCancel = { cancelled = true }
    key(view, keyCode: 53)
    XCTAssertTrue(cancelled)
  }

  @MainActor func testFirstClickReachesMouseDownWhileAppIsStillActivating() async throws {
    let view = try await makeView(candidates: [])
    XCTAssertTrue(view.acceptsFirstMouse(for: nil))
  }
  @MainActor func testWCopiesLockedCandidateWithoutEditor() async throws {
    let rect = CGRect(x: 640, y: 482, width: 320, height: 178)
    let view = try await makeView(
      candidates: [SelectionCandidate(rect: rect, kind: .window, precedence: 0)])
    mouse(view, .leftMouseDown, CGPoint(x: rect.midX, y: rect.midY))
    mouse(view, .leftMouseUp, CGPoint(x: rect.midX, y: rect.midY))
    var copied: CapturedImage?
    var openedEditor = false
    view.onCopy = { copied = $0 }
    view.onCapture = { _ in openedEditor = true }
    key(view, keyCode: 13)
    XCTAssertEqual(try XCTUnwrap(copied).image.width, 640)
    XCTAssertFalse(openedEditor)
  }

  /// The unmocked bridge from a live window listing to candidates: whatever
  /// windows exist right now, none may stick out of its display.
  @MainActor func testLiveCandidatesStayInsideDisplayBounds() async throws {
    let view = try await makeView(candidates: [])
    let live = SmartSelection.candidates(for: view.snapshot)
    XCTAssertFalse(live.isEmpty)
    let displayLocal = CGRect(origin: .zero, size: view.snapshot.display.frame.size)
    for candidate in live {
      XCTAssertEqual(candidate.rect.intersection(displayLocal), candidate.rect, "\(candidate)")
      XCTAssertGreaterThanOrEqual(
        min(candidate.rect.width, candidate.rect.height),
        SmartSelectionGeometry.minimumCandidateSize)
    }
  }

  // MARK: - Mis-selection counterexamples (fix round 2026-09-30)

  /// Dragging 100 pt horizontally with 4 pt of jitter inside a window is a
  /// manual thin drag: the locked result must be that thin strip, not the
  /// whole window the press started in.
  @MainActor func testThinDragInsideWindowStaysThinSelectionNotTheWindow() async throws {
    let rect = CGRect(x: 640, y: 482, width: 320, height: 178)
    let view = try await makeView(
      candidates: [SelectionCandidate(rect: rect, kind: .window, precedence: 0)])
    mouse(view, .leftMouseDown, CGPoint(x: 700, y: 500))
    mouse(view, .leftMouseDragged, CGPoint(x: 800, y: 504))
    mouse(view, .leftMouseUp, CGPoint(x: 800, y: 504))
    XCTAssertEqual(view.selection, CGRect(x: 700, y: 500, width: 100, height: 4))
  }
  /// Drag-vs-click is decided once: after a >8 pt excursion the pressed
  /// candidate is gone for good, so returning near the start before release
  /// must not fall back to locking the window.
  @MainActor func testDragDecidedOnceNeverFallsBackToCandidateAfterReturn() async throws {
    let rect = CGRect(x: 640, y: 482, width: 320, height: 178)
    let view = try await makeView(
      candidates: [SelectionCandidate(rect: rect, kind: .window, precedence: 0)])
    mouse(view, .leftMouseDown, CGPoint(x: 700, y: 500))
    mouse(view, .leftMouseDragged, CGPoint(x: 900, y: 500))
    mouse(view, .leftMouseDragged, CGPoint(x: 705, y: 502))
    mouse(view, .leftMouseUp, CGPoint(x: 705, y: 502))
    XCTAssertTrue(
      view.selection == nil
        || (view.selection!.width <= SmartSelectionGeometry.minimumDrag
          && view.selection!.height <= SmartSelectionGeometry.minimumDrag),
      "drag fallback produced \(String(describing: view.selection))")
    XCTAssertNil(view.toolbar)
  }
}
