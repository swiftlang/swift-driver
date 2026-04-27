//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import SwiftDriverExecution
import SwiftOptions
import TSCBasic
import TestUtilities
import Testing

@testable @_spi(Testing) import SwiftDriver

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#endif

@Suite struct TargetTests {

  private var ld: AbsolutePath { get throws { try makeLdStub() } }

  @Test func targetTriple() throws {
    let driver1 = try TestDriver(args: ["swiftc", "-c", "foo.swift", "-module-name", "Foo"])

    let expectedDefaultContents: String
    #if os(macOS)
    expectedDefaultContents = "-apple-macosx"
    #elseif os(Linux) || os(Android)
    expectedDefaultContents = "-unknown-linux"
    #elseif os(Windows)
    expectedDefaultContents = "-unknown-windows-msvc"
    #else
    expectedDefaultContents = "-"
    #endif

    #expect(
      driver1.targetTriple.triple.contains(expectedDefaultContents),
      "Default triple \(driver1.targetTriple) contains \(expectedDefaultContents)"
    )

    let driver2 = try TestDriver(args: [
      "swiftc", "-c", "-target", "x86_64-apple-watchos12", "foo.swift", "-module-name", "Foo",
    ])
    expectEqual(
      driver2.targetTriple.triple,
      "x86_64-apple-watchos12-simulator"
    )

