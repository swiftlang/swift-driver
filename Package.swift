// swift-tools-version:5.1
import PackageDescription

let package = Package(
  name: "swift-driver",
  platforms: [
    .macOS(.v10_13),
  ],
  products: [
    .executable(
      name: "swift-driver",
      targets: ["swift-driver"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("master")),
    .package(url: "https://github.com/apple/swift-llbuild.git", "0.2.0"..<"0.3.0"),
  ],
  targets: [
    /// The driver library.
    .target(
      name: "SwiftDriver",
      dependencies: ["SwiftToolsSupport-auto", "llbuildSwift"]),
    .testTarget(
      name: "SwiftDriverTests",
      dependencies: ["SwiftDriver"]),

    /// The primary driver executable.
    .target(
      name: "swift-driver",
      dependencies: ["SwiftDriver"]),

    /// The `makeOptions` utility (for importing option definitions).
    .target(
      name: "makeOptions",
      dependencies: []),
  ],
  cxxLanguageStandard: .cxx14
)
