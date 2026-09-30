import CoreGraphics
import Foundation

public enum Geometry {
  /// Converts a top-left display-local selection to ScreenCaptureKit/Quartz
  /// global coordinates. `container` is SCDisplay.frame, never NSScreen.frame.
  public static func globalRect(_ rect: CGRect, in container: CGRect) -> CGRect {
    CGRect(
      x: container.minX + rect.minX, y: container.minY + rect.minY,
      width: rect.width, height: rect.height)
  }
  public static func globalPoint(_ point: CGPoint, in container: CGRect) -> CGPoint {
    CGPoint(x: container.minX + point.x, y: container.minY + point.y)
  }
  /// Both the global rect and SCWindow.frame have a top-left origin.
  public static func windowLocalRect(global: CGRect, window: CGRect) -> CGRect? {
    guard window.contains(global), global.width > 0, global.height > 0 else { return nil }
    return global.offsetBy(dx: -window.minX, dy: -window.minY)
  }
  /// Input is top-left logical points; output is top-left image pixels.
  public static func pixelRect(_ rect: CGRect, logicalSize: CGSize, pixelSize: CGSize) -> CGRect? {
    guard logicalSize.width > 0, logicalSize.height > 0, pixelSize.width > 0, pixelSize.height > 0
    else { return nil }
    let clipped = rect.standardized.intersection(CGRect(origin: .zero, size: logicalSize))
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
    let sx = pixelSize.width / logicalSize.width
    let sy = pixelSize.height / logicalSize.height
    let x0 = floor(clipped.minX * sx)
    let y0 = floor(clipped.minY * sy)
    let x1 = ceil(clipped.maxX * sx)
    let y1 = ceil(clipped.maxY * sy)
    return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }
}

// MARK: - Hover candidates for the capture overlay

/// A clickable target highlighted while the cursor hovers over it. `rect` is
/// top-left display-local logical points, the space SelectionView draws in.
public struct SelectionCandidate: Equatable {
  public enum Kind: String, Equatable {
    case window, dock, menuBar
  }
  public var rect: CGRect
  public var kind: Kind
  /// Larger wins under the cursor. System regions render above every window;
  /// for windows the value encodes the window-server front-to-back rank.
  public var precedence: Int
  public init(rect: CGRect, kind: Kind, precedence: Int) {
    self.rect = rect
    self.kind = kind
    self.precedence = precedence
  }
}

public enum SmartSelectionGeometry {
  public struct WindowInfo {
    /// ScreenCaptureKit top-left global points.
    public var frame: CGRect
    public var layer: Int
    /// Front-to-back rank from the window server; 0 is frontmost.
    public var z: Int
    public var ownApp: Bool
    /// WindowServer ID used to cross-check the frozen listing against the
    /// same-moment on-screen listing; 0 means unknown.
    public var windowID: UInt32
    public init(frame: CGRect, layer: Int, z: Int, ownApp: Bool, windowID: UInt32) {
      self.frame = frame
      self.layer = layer
      self.z = z
      self.ownApp = ownApp
      self.windowID = windowID
    }
  }
  /// Menu bar / Dock thickness measured as the gap between a screen's frame
  /// and its visibleFrame — derived from the live system, never a fixed
  /// height, so auto-hidden or fullscreen states simply report zero.
  public struct SystemGaps: Equatable {
    public var top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat
    public init(top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) {
      self.top = top
      self.bottom = bottom
      self.left = left
      self.right = right
    }
    /// Both rects are AppKit coordinates of the same screen.
    public static func from(frame: CGRect, visibleFrame: CGRect) -> SystemGaps {
      SystemGaps(
        top: max(0, frame.maxY - visibleFrame.maxY),
        bottom: max(0, visibleFrame.minY - frame.minY),
        left: max(0, visibleFrame.minX - frame.minX),
        right: max(0, frame.maxX - visibleFrame.maxX))
    }
  }
  /// Below this on-screen size a window is not offered as a candidate.
  public static let minimumCandidateSize: CGFloat = 24
  /// Gaps thinner than this are treated as rounding noise / hidden, not as a
  /// visible system region.
  public static let minimumGap: CGFloat = 8
  /// A drag must exceed this many points before it counts as a manual
  /// free-selection and overrides the pressed candidate.
  public static let minimumDrag: CGFloat = 8

