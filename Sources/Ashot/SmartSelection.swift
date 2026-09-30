import AppKit
import AshotCore
import CoreGraphics
import ScreenCaptureKit

/// Bridges live system state into the pure candidate geometry once, before the
/// overlay appears. Nothing here runs per mouse-moved event.
enum SmartSelection {
  static func candidates(for snapshot: CaptureSnapshot) -> [SelectionCandidate] {
    let (order, visibleBounds) = onScreenWindows()
    let own = ProcessInfo.processInfo.processIdentifier
    let listed = snapshot.content.windows.map { w in
      SmartSelectionGeometry.WindowInfo(
        frame: w.frame,
        layer: w.windowLayer,
        // Windows missing from the front-to-back list sort last rather than
        // corrupting the ordering (e.g. Stage Manager thumbnails).
        z: order[Int(w.windowID)] ?? .max,
        ownApp: w.owningApplication?.processID == own,
        windowID: w.windowID)
    }
    // The frozen listing is the source of truth; any window whose ID is not
    // on screen right now, or whose bounds moved between the capture and this
    // sample, is a stale/Stage Manager entry and never a lock target.
    let windows = SmartSelectionGeometry.validatedWindows(listed, visibleBounds: visibleBounds)
    let gaps = SmartSelectionGeometry.SystemGaps.from(
      frame: snapshot.screen.frame, visibleFrame: snapshot.screen.visibleFrame)
    // The Dock backplate goes through the same ID/bounds cross-check as window
    // candidates: a hidden Dock leaves a full-screen tracking window in the
    // frozen listing, and only the WindowServer sample can disqualify it.
    let dockInfos = snapshot.content.windows
      .filter { $0.owningApplication?.bundleIdentifier == "com.apple.dock" }
      .map { w in
        SmartSelectionGeometry.WindowInfo(
          frame: w.frame, layer: w.windowLayer,
          z: order[Int(w.windowID)] ?? .max, ownApp: false, windowID: w.windowID)
      }
    return SmartSelectionGeometry.candidates(
      windows: windows, display: snapshot.display.frame, systemGaps: gaps,
      dockVisibleRect: SmartSelectionGeometry.validatedDockRect(
        dockInfos, display: snapshot.display.frame, visibleBounds: visibleBounds))
  }
  /// CGWindowListCopyWindowInfo returns on-screen windows front to back; the
  /// first index seen for an ID is its rank, and its bounds are recorded for
  /// the same-moment cross-check. One call yields both so the ordering and the
  /// bounds can never come from different samples. Reading bounds and layers
  /// needs no permission beyond what the capture flow already has.
  static func onScreenWindows() -> (order: [Int: Int], visibleBounds: [UInt32: CGRect]) {
    guard
      let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    else { return ([:], [:]) }
    var order: [Int: Int] = [:]
    var bounds: [UInt32: CGRect] = [:]
    for (index, entry) in list.enumerated() {
      guard let id = entry[kCGWindowNumber as String] as? Int else { continue }
      if order[id] == nil { order[id] = index }
      if bounds[UInt32(id)] == nil,
        let rectDict = entry[kCGWindowBounds as String] as? [String: NSNumber],
        let rect = CGRect(dictionaryRepresentation: rectDict as CFDictionary),
        // Zero-size on-screen entries are window-server noise (shadow and
        // container layers); they cannot be cross-checked against anything.
        rect.width > 0, rect.height > 0
      {
        bounds[UInt32(id)] = rect
      }
    }
    return (order, bounds)
  }
}
