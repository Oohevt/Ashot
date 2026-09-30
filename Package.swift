// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Ashot", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Ashot", targets: ["Ashot"]),
    .executable(name: "AshotOracle", targets: ["AshotOracle"]),
    .executable(name: "AshotFixture", targets: ["AshotFixture"]),
  ],
  targets: [
    .target(name: "AshotCore"),
    .executableTarget(name: "Ashot", dependencies: ["AshotCore"]),
    .executableTarget(name: "AshotOracle"),
    .executableTarget(name: "AshotFixture"),
    .testTarget(name: "AshotCoreTests", dependencies: ["AshotCore"]),
    .testTarget(name: "AshotAppTests", dependencies: ["Ashot", "AshotCore"]),
  ], swiftLanguageModes: [.v5])
