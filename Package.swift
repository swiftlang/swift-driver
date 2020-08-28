// swift-tools-version:5.1
import PackageDescription
import class Foundation.ProcessInfo

let macOSPlatform: SupportedPlatform
if let deploymentTarget = ProcessInfo.processInfo.environment["SWIFTPM_MACOS_DEPLOYMENT_TARGET"] {
    macOSPlatform = .macOS(deploymentTarget)
} else {
    macOSPlatform = .macOS(.v10_10)
}

let package = Package(
  name: "swift-driver",
  platforms: [
    macOSPlatform,
  ],
  products: [
    .executable(
      name: "swift-driver",
      targets: ["swift-driver"]),
    .executable(
      name: "swift-help",
      targets: ["swift-help"]),
    .library(
      name: "SwiftDriver",
      targets: ["SwiftDriver"]),
    .library(
      name: "SwiftOptions",
      targets: ["SwiftOptions"]),
  ],
  targets: [
    /// The driver library.
    .target(
      name: "SwiftDriver",
      dependencies: ["SwiftOptions", "SwiftToolsSupport-auto", "Yams"]),
    .testTarget(
      name: "SwiftDriverTests",
      dependencies: ["SwiftDriver", "swift-driver"]),

    /// The options library.
    .target(
      name: "SwiftOptions",
      dependencies: ["SwiftToolsSupport-auto"]),
    .testTarget(
      name: "SwiftOptionsTests",
      dependencies: ["SwiftOptions"]),

    /// The primary driver executable.
    .target(
      name: "swift-driver",
      dependencies: ["SwiftDriver"]),

    /// The help executable.
    .target(
      name: "swift-help",
      dependencies: ["SwiftOptions"]),

    /// The `makeOptions` utility (for importing option definitions).
    .target(
      name: "makeOptions",
      dependencies: []),
  ],
  cxxLanguageStandard: .cxx14
)

if ProcessInfo.processInfo.environment["SWIFT_DRIVER_LLBUILD_FWK"] == nil {
    if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
        package.dependencies += [
            .package(url: "https://github.com/apple/swift-llbuild.git", .branch("master")),
        ]
    } else {
        // In Swift CI, use a local path to llbuild to interoperate with tools
        // like `update-checkout`, which control the sources externally.
        package.dependencies += [
            .package(path: "../llbuild"),
        ]
    }
    package.targets.first(where: { $0.name == "SwiftDriver" })!.dependencies += ["llbuildSwift"]
}

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("master")),
    .package(url: "https://github.com/jpsim/Yams.git", .upToNextMinor(from: "4.0.0")),
    ]
} else {
    package.dependencies += [
        .package(path: "../swiftpm/swift-tools-support-core"),
        .package(path: "../yams"),
    ]
}
