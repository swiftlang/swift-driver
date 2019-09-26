// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "swift-driver",
    targets: [
        /// The primary driver executable.
        .target(
            name: "driver",
            dependencies: []),
        .testTarget(
            name: "driverTests",
            dependencies: ["driver"]),

        /// The `makeOptions` utility (for importing option definitions).
        .target(
            name: "makeOptions",
            dependencies: []),
    ],
    cxxLanguageStandard: .cxx14
)
