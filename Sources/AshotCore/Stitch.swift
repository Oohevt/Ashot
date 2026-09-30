import CoreGraphics
import Foundation

public struct Raster {
  public let width: Int, height: Int
  public let bytes: [UInt8]
  /// Matching normalizes to sRGB so frames from different sources stay comparable.
  public init(_ image: CGImage) throws {
    let width = image.width
    let height = image.height
    self.width = width
    self.height = height
    guard width > 0, height > 0, width <= 8192, width * height <= 16_000_000 else {
      throw StitchError.limit
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let ok = bytes.withUnsafeMutableBytes { ptr -> Bool in
      guard
        let ctx = CGContext(
          data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard ok else { throw StitchError.limit }
    self.bytes = bytes
  }
  func error(to next: Raster, shift: Int, rows: Int = 28, columns: Int = 32) -> Double {
    let overlap = height - shift
    guard overlap > 0 else { return 1 }
    var bad = 0
    var total = 0
    let maximumBad = Int(Double(min(rows, overlap) * columns) * 0.06)
    for r in 0..<min(rows, overlap) {
      let y = Int(Double(r + 1) * Double(overlap) / Double(min(rows, overlap) + 1))
      for c in 0..<columns {
        let x = Int(Double(c + 1) * Double(width) / Double(columns + 1))
        let a = ((y + shift) * width + x) * 4
        let b = (y * width + x) * 4
        if abs(Int(bytes[a]) - Int(next.bytes[b])) > 5
          || abs(Int(bytes[a + 1]) - Int(next.bytes[b + 1])) > 5
          || abs(Int(bytes[a + 2]) - Int(next.bytes[b + 2])) > 5
        {
          bad += 1
        }
        total += 1
        if bad > maximumBad { return 0.07 }
      }
    }
    return Double(bad) / Double(max(total, 1))
  }
}
public enum StitchError: Error, Equatable { case dimensions, unaligned, ambiguous, limit }
public enum FrameMatch: Equatable {
  case unchanged
  case append(Int)
}
/// Why a frame was accepted or rejected. Fields record the actual numbers seen at
/// each decision point so a failure can be attributed without reproducing it.
public struct MatchReport: Equatable {
  public let sameError: Double
  public let bestShift: Int
  public let bestError: Double
  public let runnerUpShift: Int
  public let runnerUpError: Double
  public let verifyError: Double?
  public let matched: FrameMatch?
  public let rejected: StitchError?
}
public enum VerticalMatcher {
  /// Maximum sampled-mismatch ratio for a candidate shift to count as a match.
  static let acceptError: Double = 0.008
  public static func match(previous: CGImage, next: CGImage) throws -> FrameMatch {
    try match(previous: try Raster(previous), next: try Raster(next))
  }
  public static func match(previous a: Raster, next b: Raster) throws -> FrameMatch {
    guard a.width == b.width, a.height == b.height else { throw StitchError.dimensions }
    let report = evaluate(previous: a, next: b)
    if let error = report.rejected { throw error }
    guard let matched = report.matched else { throw StitchError.unaligned }
    return matched
  }
  public static func evaluate(previous a: Raster, next b: Raster) -> MatchReport {
    let same = a.error(to: b, shift: 0, rows: 64, columns: 64)
    if same <= 0.001 {
      return MatchReport(
        sameError: same, bestShift: 0, bestError: same, runnerUpShift: -1, runnerUpError: 1,
        verifyError: nil, matched: .unchanged, rejected: nil)
    }
    let upper = Int(Double(a.height) * 0.75)
    guard upper > 1 else {
      return MatchReport(
        sameError: same, bestShift: 0, bestError: 1, runnerUpShift: -1, runnerUpError: 1,
        verifyError: nil, matched: nil, rejected: .unaligned)
    }
    var candidates: [(Int, Double)] = []
    candidates.reserveCapacity(upper)
    for shift in 1...upper { candidates.append((shift, a.error(to: b, shift: shift))) }
    candidates.sort { $0.1 < $1.1 }
    let best = candidates[0]
    let runnerUp = candidates.first(where: { abs($0.0 - best.0) > 2 }) ?? (0, 1)
    guard best.1 <= acceptError else {
      return MatchReport(
        sameError: same, bestShift: best.0, bestError: best.1, runnerUpShift: runnerUp.0,
        runnerUpError: runnerUp.1, verifyError: nil, matched: nil, rejected: .unaligned)
    }
    /// Ambiguity requires two *viable* candidates. Repetitive text produces periodic
    /// near-matches; the old absolute margin (best + 0.03) vetoed even a pixel-perfect
    /// best whenever any runner-up scored below it.
    if runnerUp.1 <= acceptError {
      return MatchReport(
        sameError: same, bestShift: best.0, bestError: best.1, runnerUpShift: runnerUp.0,
        runnerUpError: runnerUp.1, verifyError: nil, matched: nil, rejected: .ambiguous)
    }
    let verify = a.error(to: b, shift: best.0, rows: min(a.height - best.0, 300), columns: 80)
    guard verify <= acceptError else {
      return MatchReport(
        sameError: same, bestShift: best.0, bestError: best.1, runnerUpShift: runnerUp.0,
        runnerUpError: runnerUp.1, verifyError: verify, matched: nil, rejected: .unaligned)
    }
    return MatchReport(
      sameError: same, bestShift: best.0, bestError: best.1, runnerUpShift: runnerUp.0,
      runnerUpError: runnerUp.1, verifyError: verify, matched: .append(best.0), rejected: nil)
  }
}
public final class StitchAccumulator {
  public private(set) var width = 0
  public private(set) var height = 0
  public private(set) var frameCount = 0
  /// The last matcher decision, for telemetry; not part of stitching state.
  public private(set) var lastReport: MatchReport?
  /// Held instead of the previous CGImage: rasterizing it once per frame was the
  /// dominant cost, and a cropped CGImage keeps its whole source frame alive.
  private var previous: Raster?
  private var strips: [CGImage] = []
  private var space: CGColorSpace?
  public init() {}
  public func accept(_ image: CGImage) throws -> FrameMatch {
    let raster = try Raster(image)
    guard let previous else {
      width = raster.width
      height = raster.height
      space = RGBBitmapContext.space(of: image)
      self.previous = raster
      strips = [image]
      frameCount = 1
      lastReport = nil
      return .append(raster.height)
    }
    guard raster.width == previous.width, raster.height == previous.height else {
      lastReport = nil
      throw StitchError.dimensions
    }
    let report = VerticalMatcher.evaluate(previous: previous, next: raster)
    lastReport = report
    guard let match = report.matched else { throw report.rejected ?? .unaligned }
    if case .append(let delta) = match {
      guard width * (height + delta) <= 16_000_000 else { throw StitchError.limit }
      guard
        let crop = image.cropping(
          to: CGRect(x: 0, y: image.height - delta, width: width, height: delta)),
        let ctx = RGBBitmapContext.make(width: width, height: delta, space: space)
      else { throw StitchError.limit }
      ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: delta))
      guard let strip = ctx.makeImage() else { throw StitchError.limit }
      strips.append(strip)
      height += delta
      frameCount += 1
      self.previous = raster
    }
    return match
  }
  public func result() throws -> CGImage {
    guard width > 0, height > 0, width * height <= 16_000_000,
      let ctx = RGBBitmapContext.make(width: width, height: height, space: space)
    else { throw StitchError.limit }
    var y = height
    for strip in strips {
      y -= strip.height
      ctx.draw(strip, in: CGRect(x: 0, y: y, width: width, height: strip.height))
    }
    guard let result = ctx.makeImage() else { throw StitchError.limit }
    return result
  }
}