  public static func candidates(
    windows: [WindowInfo], display: CGRect, systemGaps: SystemGaps,
    dockVisibleRect: CGRect? = nil
  ) -> [SelectionCandidate] {
    var result: [SelectionCandidate] = []
    for info in windows {
      // Layer 0-3 covers normal windows and floating panels (independent
      // dialogs); higher layers are menu bar, Dock, status items and junk.
      guard !info.ownApp, (0...3).contains(info.layer) else { continue }
      let visible = info.frame.intersection(display)
      guard !visible.isNull, visible.width >= minimumCandidateSize,
        visible.height >= minimumCandidateSize
      else { continue }
      result.append(
        SelectionCandidate(
          rect: visible.offsetBy(dx: -display.minX, dy: -display.minY),
          kind: .window,
          precedence: max(0, 1_000_000 - min(info.z, 999_999))))
    }
    let size = display.size
    if systemGaps.top >= minimumGap {
      result.append(
        SelectionCandidate(
          rect: CGRect(x: 0, y: 0, width: size.width, height: systemGaps.top),
          kind: .menuBar, precedence: 2_000_000))
    }
    // The Dock candidate is the actual backplate rect measured at trigger
    // time. The visibleFrame reserve strip is NOT a substitute: it spans the
    // full display width while the real Dock usually does not. No trustworthy
    // rect means no Dock candidate — the user falls back to a manual drag.
    if let dockVisibleRect {
      let visible = dockVisibleRect.intersection(display)
      if !visible.isNull, min(visible.width, visible.height) >= minimumGap {
        result.append(
          SelectionCandidate(
            rect: visible.offsetBy(dx: -display.minX, dy: -display.minY),
            kind: .dock, precedence: 2_000_000))
      }
    }
    return result
  }
  /// Drops windows whose WindowServer ID is missing from the same-moment
  /// on-screen listing (Stage Manager strip thumbnails, stale entries) or
  /// whose bounds disagree beyond `tolerance` points (window moved between
  /// the frozen capture and the on-screen sample). Such windows are not
  /// trustworthy lock targets.
  public static func validatedWindows(
    _ windows: [WindowInfo], visibleBounds: [UInt32: CGRect], tolerance: CGFloat = 2
  ) -> [WindowInfo] {
    windows.filter { info in
      guard info.windowID != 0, let bounds = visibleBounds[info.windowID] else {
        return false
      }
      return abs(bounds.minX - info.frame.minX) <= tolerance
        && abs(bounds.minY - info.frame.minY) <= tolerance
        && abs(bounds.width - info.frame.width) <= tolerance
        && abs(bounds.height - info.frame.height) <= tolerance
    }
  }
  /// Dock backplate rect from snapshot-listed Dock windows, kept only when the
  /// same-moment WindowServer listing shows the identical window by ID and
  /// bounds. A hidden Dock leaves a full-screen tracking window in the frozen
  /// snapshot; it fails this check and yields no candidate at all.
  public static func validatedDockRect(
    _ dockWindows: [WindowInfo], display: CGRect, visibleBounds: [UInt32: CGRect],
    tolerance: CGFloat = 2
  ) -> CGRect? {
    guard
      let largest = validatedWindows(dockWindows, visibleBounds: visibleBounds, tolerance: tolerance)
        // The Dock's full-screen tracking window can stay on screen while the
        // Dock is shown; it is never the backplate.
        .filter({ $0.frame.width * $0.frame.height < display.width * display.height * 0.9 })
        .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    else { return nil }
    let visible = largest.frame.intersection(display)
    guard !visible.isNull, min(visible.width, visible.height) >= minimumGap else { return nil }
    return visible
  }
  /// Frontmost candidate under the point: highest precedence wins, then the
  /// smaller area (a dialog over its parent), then any deterministic pick.
  public static func pick(
    at point: CGPoint, candidates: [SelectionCandidate]
  ) -> SelectionCandidate? {
    candidates
      .filter { $0.rect.contains(point) }
      .min { lhs, rhs in
        if lhs.precedence != rhs.precedence { return lhs.precedence > rhs.precedence }
        let la = lhs.rect.width * lhs.rect.height
        let ra = rhs.rect.width * rhs.rect.height
        if la != ra { return la < ra }
        return lhs.kind.rawValue < rhs.kind.rawValue
      }
  }
  /// Mouse-up resolution: a drag beyond `minimumDrag` on ANY single axis is a
  /// manual selection — even a thin strip — and always wins over the pressed
  /// candidate; only sub-threshold jitter on both axes counts as a click that
  /// locks the candidate. A thin drag must never lock the whole window the
  /// press started in.
  public static func resolvedSelection(
    dragged: CGRect?, candidate: SelectionCandidate?
  ) -> (rect: CGRect, kind: SelectionCandidate.Kind?)? {
    if let dragged,
      dragged.width > minimumDrag || dragged.height > minimumDrag
    {
      return (dragged, nil)
    }
    if let candidate { return (candidate.rect, candidate.kind) }
    return nil
  }
}
