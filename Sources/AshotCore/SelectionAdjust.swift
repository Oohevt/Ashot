import CoreGraphics

/// Post-lock adjustment of a selection: which part the press grabbed, and the
/// rect that results from dragging it. Top-left, display-local points.
public enum SelectionAdjust {
  public enum Handle: String, CaseIterable, Sendable {
    case move, n, s, e, w, ne, nw, se, sw
  }
  /// Corners beat edges beat interior; a press outside the grab band is nil,
  /// which means "start a new selection".
  public static func hit(_ p: CGPoint, rect: CGRect, grab: CGFloat = 8) -> Handle? {
    guard rect.insetBy(dx: -grab, dy: -grab).contains(p) else { return nil }
    let left = abs(p.x - rect.minX) <= grab
    let right = abs(p.x - rect.maxX) <= grab
    let top = abs(p.y - rect.minY) <= grab
    let bottom = abs(p.y - rect.maxY) <= grab
    switch (left, right, top, bottom) {
    case (true, _, true, _): return .nw
    case (_, true, true, _): return .ne
    case (true, _, _, true): return .sw
    case (_, true, _, true): return .se
    case (true, _, _, _): return .w
    case (_, true, _, _): return .e
    case (_, _, true, _): return .n
    case (_, _, _, true): return .s
    default: return rect.contains(p) ? .move : nil
    }
  }
  /// Moving keeps the size and stays inside `bounds`. Edges may cross the
  /// opposite edge (the rect flips), and the result never leaves `bounds`.
  public static func adjusted(
    _ rect: CGRect, handle: Handle, from start: CGPoint, to point: CGPoint, bounds: CGRect
  ) -> CGRect {
    let dx = point.x - start.x
    let dy = point.y - start.y
    if handle == .move {
      let x = min(max(rect.minX + dx, bounds.minX), bounds.maxX - rect.width)
      let y = min(max(rect.minY + dy, bounds.minY), bounds.maxY - rect.height)
      return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
    var x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
    switch handle {
    case .w, .nw, .sw: x0 += dx
    case .e, .ne, .se: x1 += dx
    default: break
    }
    switch handle {
    case .n, .nw, .ne: y0 += dy
    case .s, .sw, .se: y1 += dy
    default: break
    }
    let r = CGRect(
      x: min(x0, x1), y: min(y0, y1), width: max(abs(x1 - x0), 1), height: max(abs(y1 - y0), 1))
    return r.intersection(bounds)
  }
}
