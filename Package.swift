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
    .package(url: "https://github.com/apple/swift-llbuild.git", .branch("master")),
  ],
  targets: [
    /// The driver library.
    .target(
      name: "SwiftDriver",
      dependencies: ["SwiftToolsSupport-auto", "llbuildSwift"]),
    .testTarget(
      name: "SwiftDriverTests",
      dependencies: ["SwiftDriver", "swift-driver"]),

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