    let driver3 = try TestDriver(args: [
      "swiftc", "-c", "-target", "x86_64-watchos12", "foo.swift", "-module-name", "Foo",
    ])
    expectEqual(
      driver3.targetTriple.triple,
      "x86_64-unknown-watchos12-simulator"
    )
  }

  @Test func targetVariant() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    do {
      var driver = try TestDriver(
        args: [
          "swiftc", "-c", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant", "x86_64-apple-macosx10.14",
          "foo.swift",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)

      #expect(plannedJobs[0].kind == .compile)
      #expect(plannedJobs[0].commandLine.contains(.flag("-target")))
      #expect(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      #expect(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))
    }

    do {
      var driver = try TestDriver(
        args: [
          "swiftc", "-emit-library", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant",
          "x86_64-apple-macosx10.14", "-module-name", "foo", "foo.swift",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)

      #expect(plannedJobs[0].kind == .compile)
      #expect(plannedJobs[0].commandLine.contains(.flag("-target")))
      #expect(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      #expect(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("--target=x86_64-apple-ios13.1-macabi")))
      expectJobInvocationMatches(plannedJobs[1], .flag("-darwin-target-variant"), .flag("x86_64-apple-macosx10.14"))
    }

    // Test -target-variant is passed to generate pch job
    do {
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant", "x86_64-apple-macosx10.14",
          "-enable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "foo.swift",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)

      #expect(plannedJobs[0].kind == .generatePCH)
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-target")))
      #expect(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      #expect(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      #expect(plannedJobs[1].kind == .compile)
      #expect(plannedJobs[1].commandLine.contains(.flag("-target")))
      #expect(plannedJobs[1].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      #expect(plannedJobs[1].commandLine.contains(.flag("-target-variant")))
      #expect(plannedJobs[1].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      #expect(plannedJobs[2].kind == .link)
      #expect(plannedJobs[2].commandLine.contains(.flag("--target=x86_64-apple-ios13.1-macabi")))
      expectJobInvocationMatches(plannedJobs[2], .flag("-darwin-target-variant"), .flag("x86_64-apple-macosx10.14"))
    }
  }

  @Test func targetVariantEmitModule() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc",
        "-target", "x86_64-apple-macosx10.14",
        "-target-variant", "x86_64-apple-ios13.1-macabi",
        "-enable-library-evolution", "-experimental-emit-variant-module",
        "-emit-module",
        "-emit-module-path", "foo.swiftmodule/target.swiftmodule",
        "-emit-variant-module-path", "foo.swiftmodule/variant.swiftmodule",
        "foo.swift",
      ])

      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)

      let targetModuleJob = plannedJobs[0]
      let variantModuleJob = plannedJobs[1]

      #expect(targetModuleJob.commandLine.contains(.flag("-emit-module")))
      #expect(variantModuleJob.commandLine.contains(.flag("-emit-module")))

      #expect(
        targetModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/target.swiftdoc"))))
      )
      #expect(
        targetModuleJob.commandLine.contains(
          .path(.relative(try .init(validating: "foo.swiftmodule/target.swiftsourceinfo")))
        )
      )
      #expect(
        targetModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/target.abi.json"))))
      )
      #expect(
        targetModuleJob.commandLine.contains(subsequence: [
          .flag("-o"), .path(.relative(try .init(validating: "foo.swiftmodule/target.swiftmodule"))),
        ])
      )

      #expect(
        variantModuleJob.commandLine.contains(
          .path(.relative(try .init(validating: "foo.swiftmodule/variant.swiftdoc")))
        )
      )
      #expect(
        variantModuleJob.commandLine.contains(
          .path(.relative(try .init(validating: "foo.swiftmodule/variant.swiftsourceinfo")))
        )
      )
      #expect(
        variantModuleJob.commandLine.contains(
          .path(.relative(try .init(validating: "foo.swiftmodule/variant.abi.json")))
        )
      )
      #expect(
        variantModuleJob.commandLine.contains(subsequence: [
          .flag("-o"), .path(.relative(try .init(validating: "foo.swiftmodule/variant.swiftmodule"))),
        ])
      )
    }

    do {
      // explicitly emit variant supplemental outputs
      var driver = try TestDriver(args: [
        "swiftc",
        "-target", "x86_64-apple-macosx10.14",
        "-target-variant", "x86_64-apple-ios13.1-macabi",
        "-enable-library-evolution", "-experimental-emit-variant-module",
        "-package-name", "Susan",
        "-emit-module",
        "-emit-module-path", "target.swiftmodule",
        "-emit-variant-module-path", "variant.swiftmodule",
        "-Xfrontend", "-emit-module-doc-path", "-Xfrontend", "target.swiftdoc",
        "-Xfrontend", "-emit-variant-module-doc-path", "-Xfrontend", "variant.swiftdoc",
        "-emit-module-source-info-path", "target.sourceinfo",
        "-emit-variant-module-source-info-path", "variant.sourceinfo",
        "-emit-package-module-interface-path", "target.package.swiftinterface",
        "-emit-variant-package-module-interface-path", "variant.package.swiftinterface",
        "-emit-private-module-interface-path", "target.private.swiftinterface",
        "-emit-variant-private-module-interface-path", "variant.private.swiftinterface",
        "-emit-module-interface-path", "target.swiftinterface",
        "-emit-variant-module-interface-path", "variant.swiftinterface",
        "foo.swift",
      ])

      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      // emit module
      // emit module
      // compile foo.swift
      // verify target.swiftinterface
      // verify target.private.swiftinterface
      // verify target.package.swiftinterface
      // verify variant.swiftinterface
      // verify variant.private.swiftinterface
      // verify variant.package.swiftinterface
      expectEqual(plannedJobs.count, 9)

      let targetModuleJob: Job = plannedJobs[0]
      let variantModuleJob = plannedJobs[1]

      try expectEqual(
        targetModuleJob.outputs.filter { $0.type == .swiftModule }.last!.file,
        try toPath("target.swiftmodule")
      )
      try expectEqual(
        variantModuleJob.outputs.filter { $0.type == .swiftModule }.last!.file,
        try toPath("variant.swiftmodule")
      )

      try expectEqual(
        targetModuleJob.outputs.filter { $0.type == .swiftDocumentation }.last!.file,
        try toPath("target.swiftdoc")
      )
      try expectEqual(
        variantModuleJob.outputs.filter { $0.type == .swiftDocumentation }.last!.file,
        try toPath("variant.swiftdoc")
      )

      try expectEqual(
        targetModuleJob.outputs.filter { $0.type == .swiftSourceInfoFile }.last!.file,
        try toPath("target.sourceinfo")
      )
      try expectEqual(
        variantModuleJob.outputs.filter { $0.type == .swiftSourceInfoFile }.last!.file,
        try toPath("variant.sourceinfo")
      )

      try expectEqual(
        targetModuleJob.outputs.filter { $0.type == .swiftInterface }.last!.file,
        try toPath("target.swiftinterface")
      )
      try expectEqual(
        variantModuleJob.outputs.filter { $0.type == .swiftInterface }.last!.file,
        try toPath("variant.swiftinterface")
      )

      try expectEqual(
        targetModuleJob.outputs.filter { $0.type == .privateSwiftInterface }.last!.file,
        try toPath("target.private.swiftinterface")
      )
      try expectEqual(
        variantModuleJob.outputs.filter { $0.type == .privateSwiftInterface }.last!.file,
        try toPath("variant.private.swiftinterface")
      )

      try expectEqual(
        targetModuleJob.outputs.filter { $0.type == .packageSwiftInterface }.last!.file,
        try toPath("target.package.swiftinterface")
      )
      try expectEqual(
        variantModuleJob.outputs.filter { $0.type == .packageSwiftInterface }.last!.file,
        try toPath("variant.package.swiftinterface")
      )

      try expectEqual(
        targetModuleJob.outputs.filter { $0.type == .jsonABIBaseline }.last!.file,
        try toPath("target.abi.json")
      )
      try expectEqual(
        variantModuleJob.outputs.filter { $0.type == .jsonABIBaseline }.last!.file,
        try toPath("variant.abi.json")
      )
    }

    #if os(macOS)
    do {
      try await withTemporaryDirectory { path in
        var env = ProcessEnv.block
        env["LD_TRACE_FILE"] = path.appending(component: ".LD_TRACE").nativePathString(escaped: false)
        var driver = try TestDriver(
          args: [
            "swiftc",
            "-target", "x86_64-apple-macosx10.14",
            "-target-variant", "x86_64-apple-ios13.1-macabi",
            "-emit-variant-module-path", "foo.swiftmodule/x86_64-apple-ios13.1-macabi.swiftmodule",
            "-enable-library-evolution", "-experimental-emit-variant-module",
            "-emit-module",
            "foo.swift",
          ],
          env: env
        )

        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let targetModuleJob = plannedJobs[0]
        let variantModuleJob = plannedJobs[1]

        #expect(
          targetModuleJob.commandLine.contains(subsequence: [
            .flag("-emit-api-descriptor-path"),
            .path(
              .absolute(
                path.appending(
                  components: "SDKDB",
                  "foo.\(driver.frontendTargetInfo.target.moduleTriple.triple).swift.sdkdb"
                )
              )
            ),
          ])
        )

        #expect(
          variantModuleJob.commandLine.contains(subsequence: [
            .flag("-emit-api-descriptor-path"),
            .path(
              .absolute(
                path.appending(
                  components: "SDKDB",
                  "foo.\(driver.frontendTargetInfo.targetVariant!.moduleTriple.triple).swift.sdkdb"
                )
              )
            ),
          ])
        )
      }
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc",
        "-target", "x86_64-apple-macosx10.14",
        "-target-variant", "x86_64-apple-ios13.1-macabi",
        "-emit-variant-module-path", "foo.swiftmodule/x86_64-apple-ios13.1-macabi.swiftmodule",
        "-enable-library-evolution", "-experimental-emit-variant-module",
        "-emit-module",
        "-emit-api-descriptor-path", "foo.swiftmodule/target.api.json",
        "-emit-variant-api-descriptor-path", "foo.swiftmodule/variant.api.json",
        "foo.swift",
      ])

      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let targetModuleJob = plannedJobs[0]
      let variantModuleJob = plannedJobs[1]

      #expect(
        targetModuleJob.commandLine.contains(subsequence: [
          .flag("-emit-api-descriptor-path"),
          .path(.relative(try .init(validating: "foo.swiftmodule/target.api.json"))),
        ])
      )

      #expect(
        variantModuleJob.commandLine.contains(subsequence: [
          .flag("-emit-api-descriptor-path"),
          .path(.relative(try .init(validating: "foo.swiftmodule/variant.api.json"))),
        ])
      )
    }
    #endif
  }

  @Test func validDeprecatedTargetiOS() async throws {
    var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", "armv7-apple-ios13.0", "foo.swift"])
    let plannedJobs = try await driver.planBuild()
    let emitModuleJob = try plannedJobs.findJob(.emitModule)
    #expect(emitModuleJob.commandLine.contains(.flag("-target")))
    #expect(emitModuleJob.commandLine.contains(.flag("armv7-apple-ios13.0")))
  }

  @Test func validDeprecatedTargetWatchOS() async throws {
    var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", "armv7k-apple-watchos10.0", "foo.swift"])
    let plannedJobs = try await driver.planBuild()
    let emitModuleJob = try plannedJobs.findJob(.emitModule)
    #expect(emitModuleJob.commandLine.contains(.flag("-target")))
    #expect(emitModuleJob.commandLine.contains(.flag("armv7k-apple-watchos10.0")))
  }

  @Test(
    .requireHostOS(.macosx),
    .requireFrontendArgSupport(.clangTarget),
    .requireFrontendArgSupport(.clangTargetVariant)
  )
  func clangTargetForExplicitModule() async throws {
    let sdkRoot = try testInputsPath.appending(component: "SDKChecks").appending(component: "MacOSX10.15.sdk")

    // Check -clang-target is on by default when explicit module is on.
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(main, bytes: "import Swift")
      var driver = try TestDriver(args: [
        "swiftc", "-explicit-module-build",
        "-target", "arm64-apple-macos10.14",
        "-sdk", sdkRoot.pathString,
        main.pathString,
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(
        plannedJobs.contains { job in
          job.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("arm64-apple-macos10.15")])
        }
      )
    }

    // Check -clang-target is handled correctly with the MacCatalyst remap.
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(
        main,
        bytes:
          """
          import Swift
          """
      )
      var driver = try TestDriver(args: [
        "swiftc", "-explicit-module-build",
        "-target", "arm64e-apple-ios13.0-macabi",
        "-sdk", sdkRoot.pathString,
        main.pathString,
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(
        plannedJobs.contains { job in
          job.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("arm64e-apple-ios13.3-macabi")])
        }
      )
    }

    // Check -disable-clang-target works
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(main, bytes: "import Swift")
      var driver = try TestDriver(args: [
        "swiftc", "-disable-clang-target",
        "-explicit-module-build",
        "-target", "arm64-apple-macos10.14",
        "-sdk", sdkRoot.pathString,
        main.pathString,
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(
        !plannedJobs.contains { job in
          job.commandLine.contains(.flag("-clang-target"))
        }
      )
    }

    // Check -clang-target-variant is handled correctly with the MacCatalyst remap.
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(
        main,
        bytes:
          """
          import Swift
          """
      )
      var driver = try TestDriver(args: [
        "swiftc", "-explicit-module-build",
        "-target", "arm64e-apple-ios13.0-macabi",
        "-target-variant", "arm64e-apple-macos10.0",
        "-sdk", sdkRoot.pathString,
        main.pathString,
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(
        plannedJobs.contains { job in
          job.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("arm64e-apple-ios13.3-macabi")])
            && job.commandLine.contains(subsequence: [.flag("-clang-target-variant"), .flag("arm64e-apple-macos10.15")])
        }
      )
    }
  }

  @Test(.requireHostOS(.macosx)) func disableClangTargetForImplicitModule() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    let sdkRoot = try testInputsPath.appending(component: "SDKChecks").appending(component: "iPhoneOS.sdk")
    var driver = try TestDriver(
      args: [
        "swiftc", "-target",
        "arm64-apple-ios12.0", "foo.swift",
        "-sdk", sdkRoot.pathString,
      ],
      env: envVars
    )
    let plannedJobs = try await driver.planBuild()
    #expect(plannedJobs.count == 2)
    expectJobInvocationMatches(plannedJobs[0], .flag("-target"))
    #expect(!plannedJobs[0].commandLine.contains(.flag("-clang-target")))
  }

  @Test func environmentInferenceWarning() async throws {
    let sdkRoot = try testInputsPath.appending(component: "SDKChecks").appending(component: "iPhoneOS.sdk")

    try await assertDriverDiagnostics(args: [
      "swiftc", "-target", "x86_64-apple-ios13.0", "foo.swift", "-sdk", sdkRoot.pathString,
    ]) {
      $1.expect(
        .warning(
          "inferring simulator environment for target 'x86_64-apple-ios13.0'; use '-target x86_64-apple-ios13.0-simulator'"
        )
      )
    }
    try await assertDriverDiagnostics(args: [
      "swiftc", "-target", "x86_64-apple-watchos6.0", "foo.swift", "-sdk", sdkRoot.pathString,
    ]) {
      $1.expect(
        .warning(
          "inferring simulator environment for target 'x86_64-apple-watchos6.0'; use '-target x86_64-apple-watchos6.0-simulator'"
        )
      )
    }
    try await assertNoDriverDiagnostics(
      args: "swiftc",
      "-target",
      "x86_64-apple-ios13.0-simulator",
      "foo.swift",
      "-sdk",
      sdkRoot.pathString
    )
  }

  @Test func darwinToolchainArgumentValidation() async throws {
    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "arm64-apple-ios6.0",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(
          platform: .iOS(.device),
          version: Triple.Version(7, 0, 0)
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "x86_64-apple-ios6.0-simulator",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(
          platform: .iOS(.simulator),
          version: Triple.Version(7, 0, 0)
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "arm64-apple-tvos6.0",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(
          platform: .tvOS(.device),
          version: Triple.Version(9, 0, 0)
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "x86_64-apple-tvos6.0-simulator",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(
          platform: .tvOS(.simulator),
          version: Triple.Version(9, 0, 0)
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "arm64-apple-watchos1.0",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(
          platform: .watchOS(.device),
          version: Triple.Version(2, 0, 0)
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "x86_64-apple-watchos1.0-simulator",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(
          platform: .watchOS(.simulator),
          version: Triple.Version(2, 0, 0)
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "x86_64-apple-macosx10.4",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(
          platform: .macOS,
          version: Triple.Version(10, 9, 0)
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "armv7-apple-ios12.1",
        "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(
          platform: .iOS(.device),
          version: Triple.Version(11, 0, 0),
          archName: "armv7"
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-emit-module", "-c", "-target",
        "armv7s-apple-ios12.0", "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(
          platform: .iOS(.device),
          version: Triple.Version(11, 0, 0),
          archName: "armv7s"
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-emit-module", "-c", "-target",
        "i386-apple-ios12.0-simulator", "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(
          platform: .iOS(.simulator),
          version: Triple.Version(11, 0, 0),
          archName: "i386"
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-emit-module", "-c", "-target",
        "armv7k-apple-watchos12.0", "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(
          platform: .watchOS(.device),
          version: Triple.Version(9, 0, 0),
          archName: "armv7k"
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-emit-module", "-c", "-target",
        "i386-apple-watchos12.0", "foo.swift",
      ])
    } throws: { error in
      guard
        case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(
          platform: .watchOS(.simulator),
          version: Triple.Version(7, 0, 0),
          archName: "i386"
        ) = error
      else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-target", "x86_64-apple-ios13.0",
        "-target-variant", "x86_64-apple-macosx10.14",
        "foo.swift",
      ])
    } throws: { error in
      guard case DarwinToolchain.ToolchainValidationError.unsupportedTargetVariant(variant: _) = error else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-static-stdlib", "-target", "x86_64-apple-macosx10.14",
        "foo.swift",
      ])
    } throws: { error in
      guard case DarwinToolchain.ToolchainValidationError.argumentNotSupported("-static-stdlib") = error else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    #expect {
      try TestDriver(args: [
        "swiftc", "-c", "-static-executable", "-target", "x86_64-apple-macosx10.14",
        "foo.swift",
      ])
    } throws: { error in
      guard case DarwinToolchain.ToolchainValidationError.argumentNotSupported("-static-executable") = error else {
        Issue.record("Unexpected error: \(error)")
        return false
      }
      return true
    }

    // Not actually a valid arch for tvOS, but we shouldn't fall into the iOS case by mistake and emit a message about iOS >= 11 not supporting armv7.
    #expect(throws: Never.self) {
      try TestDriver(args: ["swiftc", "-c", "-target", "armv7-apple-tvos9.0", "foo.swift"])
    }

    // Ensure arm64_32 is not restricted to back-deployment like other 32-bit archs (armv7k/i386).
    #expect(throws: Never.self) {
      try TestDriver(args: ["swiftc", "-emit-module", "-c", "-target", "arm64_32-apple-watchos12.0", "foo.swift"])
    }

    // On non-darwin hosts, libArcLite won't be found and a warning will be emitted
    #if os(macOS)
    try await assertNoDriverDiagnostics(
      args: "swiftc",
      "-c",
      "-target",
      "x86_64-apple-macosx10.14",
      "-link-objc-runtime",
      "foo.swift"
    )
    #endif
  }

  // Test cases ported from Driver/macabi-environment.swift
  @Test func darwinSDKVersioning() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    try await withTemporaryDirectory { tmpDir in
      let sdk1 = tmpDir.appending(component: "MacOSX10.15.sdk")
      try localFileSystem.createDirectory(sdk1, recursive: true)
      try localFileSystem.writeFileContents(
        sdk1.appending(component: "SDKSettings.json"),
        bytes:
          """
          {
            "Version":"10.15",
            "CanonicalName": "macosx10.15",
            "VersionMap" : {
                "macOS_iOSMac" : {
                    "10.15" : "13.1",
                    "10.15.1" : "13.2"
                },
                "iOSMac_macOS" : {
                    "13.1" : "10.15",
                    "13.2" : "10.15.1"
                }
            }
          }
          """
      )

      let sdk2 = tmpDir.appending(component: "MacOSX10.15.4.sdk")
      try localFileSystem.createDirectory(sdk2, recursive: true)
      try localFileSystem.writeFileContents(
        sdk2.appending(component: "SDKSettings.json"),
        bytes:
          """
          {
            "Version":"10.15.4",
            "CanonicalName": "macosx10.15.4",
            "VersionMap" : {
                "macOS_iOSMac" : {
                    "10.14.4" : "12.4",
                    "10.14.3" : "12.3",
                    "10.14.2" : "12.2",
                    "10.14.1" : "12.1",
                    "10.15" : "13.0",
                    "10.14" : "12.0",
                    "10.14.5" : "12.5",
                    "10.15.1" : "13.2",
                    "10.15.4" : "13.4"
                },
                "iOSMac_macOS" : {
                    "13.0" : "10.15",
                    "12.3" : "10.14.3",
                    "12.0" : "10.14",
                    "12.4" : "10.14.4",
                    "12.1" : "10.14.1",
                    "12.5" : "10.14.5",
                    "12.2" : "10.14.2",
                    "13.2" : "10.15.1",
                    "13.4" : "10.15.4"
                }
            }
          }
          """
      )

      do {
        var driver = try TestDriver(
          args: [
            "swiftc",
            "-target", "x86_64-apple-macosx10.14",
            "-sdk", sdk1.description,
            "foo.swift",
          ],
          env: envVars
        )
        let frontendJobs = try await driver.planBuild()
        expectEqual(frontendJobs[0].kind, .compile)
        expectJobInvocationMatches(frontendJobs[0], .flag("-target-sdk-version"), .flag("10.15"))
        if driver.isFrontendArgSupported(.targetSdkName) {
          expectJobInvocationMatches(frontendJobs[0], .flag("-target-sdk-name"), .flag("macosx10.15"))
        }
        expectEqual(frontendJobs[1].kind, .link)
        expectJobInvocationMatches(frontendJobs[1], .flag("--target=x86_64-apple-macosx10.14"))
        expectJobInvocationMatches(frontendJobs[1], .flag("--sysroot"))
        #expect(frontendJobs[1].commandLine.containsPathWithBasename(sdk1.basename))
      }

      do {
        var envVars = ProcessEnv.block
        envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

        var driver = try TestDriver(
          args: [
            "swiftc",
            "-target", "x86_64-apple-macosx10.14",
            "-target-variant", "x86_64-apple-ios13.1-macabi",
            "-sdk", sdk1.description,
            "foo.swift",
          ],
          env: envVars
        )
        let frontendJobs = try await driver.planBuild()
        expectEqual(frontendJobs[0].kind, .compile)
        expectJobInvocationMatches(
          frontendJobs[0],
          .flag("-target-sdk-version"),
          .flag("10.15"),
          .flag("-target-variant-sdk-version"),
          .flag("13.1")
        )
        expectEqual(frontendJobs[1].kind, .link)
        expectJobInvocationMatches(frontendJobs[1], .flag("--target=x86_64-apple-macosx10.14"))
        expectJobInvocationMatches(
          frontendJobs[1],
          .flag("-darwin-target-variant"),
          .flag("x86_64-apple-ios13.1-macabi")
        )
      }

      do {
        var driver = try TestDriver(
          args: [
            "swiftc",
            "-target", "x86_64-apple-macosx10.14",
            "-target-variant", "x86_64-apple-ios13.1-macabi",
            "-sdk", sdk2.description,
            "foo.swift",
          ],
          env: envVars
        )
        let frontendJobs = try await driver.planBuild()
        expectEqual(frontendJobs[0].kind, .compile)
        expectJobInvocationMatches(
          frontendJobs[0],
          .flag("-target-sdk-version"),
          .flag("10.15.4"),
          .flag("-target-variant-sdk-version"),
          .flag("13.4")
        )
        if driver.isFrontendArgSupported(.targetSdkName) {
          expectJobInvocationMatches(frontendJobs[0], .flag("-target-sdk-name"), .flag("macosx10.15.4"))
        }
        expectEqual(frontendJobs[1].kind, .link)
        expectJobInvocationMatches(frontendJobs[1], .flag("--target=x86_64-apple-macosx10.14"))
        expectJobInvocationMatches(
          frontendJobs[1],
          .flag("-darwin-target-variant"),
          .flag("x86_64-apple-ios13.1-macabi")
        )
      }

      do {
        var envVars = ProcessEnv.block
        envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

        var driver = try TestDriver(
          args: [
            "swiftc",
            "-target-variant", "x86_64-apple-macosx10.14",
            "-target", "x86_64-apple-ios13.1-macabi",
            "-sdk", sdk2.description,
            "foo.swift",
          ],
          env: envVars
        )
        let frontendJobs = try await driver.planBuild()
        expectEqual(frontendJobs[0].kind, .compile)
        expectJobInvocationMatches(
          frontendJobs[0],
          .flag("-target-sdk-version"),
          .flag("13.4"),
          .flag("-target-variant-sdk-version"),
          .flag("10.15.4")
        )
        if driver.isFrontendArgSupported(.targetSdkName) {
          expectJobInvocationMatches(frontendJobs[0], .flag("-target-sdk-name"), .flag("macosx10.15.4"))
        }
        expectEqual(frontendJobs[1].kind, .link)
        expectJobInvocationMatches(frontendJobs[1], .flag("--target=x86_64-apple-ios13.1-macabi"))
        expectJobInvocationMatches(frontendJobs[1], .flag("-darwin-target-variant"), .flag("x86_64-apple-macosx10.14"))
      }
    }
  }

  @Test func darwinSDKTooOld() async throws {
    func getSDKPath(sdkDirName: String) throws -> AbsolutePath {
      return try testInputsPath.appending(component: "SDKChecks").appending(component: sdkDirName)
    }

    // Ensure an error is emitted for an unsupported SDK
    func checkSDKUnsupported(
      sdkDirName: String
    )
      async throws
    {
      let sdkPath = try getSDKPath(sdkDirName: sdkDirName)
      // Get around the check for SDK's existence
      try localFileSystem.createDirectory(sdkPath)
      let args = ["swiftc", "foo.swift", "-target", "x86_64-apple-macosx10.9", "-sdk", sdkPath.pathString]
      try await assertDriverDiagnostics(args: args) { driver, verifier in
        verifier.expect(.error("Swift does not support the SDK \(sdkPath.pathString)"))
      }
    }

    // Ensure no error is emitted for a supported SDK
    func checkSDKOkay(sdkDirName: String) async throws {
      let sdkPath = try getSDKPath(sdkDirName: sdkDirName)
      try localFileSystem.createDirectory(sdkPath)
      let args = ["swiftc", "foo.swift", "-target", "x86_64-apple-macosx10.9", "-sdk", sdkPath.pathString]
      try await assertNoDiagnostics { de in let _ = try TestDriver(args: args, diagnosticsEngine: de) }
    }

    // Ensure old/bogus SDK versions are caught
    try await checkSDKUnsupported(sdkDirName: "tvOS8.0.sdk")
    try await checkSDKUnsupported(sdkDirName: "MacOSX10.8.sdk")
    try await checkSDKUnsupported(sdkDirName: "MacOSX10.9.sdk")
    try await checkSDKUnsupported(sdkDirName: "MacOSX10.10.sdk")
    try await checkSDKUnsupported(sdkDirName: "MacOSX10.11.sdk")
    try await checkSDKUnsupported(sdkDirName: "MacOSX7.17.sdk")
    try await checkSDKUnsupported(sdkDirName: "MacOSX10.14.Internal.sdk")
    try await checkSDKUnsupported(sdkDirName: "iPhoneOS7.sdk")
    try await checkSDKUnsupported(sdkDirName: "iPhoneSimulator7.sdk")
    try await checkSDKUnsupported(sdkDirName: "iPhoneOS12.99.sdk")
    try await checkSDKUnsupported(sdkDirName: "watchOS2.0.sdk")
    try await checkSDKUnsupported(sdkDirName: "watchOS3.0.sdk")
    try await checkSDKUnsupported(sdkDirName: "watchOS3.0.Internal.sdk")

    // Verify a selection of okay SDKs
    try await checkSDKOkay(sdkDirName: "MacOSX10.15.sdk")
    try await checkSDKOkay(sdkDirName: "MacOSX10.15.4.sdk")
    try await checkSDKOkay(sdkDirName: "MacOSX10.15.Internal.sdk")
    try await checkSDKOkay(sdkDirName: "iPhoneOS13.0.sdk")
    try await checkSDKOkay(sdkDirName: "tvOS13.0.sdk")
    try await checkSDKOkay(sdkDirName: "watchOS6.0.sdk")
    try await checkSDKOkay(sdkDirName: "watchSimulator6.0.sdk")
    try await checkSDKOkay(sdkDirName: "iPhoneOS.sdk")
    try await checkSDKOkay(sdkDirName: "tvOS.sdk")
    try await checkSDKOkay(sdkDirName: "watchOS.sdk")
  }

  @Test func darwinLinkerPlatformVersion() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "x86_64-apple-macos10.15",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=x86_64-apple-macos10.15"))
    }

    // Mac gained aarch64 support in v11
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "arm64-apple-macos10.15",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=arm64-apple-macos10.15"))
    }

    // Mac Catalyst on x86_64 was introduced in v13.
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "x86_64-apple-ios12.0-macabi",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=x86_64-apple-ios12.0-macabi"))
    }

    // Mac Catalyst on arm was introduced in v14.
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "aarch64-apple-ios12.0-macabi",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=aarch64-apple-ios12.0-macabi"))
    }

    // Regular iOS
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "aarch64-apple-ios12.0",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=aarch64-apple-ios12.0"))
    }

    // Regular tvOS
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "aarch64-apple-tvos12.0",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=aarch64-apple-tvos12.0"))
    }

    // Regular watchOS
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "aarch64-apple-watchos6.0",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=aarch64-apple-watchos6.0"))
    }

    // x86_64 iOS simulator
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "x86_64-apple-ios12.0-simulator",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=x86_64-apple-ios12.0-simulator"))
    }

    // aarch64 iOS simulator
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target", "aarch64-apple-ios12.0-simulator",
          "foo.swift",
        ],
        env: envVars
      )
      let frontendJobs = try await driver.planBuild()

      expectEqual(frontendJobs[1].kind, .link)
      expectJobInvocationMatches(frontendJobs[1], .flag("--target=aarch64-apple-ios12.0-simulator"))
    }
  }

  @Test func darwinSDKWithoutSDKSettings() async throws {
    try await withTemporaryDirectory { tmpDir in
      let sdk = tmpDir.appending(component: "MacOSX10.15.sdk")
      try localFileSystem.createDirectory(sdk, recursive: true)
      try await assertDriverDiagnostics(
        args: "swiftc",
        "-target",
        "x86_64-apple-macosx10.15",
        "foo.swift",
        "-sdk",
        sdk.pathString
      ) {
        $1.expect(.warning("Could not read SDKSettings.json for SDK at: \(sdk.pathString)"))
      }
    }
  }

  @Test func darwinSDKToolchainName() throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    try withTemporaryDirectory { tmpDir in
      let sdk = tmpDir.appending(component: "XROS1.0.sdk")
      try localFileSystem.createDirectory(sdk, recursive: true)
      try localFileSystem.writeFileContents(
        sdk.appending(component: "SDKSettings.json"),
        bytes:
          """
          {
            "Version":"1.0",
            "CanonicalName": "xros1.0"
          }
          """
      )

      let sdkInfo = DarwinToolchain.readSDKInfo(localFileSystem, VirtualPath.absolute(sdk).intern())
      expectEqual(sdkInfo?.platformKind, .visionos)
    }
  }

  @Test func nonDarwinSDK() async throws {
    try await withTemporaryDirectory { tmpDir in
      let sdk = tmpDir.appending(component: "NonDarwin.sdk")
      // SDK without SDKSettings.json should be ok for non-Darwin platforms
      try localFileSystem.createDirectory(sdk, recursive: true)
      for triple in ["x86_64-unknown-linux-gnu", "wasm32-unknown-wasi"] {
        try await assertDriverDiagnostics(args: "swiftc", "-target", triple, "foo.swift", "-sdk", sdk.pathString) {
          $1.forbidUnexpected(.error, .warning)
        }
      }
    }
  }

  @Test func isIosMacInterface() throws {
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes: "// swift-module-flags: -target x86_64-apple-ios15.0-macabi")
      #expect(try SwiftDriver.isIosMacInterface(VirtualPath.absolute(file)))
    }
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes: "// swift-module-flags: -target arm64e-apple-macos12.0")
      #expect(try !SwiftDriver.isIosMacInterface(VirtualPath.absolute(file)))
    }
  }

  @Test func windowsOptions() async throws {
    let driver =
      try TestDriver(args: ["swiftc", "-windows-sdk-version", "10.0.17763.0", #file])
    guard
      [
        .visualcToolsRoot,
        .visualcToolsVersion,
        .windowsSdkRoot,
        .windowsSdkVersion,
      ].map(driver.isFrontendArgSupported).reduce(true, { $0 && $1 })
    else {
      return
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-windows-sdk-root", "/SDK", #file,
      ])
      let frontend = try await driver.planBuild().first!
      try expectJobInvocationMatches(frontend, .flag("-windows-sdk-root"), .path(.absolute(.init(validating: "/SDK"))))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-windows-sdk-version", "10.0.17763.0", #file,
      ])
      let frontend = try await driver.planBuild().first!
      expectJobInvocationMatches(frontend, .flag("-windows-sdk-version"), .flag("10.0.17763.0"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-windows-sdk-version", "10.0.17763.0", "-windows-sdk-root",
        "/SDK", #file,
      ])
      let frontend = try await driver.planBuild().first!

      try expectJobInvocationMatches(frontend, .flag("-windows-sdk-root"), .path(.absolute(.init(validating: "/SDK"))))
      expectJobInvocationMatches(frontend, .flag("-windows-sdk-version"), .flag("10.0.17763.0"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-visualc-tools-root", "/MSVC/14.34.31933", #file,
      ])
      let frontend = try await driver.planBuild().first!
      try expectJobInvocationMatches(
        frontend,
        .flag("-visualc-tools-root"),
        .path(.absolute(.init(validating: "/MSVC/14.34.31933")))
      )
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-visualc-tools-version", "14.34.31933", #file,
      ])
      let frontend = try await driver.planBuild().first!

      expectJobInvocationMatches(frontend, .flag("-visualc-tools-version"), .flag("14.34.31933"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-visualc-tools-root", "/MSVC", "-visualc-tools-version",
        "14.34.31933", #file,
      ])
      let frontend = try await driver.planBuild().first!

      expectJobInvocationMatches(frontend, .flag("-visualc-tools-version"), .flag("14.34.31933"))
      try expectJobInvocationMatches(
        frontend,
        .flag("-visualc-tools-root"),
        .path(.absolute(.init(validating: "/MSVC")))
      )
    }
  }
}
