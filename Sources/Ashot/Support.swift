import AppKit
import AshotCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum AppPaths {
  static let root = (Bundle.main.object(forInfoDictionaryKey: "AshotWorkspaceRoot") as? String).map
  { URL(fileURLWithPath: $0) }
  static let evidence = root?.appendingPathComponent("evidence")
}
func record(_ event: String, _ fields: [String: Any] = [:]) {
  guard let evidence = AppPaths.evidence else { return }
  var value = fields
  value["event"] = event
  value["time"] = {
    let f = ISO8601DateFormatter()
    f.formatOptions.insert(.withFractionalSeconds)
    return f.string(from: Date())
  }()
  value["build"] =
    Bundle.main.object(forInfoDictionaryKey: "AshotBuildID") as? String ?? "unidentified"
  do {
    try FileManager.default.createDirectory(
      at: evidence, withIntermediateDirectories: true)
    var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    data.append(10)
    let url = evidence.appendingPathComponent("runtime.jsonl")
    if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
  } catch { NSLog("Ashot telemetry failure: %@", error.localizedDescription) }
}
func presentError(_ message: String) {
  record("error", ["message": message])
  let alert = NSAlert()
  alert.messageText = "暂时无法完成"
  alert.informativeText = message
  alert.addButton(withTitle: "知道了")
  alert.runModal()
}
enum ImageExport {
  static func png(_ image: CGImage, pixelsPerPoint: CGSize = CGSize(width: 1, height: 1)) throws
    -> Data
  {
    guard pixelsPerPoint.width.isFinite, pixelsPerPoint.height.isFinite,
      pixelsPerPoint.width > 0, pixelsPerPoint.height > 0
    else { throw CocoaError(.coderInvalidValue) }
    let data = NSMutableData()
    guard
      let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    let properties: [CFString: Any] = [
      kCGImagePropertyDPIWidth: 72 * pixelsPerPoint.width,
      kCGImagePropertyDPIHeight: 72 * pixelsPerPoint.height,
    ]
    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
  }
  static func copy(
    _ image: CGImage, pixelsPerPoint: CGSize = CGSize(width: 1, height: 1),
    pasteboard: NSPasteboard = .general
  ) throws {
    let data = try png(image, pixelsPerPoint: pixelsPerPoint)
    pasteboard.clearContents()
    guard pasteboard.setData(data, forType: .png) else {
      throw CocoaError(.fileWriteUnknown)
    }
    record(
      "copy",
      [
        "width": image.width, "height": image.height, "dpiX": 72 * pixelsPerPoint.width,
        "dpiY": 72 * pixelsPerPoint.height,
      ])
  }
  static func save(
    _ image: CGImage, pixelsPerPoint: CGSize = CGSize(width: 1, height: 1), to url: URL
  ) throws {
    try png(image, pixelsPerPoint: pixelsPerPoint).write(to: url, options: .atomic)
    record("save", ["file": url.lastPathComponent, "width": image.width, "height": image.height])
  }
}
