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
