// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "swift-driver",
    targets: [
        /// The driver library.
        .target(
            name: "SwiftDriver",
            dependencies: []),
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
