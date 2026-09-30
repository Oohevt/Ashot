import AppKit
import ImageIO
import UniformTypeIdentifiers

// Independent fixture generator/checker: no import of AshotCore or stitch implementation.
let width = 1000, rowHeight = 64, rows = 120
enum OracleError: Error { case invalid(String) }
func read(_ path: String) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw OracleError.invalid("Cannot read \(path)") }
    return image
}
func pixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { ptr in
        let ctx = CGContext(data: ptr.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}
func write(_ image: CGImage, _ path: String) throws {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw OracleError.invalid("Create output failed") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw OracleError.invalid("Write output failed") }
}
func generate(_ kind: String, _ path: String) throws {
    let h = rows * rowHeight
    let ctx = CGContext(data: nil, width: width, height: h, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: width, height: h))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    for row in 0..<rows {
        let y = row * rowHeight
        let seed = UInt32(row + 1) &* 2654435761
        for bit in 0..<32 {
            let dark = ((seed >> bit) & 1) == 1
            ctx.setFillColor((dark ? NSColor(calibratedWhite: 0.15, alpha: 1) : NSColor(calibratedWhite: 0.9, alpha: 1)).cgColor)
            ctx.fill(CGRect(x: 12 + bit * 4, y: y + 6, width: 4, height: 52))
        }
        ctx.setFillColor(NSColor(calibratedRed: CGFloat((row * 37) % 180 + 30) / 255, green: CGFloat((row * 71) % 180 + 30) / 255, blue: CGFloat((row * 13) % 180 + 30) / 255, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 950, y: y, width: 50, height: rowHeight))
        ctx.setStrokeColor(NSColor.lightGray.cgColor); ctx.setLineWidth(1); ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: width, y: y)); ctx.strokePath()
        let text: String
        switch kind {
        case "article": text = String(format: "%03d  自建文章 · 截图内容必须完整保存 / Paragraph %03d", row + 1, row + 1)
        case "table": text = String(format: "%03d  产品_%03d     数量 %04d     金额 %06d", row + 1, row + 1, row * 7, row * 103)
        default: text = String(format: "%03d  let sample_%03d = value + %d // 保留缩进与行号", row + 1, row + 1, row * 17)
        }
        (text as NSString).draw(at: CGPoint(x: 156, y: y + 19), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    try write(ctx.makeImage()!, path)
}
func compare(_ actualPath: String, _ expectedPath: String) throws {
    let a = try read(actualPath), e = try read(expectedPath)
    guard a.width == e.width, a.height == e.height else { throw OracleError.invalid("Size mismatch actual=\(a.width)x\(a.height), expected=\(e.width)x\(e.height)") }
    let ap = pixels(a), ep = pixels(e)
    var mismatches = 0
    for i in stride(from: 0, to: ap.count, by: 4) {
        if (0..<3).contains(where: { abs(Int(ap[i + $0]) - Int(ep[i + $0])) > 3 }) { mismatches += 1 }
    }
    let rate = Double(mismatches) / Double(a.width * a.height)
    guard rate <= 0.001 else { throw OracleError.invalid("Pixel mismatch rate \(rate), limit=0.001") }
    print("PASS size=\(a.width)x\(a.height) pixels=\(a.width*a.height) mismatch=\(mismatches) rows=120")
}
do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "generate":
        guard args.count == 2 else { throw OracleError.invalid("generate <directory>") }
        try FileManager.default.createDirectory(atPath: args[1], withIntermediateDirectories: true)
        for kind in ["article", "table", "code"] { try generate(kind, args[1] + "/" + kind + ".png") }
        print("Generated 3 independent fixtures, 1000x7680, 120 rows each")
    case "compare":
        guard args.count == 3 else { throw OracleError.invalid("compare <actual.png> <expected.png>") }; try compare(args[1], args[2])
    case "corrupt":
        guard args.count == 3 else { throw OracleError.invalid("corrupt <input> <output>") }
        let image = try read(args[1]); let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x: 0, y: 100, width: image.width, height: 128)); try write(ctx.makeImage()!, args[2])
    default: throw OracleError.invalid("Commands: generate, compare, corrupt")
    }
} catch { fputs("FAIL \(error)\n", stderr); exit(1) }
