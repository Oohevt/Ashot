import CoreGraphics

/// Common source-gamut policy for stitched strips and annotation rendering.
enum RGBBitmapContext {
  static func make(width: Int, height: Int, space: CGColorSpace?) -> CGContext? {
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    for candidate in [space, CGColorSpace(name: CGColorSpace.sRGB)!].compactMap({ $0 }) {
      if let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: candidate, bitmapInfo: info)
      {
        return ctx
      }
    }
    return nil
  }
  static func space(of image: CGImage) -> CGColorSpace? {
    guard let space = image.colorSpace, space.model == .rgb else { return nil }
    return space
  }
}
