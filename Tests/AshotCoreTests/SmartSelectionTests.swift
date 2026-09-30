import XCTest

@testable import AshotCore

/// Hover-candidate geometry follows the review's coordinate rules: every rect
/// is top-left origin, display-local, and unreliable sources fall back to nil.
final class SmartSelectionTests: XCTestCase {
  let display = CGRect(x: 0, y: 0, width: 1512, height: 945)
  func window(
    _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
    z: Int = 0, layer: Int = 0, ownApp: Bool = false, id: UInt32 = 1
  ) -> SmartSelectionGeometry.WindowInfo {
    SmartSelectionGeometry.WindowInfo(
      frame: CGRect(x: x, y: y, width: w, height: h), layer: layer, z: z, ownApp: ownApp,
      windowID: id)
  }
  func testFrontmostWindowUnderCursorWinsOverWindowBehindIt() throws {
    let parent = window(100, 100, 900, 600, z: 5)
    let dialog = window(200, 200, 320, 180, z: 0)
    let list = SmartSelectionGeometry.candidates(
      windows: [parent, dialog], display: display, systemGaps: .init())
    let picked = try XCTUnwrap(
      SmartSelectionGeometry.pick(at: CGPoint(x: 350, y: 280), candidates: list))
    XCTAssertEqual(picked.kind, .window)
    XCTAssertEqual(picked.rect, CGRect(x: 200, y: 200, width: 320, height: 180))
    XCTAssertEqual(picked.precedence, dialogPrecedence(front: 0))
  }
  func dialogPrecedence(front z: Int) -> Int { 1_000_000 - z }
  func testSecondaryDisplayWithNegativeOriginConvertsToLocalTopLeft() throws {
    let secondary = CGRect(x: -1512, y: -200, width: 1512, height: 945)
    let list = SmartSelectionGeometry.candidates(
      windows: [window(-1500, -180, 600, 400)], display: secondary, systemGaps: .init())
    let picked = try XCTUnwrap(
      SmartSelectionGeometry.pick(at: CGPoint(x: 30, y: 50), candidates: list))
    XCTAssertEqual(picked.rect.origin, CGPoint(x: 12, y: 20))
    XCTAssertEqual(
      Geometry.globalRect(picked.rect, in: secondary),
      CGRect(x: -1500, y: -180, width: 600, height: 400))
  }
  func testWindowStraddlingDisplayEdgeIsClippedAndOffscreenDropped() throws {
    let list = SmartSelectionGeometry.candidates(
      windows: [
        window(1400, 100, 400, 300),
        window(2000, 100, 300, 300),
      ],
      display: display, systemGaps: .init())
    XCTAssertEqual(list.count, 1)
    XCTAssertEqual(list[0].rect, CGRect(x: 1400, y: 100, width: 112, height: 300))
  }
  func testOwnAppOverlayAndHighLayerWindowsAreExcludedButFloatingDialogIncluded() {
    let list = SmartSelectionGeometry.candidates(
      windows: [
        window(100, 100, 500, 400, ownApp: true),
        window(100, 100, 500, 400, z: 0, layer: 25),
        window(100, 100, 500, 400),
        // Independent dialogs are floating panels at window layer 3.
        window(600, 200, 320, 180, z: 1, layer: 3),
      ],
      display: display, systemGaps: .init())
    XCTAssertEqual(list.count, 2)
    XCTAssertEqual(list[0].kind, .window)
    XCTAssertEqual(
      list[1].rect, CGRect(x: 600, y: 200, width: 320, height: 180))
  }
  /// The Dock candidate follows the actual backplate rect supplied by the
  /// bridge (bottom and side orientations); it never spans the display and
  /// still wins over an overlapping window.
  func testDockCandidateFollowsActualDockBackplateNotScreenWidth() throws {
    for (dockRect, probe) in [
      (CGRect(x: 356, y: 865, width: 800, height: 80), CGPoint(x: 756, y: 905)),
      (CGRect(x: 0, y: 0, width: 72, height: 945), CGPoint(x: 36, y: 400)),
    ] {
      let list = SmartSelectionGeometry.candidates(
        windows: [window(0, 700, 1512, 245, z: 0)], display: display,
        systemGaps: .init(top: 24), dockVisibleRect: dockRect)
      let picked = try XCTUnwrap(SmartSelectionGeometry.pick(at: probe, candidates: list))
      XCTAssertEqual(picked.kind, .dock)
      XCTAssertEqual(picked.rect, dockRect)
      XCTAssertEqual(list.filter { $0.kind == .dock }.count, 1)
      let wallpaper = SmartSelectionGeometry.pick(
        at: CGPoint(x: 100, y: 905), candidates: list)
      if let wallpaper { XCTAssertNotEqual(wallpaper.kind, .dock) }
    }
  }
  /// A window whose WindowServer ID is missing from the same-moment on-screen
  /// list (Stage Manager strip, stale listing) or whose bounds disagree beyond
  /// tolerance (window moved between the two samples) is unreliable and must
  /// not be offered as a candidate.
  func testValidatedWindowsDropsUnknownIDAndMovedFrames() {
    let stable = window(100, 100, 500, 300, id: 7)
    let stale = window(400, 300, 500, 300, id: 42)
    let moved = window(600, 200, 500, 300, id: 9)
    let kept = SmartSelectionGeometry.validatedWindows(
      [stable, stale, moved],
      visibleBounds: [
        7: CGRect(x: 100, y: 100, width: 500, height: 300),
        9: CGRect(x: 152, y: 204, width: 500, height: 300),
      ])
    XCTAssertEqual(kept.map(\.windowID), [7])
  }
  /// A hidden Dock leaves a full-screen tracking window in the frozen capture
  /// listing; without a matching entry in the same-moment on-screen sample it
  /// must yield NO dock rect at all — never the whole display.
  func testHiddenDockTrackingWindowYieldsNoDockRect() {
    let tracking = window(0, 0, 1512, 945, id: 501)
    XCTAssertNil(
      SmartSelectionGeometry.validatedDockRect([tracking], display: display, visibleBounds: [:]))
    // Revealed: the live sample confirms the backplate by ID and bounds.
    let backplate = window(560, 849, 800, 96, id: 502)
    let live = [UInt32(502): CGRect(x: 560, y: 849, width: 800, height: 96)]
    XCTAssertEqual(
      SmartSelectionGeometry.validatedDockRect(
        [tracking, backplate], display: display, visibleBounds: live),
      CGRect(x: 560, y: 849, width: 800, height: 96))
    // Bounds drifted between samples (reveal animation midpoint) → no rect.
    let drifting = [UInt32(502): CGRect(x: 560, y: 880, width: 800, height: 96)]
    XCTAssertNil(
      SmartSelectionGeometry.validatedDockRect(
        [backplate], display: display, visibleBounds: drifting))
  }
  func testOnScreenFullDisplayDockWindowIsNotTheBackplate() {
    let tracking = window(0, 0, 1512, 945, id: 501)
    let live = [UInt32(501): CGRect(x: 0, y: 0, width: 1512, height: 945)]
    XCTAssertNil(
      SmartSelectionGeometry.validatedDockRect([tracking], display: display, visibleBounds: live))
  }
  func testMenuBarAppearsOnlyWhenVisibleGapIsReal() {
    let shown = SmartSelectionGeometry.candidates(
      windows: [], display: display, systemGaps: .init(top: 24))
    XCTAssertEqual(shown.count, 1)
    XCTAssertEqual(shown[0].kind, .menuBar)
    XCTAssertEqual(shown[0].rect, CGRect(x: 0, y: 0, width: 1512, height: 24))
    let sliver = SmartSelectionGeometry.candidates(
      windows: [], display: display, systemGaps: .init(top: 4))
    let hidden = SmartSelectionGeometry.candidates(
      windows: [], display: display, systemGaps: .init())
    XCTAssertTrue(sliver.isEmpty)
    XCTAssertTrue(hidden.isEmpty)
  }
  func testEmptyScreenSpaceHasNoCandidate() {
    let list = SmartSelectionGeometry.candidates(
      windows: [window(100, 100, 500, 400)], display: display, systemGaps: .init(top: 24))
    XCTAssertNil(SmartSelectionGeometry.pick(at: CGPoint(x: 800, y: 600), candidates: list))
  }
  func testGapsDerivedFromAppKitFrameAndVisibleFrame() {
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 945)
    let visible = CGRect(x: 80, y: 40, width: 1360, height: 880)
    XCTAssertEqual(
      SmartSelectionGeometry.SystemGaps.from(frame: frame, visibleFrame: visible),
      .init(top: 25, bottom: 40, left: 80, right: 72))
    XCTAssertEqual(
      SmartSelectionGeometry.SystemGaps.from(frame: frame, visibleFrame: frame), .init())
  }
  /// The locked candidate maps through the same pixel conversion the crop uses:
  /// integral 2x selections double exactly, and fractional origins round
  /// outward so no covered pixel row is lost.
  func testCandidatePixelMappingDoublesOnRetina() throws {
    let integral = SelectionCandidate(
      rect: CGRect(x: 96, y: 48, width: 400, height: 300), kind: .window, precedence: 0)
    let exact = try XCTUnwrap(
      Geometry.pixelRect(
        integral.rect, logicalSize: CGSize(width: 1512, height: 982),
        pixelSize: CGSize(width: 3024, height: 1964)))
    XCTAssertEqual(exact, CGRect(x: 192, y: 96, width: 800, height: 600))
    let fractional = CGRect(x: 100.4, y: 50.2, width: 300, height: 200)
    let covered = try XCTUnwrap(
      Geometry.pixelRect(
        fractional, logicalSize: CGSize(width: 1512, height: 945),
        pixelSize: CGSize(width: 3024, height: 1890)))
    XCTAssertEqual(covered, CGRect(x: 200, y: 100, width: 601, height: 401))
  }
  func testDragOverEightPointsOverridesCandidateLock() throws {
    let candidate = SelectionCandidate(
      rect: CGRect(x: 10, y: 10, width: 500, height: 300), kind: .window, precedence: 0)
    let dragged = try XCTUnwrap(
      SmartSelectionGeometry.resolvedSelection(
        dragged: CGRect(x: 0, y: 0, width: 120, height: 90), candidate: candidate))
    XCTAssertEqual(dragged.rect, CGRect(x: 0, y: 0, width: 120, height: 90))
    XCTAssertNil(dragged.kind)
    let locked = try XCTUnwrap(
      SmartSelectionGeometry.resolvedSelection(
        dragged: CGRect(x: 0, y: 0, width: 5, height: 4), candidate: candidate))
    XCTAssertEqual(locked.rect, candidate.rect)
    XCTAssertEqual(locked.kind, .window)
    let plainClick = try XCTUnwrap(
      SmartSelectionGeometry.resolvedSelection(dragged: nil, candidate: candidate))
    XCTAssertEqual(plainClick.rect, candidate.rect)
    XCTAssertNil(SmartSelectionGeometry.resolvedSelection(dragged: nil, candidate: nil))
    XCTAssertNil(
      SmartSelectionGeometry.resolvedSelection(
        dragged: CGRect(x: 0, y: 0, width: 5, height: 4), candidate: nil))
  }

  // MARK: - Mis-selection counterexamples (fix round 2026-09-30)

  /// The visibleFrame reserve strip spans the whole screen width; the real
  /// Dock backplate does not. Without trustworthy Dock window bounds there
  /// must be no Dock candidate at all — never a full-width bottom strip.
  func testVisibleFrameReserveStripIsNotADockCandidate() {
    let list = SmartSelectionGeometry.candidates(
      windows: [window(0, 700, 1512, 245, z: 0)],
      display: display, systemGaps: .init(bottom: 80))
    XCTAssertFalse(list.contains { $0.kind == .dock }, "\(list)")
  }
  /// A 100 x 4 drag crosses the threshold on one axis only; it is a manual
  /// drag, so it must resolve to the thin strip — never lock the whole
  /// window the press started inside.
  func testThinHorizontalDragNeverLocksThePressedWindow() throws {
    let candidate = SelectionCandidate(
      rect: CGRect(x: 10, y: 10, width: 500, height: 300), kind: .window, precedence: 0)
    let thin = try XCTUnwrap(
      SmartSelectionGeometry.resolvedSelection(
        dragged: CGRect(x: 200, y: 100, width: 100, height: 4), candidate: candidate))
    XCTAssertEqual(thin.rect, CGRect(x: 200, y: 100, width: 100, height: 4))
    XCTAssertNil(thin.kind)
  }
}
