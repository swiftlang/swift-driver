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

import SwiftOptions
import TSCBasic
import TestUtilities
import Testing

@testable @_spi(Testing) import SwiftDriver

@Suite struct SanitizerTests {

  @Test func sanitizerRecoverArgs() async throws {
    let commonArgs = ["swiftc", "foo.swift", "bar.swift"]
    do {
      // address sanitizer + address sanitizer recover
      var driver = try TestDriver(args: commonArgs + ["-sanitize=address", "-sanitize-recover=address"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      #expect(plannedJobs.count == 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      #expect(compileCmd.contains(.flag("-sanitize=address")))
      #expect(compileCmd.contains(.flag("-sanitize-recover=address")))
    }
    do {
      // invalid sanitize recover arg
      try await assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=foo"]) {
        $1.expect(.error("invalid value 'foo' in '-sanitize-recover='"))
      }
    }
    do {
      // only address is supported
      try await assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=thread"]) {
        $1.expect(.error("unsupported argument 'thread' to option '-sanitize-recover='"))
      }
    }
    do {
      // only address is supported
      try await assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=scudo"]) {
        $1.expect(.error("unsupported argument 'scudo' to option '-sanitize-recover='"))
      }
    }
    do {
      // invalid sanitize recover arg
      try await assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=undefined"]) {
        $1.expect(.error("unsupported argument 'undefined' to option '-sanitize-recover='"))
      }
    }
    do {
      // no sanitizer + address sanitizer recover
      try await assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=address"]) {
        $1.expect(
          .warning(
            "option '-sanitize-recover=address' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"
          )
        )
      }
    }
    do {
      // thread sanitizer + address sanitizer recover
      try await assertDriverDiagnostics(args: commonArgs + ["-sanitize=thread", "-sanitize-recover=address"]) {
        #if os(Windows)
        $1.expect(.error("thread sanitizer is unavailable on target 'x86_64-unknown-windows-msvc'"))
        #endif
        $1.expect(
          .warning(
            "option '-sanitize-recover=address' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"
          )
        )
      }
    }
    // "-sanitize=undefined" is not available on x86_64-unknown-linux-gnu
    #if os(macOS)
    do {
      // multiple sanitizers separately
      try await assertDriverDiagnostics(
        args: commonArgs + ["-sanitize=undefined", "-sanitize=address", "-sanitize-recover=address"]
      ) {
        $1.forbidUnexpected(.error, .warning)
      }
    }
    do {
      // comma sanitizer + address sanitizer recover together
      try await assertDriverDiagnostics(
        args: commonArgs + ["-sanitize=undefined,address", "-sanitize-recover=address"]
      ) {
        $1.forbidUnexpected(.error, .warning)
      }
    }
    #endif
  }

  private static func hasSanitizerRuntime() -> Bool {
    guard
      var driver = try? TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-emit-executable", "-module-name", "Test", "-use-ld=lld",
        "-sanitize=address",
      ])
    else {
      return false
    }
    guard
      let exist = try? driver.unwrap({
        try $0.toolchain.runtimeLibraryExists(
          for: .address,
          targetInfo: $0.frontendTargetInfo,
          parsedOptions: &$0.parsedOptions,
          isShared: true
        )
      })
    else {
      return false;
    }
    return exist
  }

  @Test(.enabled(if: hasSanitizerRuntime())) func sanitizerArgs() async throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift", "-emit-executable", "-module-name", "Test", "-use-ld=lld",
    ]

    #if os(macOS) || os(Windows)
    do {
      // address sanitizer
      var driver = try TestDriver(args: commonArgs + ["-sanitize=address"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()

      expectEqual(jobs.count, 3)
      expectJobInvocationMatches(jobs[0], .flag("-sanitize=address"))
      expectJobInvocationMatches(jobs[2], .flag("-fsanitize=address"))
    }

    do {
      // address sanitizer on a dylib
      var driver = try TestDriver(args: commonArgs + ["-sanitize=address", "-emit-library"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()

      expectEqual(jobs.count, 3)
      expectJobInvocationMatches(jobs[0], .flag("-sanitize=address"))
      expectJobInvocationMatches(jobs[2], .flag("-fsanitize=address"))
    }

    do {
      // *no* address sanitizer on a static lib
      var driver = try TestDriver(args: commonArgs + ["-sanitize=address", "-emit-library", "-static"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()

      expectEqual(jobs.count, 3)
      #expect(!jobs[2].commandLine.contains(.flag("-fsanitize=address")))
    }

    #if !os(Windows)
    do {
      // thread sanitizer
      var driver = try TestDriver(args: commonArgs + ["-sanitize=thread"])
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      #expect(compileCmd.contains(.flag("-sanitize=thread")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      #expect(linkCmd.contains(.flag("-fsanitize=thread")))
    }
    #endif

    do {
      // undefined behavior sanitizer
      var driver = try TestDriver(args: commonArgs + ["-sanitize=undefined"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()

      expectEqual(jobs.count, 3)
      expectJobInvocationMatches(jobs[0], .flag("-sanitize=undefined"))
      expectJobInvocationMatches(jobs[2], .flag("-fsanitize=undefined"))
    }

    do {
      // memory tagging stack sanitizer
      var driver = try TestDriver(args: commonArgs + ["-sanitize=memtag-stack"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()

      expectEqual(jobs.count, 3)
      expectJobInvocationMatches(jobs[0], .flag("-sanitize=memtag-stack"))
      // No runtime for memtag-stack - thus no linker arg required
    }

    do {
      // fuzzer-no-link sanitizer
      var driver = try TestDriver(args: commonArgs + ["-sanitize=fuzzer-no-link"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()

      expectEqual(jobs.count, 3)
      expectJobInvocationMatches(jobs[0], .flag("-sanitize=fuzzer-no-link"))
      // No runtime for fuzzer-no-link - thus no linker arg required
    }

    // FIXME: This test will fail when run on macOS, because the driver uses
    //        the existence of the runtime support libraries to determine if
    //        a sanitizer is supported. Until we allow cross-compiling with
    //        sanitizers, we'll need to disable this test on macOS
    #if os(Linux)
    do {
      // linux multiple sanitizers
      var driver = try TestDriver(
        args: commonArgs + [
          "-target", "x86_64-unknown-linux",
          "-sanitize=address", "-sanitize=undefined",
        ]
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      #expect(compileCmd.contains(.flag("-sanitize=address")))
      #expect(compileCmd.contains(.flag("-sanitize=undefined")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      #expect(linkCmd.contains(.flag("-fsanitize=address,undefined")))
    }

    do {
      // linux scudo hardened allocator
      var driver = try TestDriver(
        args: commonArgs + [
          "-target", "x86_64-unknown-linux",
          "-sanitize=scudo",
        ]
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      #expect(compileCmd.contains(.flag("-sanitize=scudo")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      #expect(linkCmd.contains(.flag("-fsanitize=scudo")))
    }
    #endif
    #endif

    // FIXME: This test will fail when not run on Android, because the driver uses
    //        the existence of the runtime support libraries to determine if
    //        a sanitizer is supported. Until we allow cross-compiling with
    //        sanitizers, this test is disabled outside Android.
    #if os(Android)
    do {
      var driver = try TestDriver(
        args: commonArgs + [
          "-target", "aarch64-unknown-linux-android", "-sanitize=address",
        ]
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      #expect(compileCmd.contains(.flag("-sanitize=address")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      #expect(linkCmd.contains(.flag("-fsanitize=address")))
    }
    #endif

    // FIXME: This test will fail when not run on FreeBSD, because the driver uses
    //        the existence of the runtime support libraries to determine if
    //        a sanitizer is supported. Until we allow cross-compiling with
    //        sanitizers, this test is disabled outside FreeBSD.
    #if os(FreeBSD)
    do {
      var driver = try TestDriver(
        args: commonArgs + [
          "-target", "x86_64-unknown-freebsd14.3", "-sanitize=address",
        ]
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      #expect(compileCmd.contains(.flag("-sanitize=address")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      #expect(linkCmd.contains(.flag("-fsanitize=address")))
    }
    #endif

    func checkWASITarget(target: String, clangOSDir: String) async throws {
      try await withTemporaryDirectory { resourceDir in
        var env = ProcessEnv.block
        env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"

        let asanRuntimeLibPath = resourceDir.appending(components: [
          "clang", "lib", clangOSDir, "libclang_rt.asan-wasm32.a",
        ])
        try localFileSystem.writeFileContents(asanRuntimeLibPath) {
          $0.send("garbage")
        }
        try localFileSystem.writeFileContents(resourceDir.appending(components: "wasi", "static-executable-args.lnk")) {
          $0.send("garbage")
        }

        var driver = try TestDriver(
          args: commonArgs + [
            "-target", target, "-sanitize=address",
            "-resource-dir", resourceDir.pathString,
          ],
          env: env
        )
        let plannedJobs = try await driver.planBuild()

        #expect(plannedJobs.count == 4)

        let compileJob = plannedJobs[0]
        let compileCmd = compileJob.commandLine
        #expect(compileCmd.contains(.flag("-sanitize=address")))

        let linkJob = plannedJobs[3]
        let linkCmd = linkJob.commandLine
        #expect(linkCmd.contains(.flag("-fsanitize=address")))
      }
    }
    do {
      try await checkWASITarget(target: "wasm32-unknown-wasi", clangOSDir: "wasi")
      try await checkWASITarget(target: "wasm32-unknown-wasip1", clangOSDir: "wasip1")
      try await checkWASITarget(target: "wasm32-unknown-wasip1-threads", clangOSDir: "wasip1")
    }
  }

  @Test func sanitizerCoverageArgs() async throws {
    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-sanitize-coverage=func,trace-cmp"]) {
      $1.expect(
        .error("option '-sanitize-coverage=' requires a sanitizer to be enabled. Use -sanitize= to enable a sanitizer")
      )
    }

    #if !os(Windows)  // tsan is not yet available on Windows
    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-sanitize=thread", "-sanitize-coverage=bar"]) {
      $1.expect(.error("option '-sanitize-coverage=' is missing a required argument (\"func\", \"bb\", \"edge\")"))
      $1.expect(.error("unsupported argument 'bar' to option '-sanitize-coverage='"))
    }

    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-sanitize=thread", "-sanitize-coverage=func,baz"])
    {
      $1.expect(.error("unsupported argument 'baz' to option '-sanitize-coverage='"))
    }

    try await assertNoDriverDiagnostics(
      args: "swiftc",
      "foo.swift",
      "-sanitize=thread",
      "-sanitize-coverage=edge,indirect-calls,trace-bb,trace-cmp,8bit-counters,pc-table,inline-8bit-counters"
    )
    #endif
  }

  @Test func sanitizerAddressUseOdrIndicator() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-sanitize=address", "-sanitize-address-use-odr-indicator", "Test.swift",
      ])

      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)
      #expect(plannedJobs[0].commandLine.contains(.flag("-sanitize=address")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-sanitize-address-use-odr-indicator")))
    }

    do {
      try await assertDriverDiagnostics(args: [
        "swiftc", "-sanitize=thread", "-sanitize-address-use-odr-indicator", "Test.swift",
      ]) {
        $1.expect(
          .warning(
            "option '-sanitize-address-use-odr-indicator' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"
          )
        )
        #if os(Windows)
        $1.expect(.error("thread sanitizer is unavailable on target 'x86_64-unknown-windows-msvc'"))
        #endif
      }
    }

    do {
      try await assertDriverDiagnostics(args: ["swiftc", "-sanitize-address-use-odr-indicator", "Test.swift"]) {
        $1.expect(
          .warning(
            "option '-sanitize-address-use-odr-indicator' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"
          )
        )
      }
    }
  }

  @Test(.requireHostOS(.darwin, comment: "-sanitize-stable-abi is only implemented on Darwin")) func sanitizeStableAbi()
    async throws
  {
    var driver = try TestDriver(args: ["swiftc", "-sanitize=address", "-sanitize-stable-abi", "Test.swift"])
    guard driver.isFrontendArgSupported(.sanitizeStableAbiEQ) else {
      return
    }

    do {
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)
      #expect(plannedJobs[0].commandLine.contains(.flag("-sanitize=address")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-sanitize-stable-abi")))

      #expect(plannedJobs[1].commandLine.contains(.flag("-fsanitize=address")))
      #expect(plannedJobs[1].commandLine.contains(.flag("-fsanitize-stable-abi")))
    }

    do {
      try await assertDriverDiagnostics(args: ["swiftc", "-sanitize-stable-abi", "Test.swift"]) {
        $1.expect(
          .warning(
            "option '-sanitize-stable-abi' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"
          )
        )
      }
    }
  }

  @Test func sanitizerArgsForTargets() async throws {
    let targets = [
      "x86_64-unknown-freebsd", "x86_64-unknown-linux", "x86_64-apple-macosx10.9", "x86_64-unknown-windows-msvc",
    ]
    for target in targets {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", target, "foo.swift"])
      _ = try await driver.planBuild()
      #expect(!driver.diagnosticEngine.hasErrors)
    }
  }
}
