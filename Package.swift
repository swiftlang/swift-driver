// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "swift-driver",
    dependencies: [
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("master")),
    ],
    targets: [
        /// The driver library.
        .target(
            name: "SwiftDriver",
            dependencies: ["SwiftToolsSupport-auto"]),
        .testTarget(
            name: "SwiftDriverTests",
            dependencies: ["SwiftDriver"]),

        /// The primary driver executable.
        .target(
            name: "driver",
            dependencies: ["SwiftDriver"]),

        /// The `makeOptions` utility (for importing option definitions).
        .target(
            name: "makeOptions",
            dependencies: []),
    ],
    cxxLanguageStandard: .cxx14
)
