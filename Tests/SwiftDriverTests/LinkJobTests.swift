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

@Suite struct LinkJobTests {

  private var ld: AbsolutePath { get throws { try makeLdStub() } }

  @Test func linking() async throws {
    var env = ProcessEnv.block
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    env["SWIFT_DRIVER_DSYMUTIL_EXEC"] = "/garbage/dsymutil"

    let commonArgs = ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test"]

    do {
      // macOS target
      var driver = try TestDriver(
        args: commonArgs + [
          "-emit-library", "-target", "x86_64-apple-macosx10.15", "-Onone", "-use-ld=foo", "-ld-path=/bar/baz",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      expectEqual(3, plannedJobs.count)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-dynamiclib")))
      #expect(cmd.contains(.flag("-fuse-ld=foo")))
      #expect(cmd.contains(.joinedOptionAndPath("--ld-path=", try VirtualPath(path: "/bar/baz"))))
      #expect(cmd.contains(.flag("--target=x86_64-apple-macosx10.15")))
      #expect(try linkJob.outputs[0].file == toPath("libTest.dylib"))

      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-shared")))
      // Handling of '-lobjc' is now in the Clang linker driver.
      #expect(!cmd.contains(.flag("-lobjc")))
      #expect(cmd.contains(.flag("-O0")))
    }

    do {
      // .tbd inputs are passed down to the linker.
      var driver = try TestDriver(
        args: commonArgs + ["foo.dylib", "foo.tbd", "-target", "x86_64-apple-macosx10.15"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)
      let cmd = linkJob.commandLine
      #expect(cmd.contains(try toPathOption("foo.tbd")))
      #expect(cmd.contains(try toPathOption("foo.dylib")))
    }

    do {
      // iOS target
      var driver = try TestDriver(args: commonArgs + ["-emit-library", "-target", "arm64-apple-ios10.0"], env: env)
      let plannedJobs = try await driver.planBuild()

      expectEqual(3, plannedJobs.count)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-dynamiclib")))
      #expect(cmd.contains(.flag("--target=arm64-apple-ios10.0")))
      #expect(try linkJob.outputs[0].file == toPath("libTest.dylib"))

      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-shared")))
    }

    do {
      // macOS catalyst target
      var driver = try TestDriver(
        args: commonArgs + ["-emit-library", "-target", "x86_64-apple-ios13.1-macabi"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      expectEqual(3, plannedJobs.count)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-dynamiclib")))
      #expect(cmd.contains(.flag("--target=x86_64-apple-ios13.1-macabi")))
      #expect(try linkJob.outputs[0].file == toPath("libTest.dylib"))

      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-shared")))
    }

    do {
      // Xlinker flags
      var driver = try TestDriver(
        args: commonArgs + ["-emit-library", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      expectEqual(3, plannedJobs.count)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-dynamiclib")))
      #expect(cmd.contains(.flag("-w")))
      #expect(cmd.contains(.flag("-L")))
      #expect(cmd.contains(.path(.absolute(try .init(validating: "/tmp")))))
      #expect(try linkJob.outputs[0].file == toPath("libTest.dylib"))

      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-shared")))
    }

    do {
      // -fobjc-link-runtime default
      var driver = try TestDriver(
        args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      expectEqual(3, plannedJobs.count)
      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)
      let cmd = linkJob.commandLine
      #expect(!cmd.contains(.flag("-fobjc-link-runtime")))
    }

    do {
      // -fobjc-link-runtime enable
      var driver = try TestDriver(
        args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15", "-link-objc-runtime"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      expectEqual(3, plannedJobs.count)
      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)
      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-fobjc-link-runtime")))
    }

    do {
      // -fobjc-link-runtime disable override
      var driver = try TestDriver(
        args: commonArgs + [
          "-emit-library", "-target", "x86_64-apple-macosx10.15", "-link-objc-runtime", "-no-link-objc-runtime",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      expectEqual(3, plannedJobs.count)
      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)
      let cmd = linkJob.commandLine
      #expect(!cmd.contains(.flag("-fobjc-link-runtime")))
    }

    do {
      // Xlinker flags
      // Ensure that Xlinker flags are passed as such to the clang linker invocation.
      var driver = try TestDriver(
        args: commonArgs + [
          "-emit-library", "-L", "/tmp", "-Xlinker", "-w",
          "-Xlinker", "-alias", "-Xlinker", "_foo_main", "-Xlinker", "_main",
          "-Xclang-linker", "foo", "-target", "x86_64-apple-macos12.0",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      let linkJob = plannedJobs[2]
      let cmd = linkJob.commandLine
      #expect(
        cmd.contains(subsequence: [
          .flag("-Xlinker"), .flag("-alias"),
          .flag("-Xlinker"), .flag("_foo_main"),
          .flag("-Xlinker"), .flag("_main"),
          .flag("foo"),
        ])
      )
    }

    do {
      try await withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "linux", "static-executable-args.lnk")) {
          $0.send("empty")
        }
        // Ensure that when building a static executable on Linux we do not pass in
        // a redundant '-pie'
        var driver = try TestDriver(
          args: commonArgs + [
            "-emit-executable", "-L", "/tmp", "-Xlinker", "--export-all",
            "-Xlinker", "-E", "-Xclang-linker", "foo",
            "-resource-dir", path.pathString,
            "-static-executable",
            "-target", "x86_64-unknown-linux",
          ],
          env: env
        )
        let plannedJobs = try await driver.planBuild()
        #expect(plannedJobs.count == 4)
        let linkJob = plannedJobs[3]
        let cmd = linkJob.commandLine
        #expect(!cmd.contains(.flag("-pie")))
      }

    }

    do {
      try await withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "linux", "static-executable-args.lnk")) {
          $0.send("empty")
        }
        // Ensure that when building a non-static executable on Linux, we specify '-pie'
        var driver = try TestDriver(
          args: commonArgs + [
            "-emit-executable", "-L", "/tmp", "-Xlinker", "--export-all",
            "-Xlinker", "-E", "-Xclang-linker", "foo",
            "-resource-dir", path.pathString,
            "-target", "x86_64-unknown-linux",
          ],
          env: env
        )
        let plannedJobs = try await driver.planBuild()
        #expect(plannedJobs.count == 4)
        let linkJob = plannedJobs[3]
        let cmd = linkJob.commandLine
        #expect(cmd.contains(.flag("-pie")))
      }
    }

    do {
      // Xlinker flags
      // Ensure that Xlinker flags are passed as such to the clang linker invocation.
      var driver = try TestDriver(
        args: commonArgs + [
          "-emit-library", "-L", "/tmp", "-Xlinker", "-w",
          "-Xlinker", "-rpath=$ORIGIN", "-Xclang-linker", "foo",
          "-target", "x86_64-unknown-linux",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 4)
      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      #expect(cmd.contains(subsequence: [.flag("-Xlinker"), .flag("-rpath=$ORIGIN"), .flag("foo")]))
    }

    do {
      // Xlinker flags
      // Ensure that Xlinker flags are passed as such to the clang linker invocation.
      try await withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "wasi", "static-executable-args.lnk")) {
          $0.send("garbage")
        }
        var driver = try TestDriver(
          args: commonArgs + [
            "-emit-executable", "-L", "/tmp", "-Xlinker", "--export-all",
            "-Xlinker", "-E", "-Xclang-linker", "foo",
            "-resource-dir", path.pathString,
            "-target", "wasm32-unknown-wasi",
          ],
          env: env
        )
        let plannedJobs = try await driver.planBuild()
        #expect(plannedJobs.count == 4)
        let linkJob = plannedJobs[3]
        let cmd = linkJob.commandLine
        #expect(
          cmd.contains(subsequence: [
            .flag("-Xlinker"), .flag("--export-all"),
            .flag("-Xlinker"), .flag("-E"),
            .flag("foo"),
          ])
        )
      }
    }

    do {
      var driver = try TestDriver(
        args: commonArgs + [
          "-emit-library", "-no-toolchain-stdlib-rpath",
          "-target", "aarch64-unknown-linux",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 4)
      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      #expect(!cmd.contains(subsequence: [.flag("-Xlinker"), .flag("-rpath"), .flag("-Xlinker")]))
    }

    do {
      // Object file inputs
      var driver = try TestDriver(
        args: commonArgs + ["baz.o", "-emit-library", "-target", "x86_64-apple-macosx10.15"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      expectEqual(3, plannedJobs.count)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(linkJob.inputs.contains { matchTemporary($0.file, "foo.o") && $0.type == .object })
      #expect(linkJob.inputs.contains { matchTemporary($0.file, "bar.o") && $0.type == .object })
      #expect(linkJob.inputs.contains(.init(file: try toPath("baz.o").intern(), type: .object)))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(cmd.contains(try toPathOption("baz.o")))
    }

    do {
      // static linking
      var driver = try TestDriver(
        args: commonArgs + [
          "-emit-library", "-static", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 3)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-static")))
      #expect(cmd.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(try linkJob.outputs[0].file == toPath("libTest.a"))

      // The regular Swift driver doesn't pass Xlinker flags to the static
      // linker, so be consistent with this
      #expect(!cmd.contains(.flag("-w")))
      #expect(!cmd.contains(.flag("-L")))
      #expect(!cmd.contains(.path(.absolute(try .init(validating: "/tmp")))))
      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-shared")))
    }

    do {
      // static linking
      // Locating relevant libraries is dependent on being a macOS host
      #if os(macOS)
      var driver = try TestDriver(
        args: commonArgs + [
          "-emit-library", "-static", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.9",
          "-lto=llvm-full",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 3)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-static")))
      #expect(cmd.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(cmd, "foo.bc"))
      #expect(commandContainsTemporaryPath(cmd, "bar.bc"))
      #expect(try linkJob.outputs[0].file == toPath("libTest.a"))

      // The regular Swift driver doesn't pass Xlinker flags to the static
      // linker, so be consistent with this
      #expect(!cmd.contains(.flag("-w")))
      #expect(!cmd.contains(.flag("-L")))
      #expect(!cmd.contains(.path(.absolute(try .init(validating: "/tmp")))))
      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-shared")))
      #expect(!cmd.contains("-force_load"))
      #expect(!cmd.contains("-platform_version"))
      #expect(!cmd.contains("-lto_library"))
      #expect(!cmd.contains("-syslibroot"))
      #expect(!cmd.contains("-no_objc_category_merging"))
      #endif
    }

    do {
      // executable linking
      var driver = try TestDriver(
        args: commonArgs + ["-emit-executable", "-target", "x86_64-apple-macosx10.15"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      expectEqual(3, plannedJobs.count)
      #expect(!plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(try linkJob.outputs[0].file == toPath("Test"))

      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-shared")))
    }

    do {
      // lto linking
      // Locating relevant libraries is dependent on being a macOS host
      #if os(macOS)
      var driver1 = try TestDriver(
        args: commonArgs + ["-emit-executable", "-target", "x86_64-apple-macosx10.15", "-lto=llvm-thin"],
        env: env
      )
      let plannedJobs1 = try await driver1.planBuild()
      #expect(!plannedJobs1.containsJob(.autolinkExtract))
      let linkJob1 = try plannedJobs1.findJob(.link)
      #expect(linkJob1.tool.name.contains("clang"))
      expectJobInvocationMatches(linkJob1, .flag("-flto=thin"))
      #endif

      var driver2 = try TestDriver(
        args: commonArgs + ["-emit-executable", "-O", "-target", "x86_64-unknown-linux", "-lto=llvm-thin"],
        env: env
      )
      let plannedJobs2 = try await driver2.planBuild()
      #expect(!plannedJobs2.containsJob(.autolinkExtract))
      let linkJob2 = try plannedJobs2.findJob(.link)
      #expect(linkJob2.tool.name.contains("clang"))
      expectJobInvocationMatches(linkJob2, .flag("-flto=thin"))
      expectJobInvocationMatches(linkJob2, .flag("-O3"))

      var driver3 = try TestDriver(
        args: commonArgs + ["-emit-executable", "-target", "x86_64-unknown-linux", "-lto=llvm-full"],
        env: env
      )
      let plannedJobs3 = try await driver3.planBuild()
      #expect(!plannedJobs3.containsJob(.autolinkExtract))

      let compileJob3 = try plannedJobs3.findJob(.compile)
      #expect(compileJob3.outputs.contains { $0.file.basename.hasSuffix(".bc") })

      let linkJob3 = try plannedJobs3.findJob(.link)
      #expect(linkJob3.tool.name.contains("clang"))
      expectJobInvocationMatches(linkJob3, .flag("-flto=full"))

      try await withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "wasi", "static-executable-args.lnk")) {
          $0.send("garbage")
        }
        var driver4 = try TestDriver(
          args: commonArgs + [
            "-emit-executable", "-target", "wasm32-unknown-wasi", "-lto=llvm-thin", "baz.bc",
            "-resource-dir", path.pathString,
          ],
          env: env
        )
        let plannedJobs4 = try await driver4.planBuild()
        #expect(!plannedJobs4.containsJob(.autolinkExtract))
        let linkJob4 = try plannedJobs4.findJob(.link)
        #expect(linkJob4.tool.name.contains("clang"))
        expectJobInvocationMatches(linkJob4, .flag("-flto=thin"))
        for linkBcInput in ["foo", "bar", "baz.bc"] {
          #expect(
            linkJob4.inputs.contains { $0.file.basename.hasPrefix(linkBcInput) && $0.type == .llvmBitcode },
            "Missing input \(linkBcInput)"
          )
        }
      }
    }

    do {
      var driver = try TestDriver(
        args: commonArgs + ["-emit-executable", "-Onone", "-emit-module", "-g", "-target", "x86_64-apple-macosx10.15"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      expectEqual(5, plannedJobs.count)
      #expect(plannedJobs.map(\.kind) == [.emitModule, .compile, .compile, .link, .generateDSYM])

      let linkJob = plannedJobs[3]
      #expect(linkJob.kind == .link)

      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(cmd.contains(.joinedOptionAndPath("-Wl,-add_ast_path,", try toPath("Test.swiftmodule"))))
      #expect(cmd.contains(.flag("-O0")))
      #expect(try linkJob.outputs[0].file == toPath("Test"))

      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-shared")))
    }

    do {
      // linux target
      var driver = try TestDriver(args: commonArgs + ["-emit-library", "-target", "x86_64-unknown-linux"], env: env)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let autolinkExtractJob = plannedJobs[2]
      #expect(autolinkExtractJob.kind == .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      #expect(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      #expect(linkJob.kind == .link)
      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-o")))
      #expect(cmd.contains(.flag("-shared")))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(commandContainsTemporaryResponsePath(cmd, "Test.autolink"))
      #expect(try linkJob.outputs[0].file == toPath("libTest.so"))

      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-static")))
    }

    do {
      // Linux shared objects (.so) are not offered to autolink-extract
      try await withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(
          path.appending(components: "libEmpty.so"),
          bytes:
            """
                /* empty */
            """
        )

        var driver = try TestDriver(
          args: commonArgs + ["-emit-executable", "-target", "x86_64-unknown-linux", "libEmpty.so"],
          env: env
        )
        let plannedJobs = try await driver.planBuild()

        #expect(plannedJobs.count == 4)

        let autolinkExtractJob = plannedJobs[2]
        expectEqual(autolinkExtractJob.kind, .autolinkExtract)

        let autolinkCmd = autolinkExtractJob.commandLine
        #expect(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
        #expect(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
        #expect(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))
        #expect(
          !autolinkCmd.contains {
            guard case .path(let path) = $0 else { return false }
            if case .relative(let p) = path, p.basename == "libEmpty.so" { return true }
            return false
          }
        )
      }
    }

    do {
      // static linux linking
      var driver = try TestDriver(
        args: commonArgs + ["-emit-library", "-static", "-target", "x86_64-unknown-linux"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let autolinkExtractJob = plannedJobs[2]
      #expect(autolinkExtractJob.kind == .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      #expect(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      // we'd expect "ar crs libTest.a foo.o bar.o"
      #expect(cmd.contains(.flag("crs")))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(try linkJob.outputs[0].file == toPath("libTest.a"))

      #expect(!cmd.contains(.flag("-o")))
      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-shared")))
      #expect(!cmd.contains(.flag("--start-group")))
      #expect(!cmd.contains(.flag("--end-group")))
    }

    // /usr/lib/swift_static/linux/static-stdlib-args.lnk is required for static
    // linking on Linux, but is not present in macOS toolchains
    #if os(Linux)
    do {
      // executable linking linux static stdlib
      var driver = try TestDriver(
        args: commonArgs + ["-emit-executable", "-Osize", "-static-stdlib", "-target", "x86_64-unknown-linux"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let autolinkExtractJob = plannedJobs[2]
      #expect(autolinkExtractJob.kind == .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      #expect(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      #expect(cmd.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(cmd.contains(.flag("--start-group")))
      #expect(cmd.contains(.flag("--end-group")))
      #expect(cmd.contains(.flag("-Os")))
      #expect(try linkJob.outputs[0].file == toPath("Test"))

      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-shared")))
    }
    #endif

    do {
      // static Wasm linking
      var driver = try TestDriver(
        args: commonArgs + ["-emit-library", "-static", "-target", "wasm32-unknown-wasi"],
        env: env
      )
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 4)

      let autolinkExtractJob = plannedJobs[2]
      #expect(autolinkExtractJob.kind == .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      #expect(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      #expect(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      // we'd expect "ar crs libTest.a foo.o bar.o"
      #expect(cmd.contains(.flag("crs")))
      #expect(commandContainsTemporaryPath(cmd, "foo.o"))
      #expect(commandContainsTemporaryPath(cmd, "bar.o"))
      #expect(try linkJob.outputs[0].file == toPath("libTest.a"))

      #expect(!cmd.contains(.flag("-o")))
      #expect(!cmd.contains(.flag("-dylib")))
      #expect(!cmd.contains(.flag("-static")))
      #expect(!cmd.contains(.flag("-shared")))
      #expect(!commandContainsTemporaryPath(cmd, "Test.autolink"))
    }

    do {
      try await withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "wasi", "static-executable-args.lnk")) {
          $0.send("garbage")
        }
        // Wasm executable linking
        var driver = try TestDriver(
          args: commonArgs + [
            "-emit-executable", "-Ounchecked",
            "-target", "wasm32-unknown-wasi",
            "-resource-dir", path.pathString,
            "-sdk", "/sdk/path",
          ],
          env: env
        )
        let plannedJobs = try await driver.planBuild()

        #expect(plannedJobs.count == 4)

        let autolinkExtractJob = plannedJobs[2]
        #expect(autolinkExtractJob.kind == .autolinkExtract)

        let autolinkCmd = autolinkExtractJob.commandLine
        #expect(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
        #expect(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
        #expect(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

        let linkJob = plannedJobs[3]
        let cmd = linkJob.commandLine
        #expect(cmd.contains(subsequence: ["-target", "wasm32-unknown-wasi"]))
        #expect(cmd.contains(subsequence: ["--sysroot", .path(.absolute(try .init(validating: "/sdk/path")))]))
        #expect(cmd.contains(.path(.absolute(path.appending(components: "wasi", "wasm32", "swiftrt.o")))))
        #expect(commandContainsTemporaryPath(cmd, "foo.o"))
        #expect(commandContainsTemporaryPath(cmd, "bar.o"))
        #expect(commandContainsTemporaryResponsePath(cmd, "Test.autolink"))
        #expect(
          cmd.contains(.responseFilePath(.absolute(path.appending(components: "wasi", "static-executable-args.lnk"))))
        )
        #expect(cmd.contains(subsequence: [.flag("-Xlinker"), .flag("--global-base=4096")]))
        #expect(cmd.contains(subsequence: [.flag("-Xlinker"), .flag("--table-base=4096")]))
        #expect(
          cmd.contains(subsequence: [
            .flag("-Xlinker"), .flag("-z"), .flag("-Xlinker"), .flag("stack-size=\(128 * 1024)"),
          ])
        )
        #expect(cmd.contains(.flag("-O3")))
        #expect(try linkJob.outputs[0].file == toPath("Test"))

        #expect(!cmd.contains(.flag("-dylib")))
        #expect(!cmd.contains(.flag("-shared")))
      }
    }

    do {
      // -sysroot is preferred over -sdk as the sysroot passed to the clang linker
      try await withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "wasi", "static-executable-args.lnk")) {
          $0.send("garbage")
        }
        var driver = try TestDriver(
          args: commonArgs + [
            "-emit-executable", "-Ounchecked",
            "-target", "wasm32-unknown-wasi",
            "-resource-dir", path.pathString,
            "-sysroot", "/sysroot/path",
            "-sdk", "/sdk/path",
          ],
          env: env
        )
        let plannedJobs = try await driver.planBuild()
        let cmd = plannedJobs.last!.commandLine
        #expect(cmd.contains(subsequence: ["--sysroot", .path(.absolute(try .init(validating: "/sysroot/path")))]))
      }
    }

    do {
      // Linker flags with and without space
      var driver = try TestDriver(args: commonArgs + ["-lsomelib", "-l", "otherlib"], env: env)
      let plannedJobs = try await driver.planBuild()
      let cmd = plannedJobs.last!.commandLine
      #expect(cmd.contains(.flag("-lsomelib")))
      #expect(cmd.contains(.flag("-lotherlib")))
    }

    do {
      // The Android NDK only uses the lld linker now
      var driver = try TestDriver(
        args: commonArgs + ["-emit-library", "-target", "aarch64-unknown-linux-android24", "-use-ld=lld"],
        env: env
      )
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let lastJob = plannedJobs.last!
      #expect(lastJob.tool.name.contains("clang"))
      expectJobInvocationMatches(lastJob, .flag("-fuse-ld=lld"))
    }
  }

  @Test func lEqualPassedDownToLinkerInvocation() async throws {
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "Foo", "Bar")

    var driver = try TestDriver(args: [
      "swiftc", "-working-directory", workingDirectory.pathString, "-emit-executable", "test.swift", "-L=.", "-F=.",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let workDir: VirtualPath = try VirtualPath(path: workingDirectory.nativePathString(escaped: false))

    #expect(plannedJobs.count == 2)

    expectJobInvocationMatches(plannedJobs[0], .joinedOptionAndPath("-F=", workDir))
    #expect(!plannedJobs[0].commandLine.contains(.joinedOptionAndPath("-L=", workDir)))
    expectJobInvocationMatches(plannedJobs[1], .joinedOptionAndPath("-L=", workDir))

    #expect(!plannedJobs[1].commandLine.contains(.joinedOptionAndPath("-F=", workDir)))
    // Test implicit output file also honors the working directory.
    try expectJobInvocationMatches(
      plannedJobs[1],
      .flag("-o"),
      .path(VirtualPath(path: rebase(executableName("test"), at: workingDirectory)))
    )
  }

  @Test func compatibilityLibs() async throws {
    var env = ProcessEnv.block
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    try await withTemporaryDirectory { path in
      let path5_0Mac = path.appending(components: "macosx", "libswiftCompatibility50.a")
      let path5_1Mac = path.appending(components: "macosx", "libswiftCompatibility51.a")
      let pathDynamicReplacementsMac = path.appending(
        components: "macosx",
        "libswiftCompatibilityDynamicReplacements.a"
      )
      let path5_0iOS = path.appending(components: "iphoneos", "libswiftCompatibility50.a")
      let path5_1iOS = path.appending(components: "iphoneos", "libswiftCompatibility51.a")
      let pathDynamicReplacementsiOS = path.appending(
        components: "iphoneos",
        "libswiftCompatibilityDynamicReplacements.a"
      )
      let pathCompatibilityPacksMac = path.appending(components: "macosx", "libswiftCompatibilityPacks.a")

      for compatibilityLibPath in [
        path5_0Mac, path5_1Mac,
        pathDynamicReplacementsMac, path5_0iOS,
        path5_1iOS, pathDynamicReplacementsiOS,
        pathCompatibilityPacksMac,
      ] {
        try localFileSystem.createDirectory(compatibilityLibPath.parentDirectory, recursive: true)
        try localFileSystem.writeFileContents(compatibilityLibPath, bytes: "Empty")
      }
      let commonArgs = ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-resource-dir", path.pathString]

      do {
        var driver = try TestDriver(args: commonArgs + ["-target", "x86_64-apple-macosx10.14"], env: env)
        let plannedJobs = try await driver.planBuild()

        expectEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        #expect(linkJob.kind == .link)
        let cmd = linkJob.commandLine

        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        #expect(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try TestDriver(args: commonArgs + ["-target", "x86_64-apple-macosx10.15.1"], env: env)
        let plannedJobs = try await driver.planBuild()

        expectEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        #expect(linkJob.kind == .link)
        let cmd = linkJob.commandLine

        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        #expect(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try TestDriver(args: commonArgs + ["-target", "x86_64-apple-macosx10.15.4"], env: env)
        let plannedJobs = try await driver.planBuild()

        expectEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        #expect(linkJob.kind == .link)
        let cmd = linkJob.commandLine

        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        #expect(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try TestDriver(
          args: commonArgs + ["-target", "x86_64-apple-macosx10.15.4", "-runtime-compatibility-version", "5.0"],
          env: env
        )
        let plannedJobs = try await driver.planBuild()

        expectEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        #expect(linkJob.kind == .link)
        let cmd = linkJob.commandLine

        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        #expect(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try TestDriver(args: commonArgs + ["-target", "arm64-apple-ios13.0"], env: env)
        let plannedJobs = try await driver.planBuild()

        expectEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        #expect(linkJob.kind == .link)
        let cmd = linkJob.commandLine

        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0iOS))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1iOS))]))
        #expect(!cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsiOS))]))
      }

      do {
        var driver = try TestDriver(args: commonArgs + ["-target", "arm64-apple-ios12.0"], env: env)
        let plannedJobs = try await driver.planBuild()

        expectEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        #expect(linkJob.kind == .link)
        let cmd = linkJob.commandLine

        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0iOS))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1iOS))]))
        #expect(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsiOS))]))
      }
    }
  }

  @Test func dsymGeneration() async throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-module-name", "Test",
    ]

    do {
      // No dSYM generation (no -g)
      var driver = try TestDriver(args: commonArgs)
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      #expect(plannedJobs.count == 3)
      #expect(!plannedJobs.containsJob(.generateDSYM))
    }

    do {
      // No dSYM generation (-gnone)
      var driver = try TestDriver(args: commonArgs + ["-gnone"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      #expect(plannedJobs.count == 3)
      #expect(!plannedJobs.containsJob(.generateDSYM))
    }

    do {
      var env = ProcessEnv.block
      // As per Unix conventions, /var/empty is expected to exist and be empty.
      // This gives us a non-existent path that we can use for libtool which
      // allows us to run this this on non-Darwin platforms.
      env["SWIFT_DRIVER_LIBTOOL_EXEC"] = "/var/empty/libtool"

      // No dSYM generation (-g -emit-library -static)
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "x86_64-apple-macosx10.15", "-g", "-emit-library",
          "-static", "-o", "library.a", "library.swift",
        ],
        env: env
      )
      let jobs = try await driver.planBuild()

      expectEqual(jobs.count, 3)
      #expect(!jobs.containsJob(.generateDSYM))
    }

    do {
      // dSYM generation (-g)
      var driver = try TestDriver(args: commonArgs + ["-g"])
      let plannedJobs = try await driver.planBuild()

      let generateDSYMJob = plannedJobs.last!
      let cmd = generateDSYMJob.commandLine

      if driver.targetTriple.objectFormat == .elf {
        expectEqual(plannedJobs.count, 6)
      } else {
        #expect(plannedJobs.count == 5)
      }

      if driver.targetTriple.isDarwin {
        try expectEqual(generateDSYMJob.outputs.last?.file, try toPath("Test.dSYM"))
      } else {
        #expect(!plannedJobs.map { $0.kind }.contains(.generateDSYM))
      }

      #expect(cmd.contains(try toPathOption(executableName("Test"))))
    }

    do {
      // dSYM generation (-g) with specified output file name with an extension
      var driver = try TestDriver(args: commonArgs + ["-g", "-o", "a.out"])
      let plannedJobs = try await driver.planBuild()
      let generateDSYMJob = plannedJobs.last!
      if driver.targetTriple.isDarwin {
        #expect(plannedJobs.count == 5)
        try expectEqual(generateDSYMJob.outputs.last?.file, try toPath("a.out.dSYM"))
      }
    }
  }

  @Test func verifyDebugInfo() async throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-module-name", "Test", "-verify-debug-info",
    ]

    // No dSYM generation (no -g), therefore no verification
    try await assertDriverDiagnostics(args: commonArgs) { driver, verifier in
      verifier.expect(.warning("ignoring '-verify-debug-info'; no debug info is being generated"))
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)
      #expect(!plannedJobs.containsJob(.verifyDebugInfo))
    }

    // No dSYM generation (-gnone), therefore no verification
    try await assertDriverDiagnostics(args: commonArgs + ["-gnone"]) { driver, verifier in
      verifier.expect(.warning("ignoring '-verify-debug-info'; no debug info is being generated"))
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)
      #expect(!plannedJobs.containsJob(.verifyDebugInfo))
    }

    do {
      // dSYM generation and verification (-g + -verify-debug-info)
      var driver = try TestDriver(args: commonArgs + ["-g"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      let verifyDebugInfoJob = plannedJobs.last!
      let cmd = verifyDebugInfoJob.commandLine

      if driver.targetTriple.isDarwin {
        expectEqual(plannedJobs.count, 6)
        try expectEqual(verifyDebugInfoJob.inputs.first?.file, try toPath("Test.dSYM"))
        #expect(cmd.contains(.flag("--verify")))
        #expect(cmd.contains(.flag("--debug-info")))
        #expect(cmd.contains(.flag("--eh-frame")))
        #expect(cmd.contains(.flag("--quiet")))
        #expect(cmd.contains(try toPathOption("Test.dSYM")))
      } else {
        #expect(plannedJobs.count == 5)
      }
    }
  }

  @Test func emitModuleTrace() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-typecheck", "-emit-loaded-module-trace", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      #expect(
        job.commandLine.contains(subsequence: [
          "-emit-loaded-module-trace-path",
          .path(.relative(try .init(validating: "foo.trace.json"))),
        ])
      )
    }
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck",
        "-emit-loaded-module-trace",
        "foo.swift", "bar.swift", "baz.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      let tracedJobs = try plannedJobs.filter {
        $0.commandLine.contains(subsequence: [
          "-emit-loaded-module-trace-path",
          .path(.relative(try .init(validating: "main.trace.json"))),
        ])
      }
      expectEqual(tracedJobs.count, 1)
    }
    do {
      // Make sure the trace is associated with the first frontend job as
      // opposed to the first input.
      var driver = try TestDriver(args: [
        "swiftc", "-emit-loaded-module-trace",
        "foo.o", "bar.swift", "baz.o",
      ])
      let plannedJobs = try await driver.planBuild()
      let tracedJobs = try plannedJobs.filter {
        $0.commandLine.contains(subsequence: [
          "-emit-loaded-module-trace-path",
          .path(.relative(try .init(validating: "main.trace.json"))),
        ])
      }
      expectEqual(tracedJobs.count, 1)
      #expect(tracedJobs[0].inputs.contains(.init(file: try toPath("bar.swift").intern(), type: .swift)))
    }
    do {
      var env = ProcessEnv.block
      env["SWIFT_LOADED_MODULE_TRACE_FILE"] = "/some/path/to/the.trace.json"
      var driver = try TestDriver(
        args: [
          "swiftc", "-typecheck",
          "-emit-loaded-module-trace", "foo.swift",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      #expect(
        job.commandLine.contains(subsequence: [
          "-emit-loaded-module-trace-path",
          .path(.absolute(try .init(validating: "/some/path/to/the.trace.json"))),
        ])
      )
    }
  }

  @Test(.skipHostOS(.darwin, comment: "Darwin does not use clang as the linker driver")) func cxxLinking() async throws
  {
    var driver = try TestDriver(args: [
      "swiftc", "-cxx-interoperability-mode=upcoming-swift", "-emit-library", "-o", "library.dll", "library.obj",
    ])
    let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(jobs.count == 1)
    let job = jobs.first!
    expectEqual(job.kind, .link)
    #expect(job.tool.name.hasSuffix(executableName("clang++")))
  }

  @Test func ltoOption() async throws {
    try expectEqual(try TestDriver(args: ["swiftc"]).lto, nil)

    try expectEqual(try TestDriver(args: ["swiftc", "-lto=llvm-thin"]).lto, .llvmThin)

    try expectEqual(try TestDriver(args: ["swiftc", "-lto=llvm-full"]).lto, .llvmFull)

    try await assertDriverDiagnostics(args: ["swiftc", "-lto=nop"]) { driver, verify in
      verify.expect(.error("invalid value 'nop' in '-lto=', valid options are: llvm-thin, llvm-full"))
    }
  }

  @Test func ltoOutputs() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    let targets = ["x86_64-unknown-linux-gnu", "x86_64-apple-macosx10.9"]
    for target in targets {
      var driver = try TestDriver(
        args: ["swiftc", "foo.swift", "-lto=llvm-thin", "-target", target],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-bc"))
      #expect(matchTemporary(plannedJobs[0].outputs.first!.file, "foo.bc"))
      #expect(matchTemporary(plannedJobs[1].inputs.first!.file, "foo.bc"))
    }
  }

  @Test(.requireHostOS(.macosx)) func ltoLibraryArg() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-lto=llvm-thin", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.map(\.kind) == [.compile, .link])
      expectJobInvocationMatches(plannedJobs[1], .flag("-flto=thin"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-lto=llvm-thin", "-lto-library", "/foo/libLTO.dylib", "-target",
        "x86_64-apple-macos11.0",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.map(\.kind) == [.compile, .link])
      #expect(!plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/foo/libLTO.dylib"))))
      expectJobInvocationMatches(plannedJobs[1], .flag("-flto=thin"))
      try expectJobInvocationMatches(
        plannedJobs[1],
        .joinedOptionAndPath("-Wl,-lto_library,", VirtualPath(path: "/foo/libLTO.dylib"))
      )
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.map(\.kind) == [.compile, .link])
      expectJobInvocationMatches(plannedJobs[1], .flag("-flto=full"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-lto=llvm-full", "-lto-library", "/foo/libLTO.dylib", "-target",
        "x86_64-apple-macos11.0",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.map(\.kind) == [.compile, .link])
      #expect(!plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/foo/libLTO.dylib"))))
      expectJobInvocationMatches(plannedJobs[1], .flag("-flto=full"))
      try expectJobInvocationMatches(
        plannedJobs[1],
        .joinedOptionAndPath("-Wl,-lto_library,", VirtualPath(path: "/foo/libLTO.dylib"))
      )
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.map(\.kind) == [.compile, .link])
      #expect(!plannedJobs[1].commandLine.contains("-flto=thin"))
      #expect(!plannedJobs[1].commandLine.contains("-flto=full"))
    }
  }

  @Test func bcAsTopLevelOutput() async throws {
    var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-bc", "-target", "x86_64-apple-macosx10.9"])
    let plannedJobs = try await driver.planBuild()
    #expect(plannedJobs.count == 1)
    expectJobInvocationMatches(plannedJobs[0], .flag("-emit-bc"))
    try expectEqual(plannedJobs[0].outputs.first!.file, try toPath("foo.bc"))
  }

  @Test func gccToolchainFlags() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-gcc-toolchain", "/foo/as/blarpy", "test.swift",
    ])
    let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(jobs.count == 2)
    let (compileJob, linkJob) = (jobs[0], jobs[1])
    #expect(compileJob.commandLine.contains(.flag("--gcc-toolchain=/foo/as/blarpy")))
    #expect(linkJob.commandLine.contains(.flag("--gcc-toolchain=/foo/as/blarpy")))
  }

  @Test(.requireHostOS(.macosx, comment: "sdkArguments does not work on Linux")) func cleaningUpOldCompilationOutputs()
    async throws
  {
    // Build something, create an error, see if the .o and .swiftdeps files get cleaned up
    try await withTemporaryDirectory { tmpDir in
      let main = tmpDir.appending(component: "main.swift")
      let ofm = tmpDir.appending(component: "ofm")
      OutputFileMapCreator.write(
        module: "mod",
        inputPaths: [main],
        derivedData: tmpDir,
        to: ofm
      )

      try localFileSystem.writeFileContents(
        main,
        bytes:
          """
          // no errors here
          func foo() {}
          """
      )
      /// return true if no error
      func doBuild() async throws -> Bool {
        let sdkArguments = try #require(try Driver.sdkArgumentsForTesting())
        var driver = try TestDriver(
          args: [
            "swiftc",
            "-working-directory", tmpDir.nativePathString(escaped: false),
            "-module-name", "mod",
            "-c",
            "-incremental",
            "-output-file-map", ofm.nativePathString(escaped: false),
            main.nativePathString(escaped: false),
          ] + sdkArguments
        )
        let jobs = try await driver.planBuild()
        do { try await driver.run(jobs: jobs) } catch { return false }
        return true
      }
      #expect(try await doBuild())

      let outputs = [
        tmpDir.appending(component: "main.o"),
        tmpDir.appending(component: "main.swiftdeps"),
      ]
      #expect(outputs.allSatisfy(localFileSystem.exists))

      try localFileSystem.writeFileContents(
        main,
        bytes:
          """
          #error(\"Yipes!\")
          func foo() {}
          """
      )
      #expect(try await !doBuild())
      #expect(outputs.allSatisfy { !localFileSystem.exists($0) })
    }
  }

  @Test(.requireHostOS(.macosx, comment: "platform does not support dsymutil")) func linkFilelistWithDebugInfo()
    async throws
  {
    func getFileListElements(for filelistOpt: String, job: Job) -> [VirtualPath] {
      guard let optIdx = job.commandLine.firstIndex(of: .flag(filelistOpt)) else {
        Issue.record("Argument '\(filelistOpt)' not in job command line")
        return []
      }
      let value = job.commandLine[job.commandLine.index(after: optIdx)]
      guard case let .path(.fileList(_, valueFileList)) = value else {
        Issue.record("Argument wasn't a filelist")
        return []
      }
      guard case let .list(inputs) = valueFileList else {
        Issue.record("FileList wasn't a List")
        return []
      }
      return inputs
    }

    var driver = try TestDriver(args: [
      "swiftc", "-target", "arm64-apple-macosx15",
      "-g", "/tmp/hello.swift", "-module-name", "Hello",
      "-emit-library", "-driver-filelist-threshold=0",
    ])

    let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let linkJob = try jobs.findJob(.link)
    try expectEqual(
      getFileListElements(for: "-filelist", job: linkJob),
      [.temporary(try .init(validating: "hello-1.o"))]
    )
  }

  @Test func windowsRuntimeLibraryFlags() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-libc", "MD", "-use-ld=lld", "-c", "input.swift",
      ])
      let jobs = try await driver.planBuild()

      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .compile)

      expectJobInvocationMatches(
        jobs[0],
        .flag("-autolink-library"),
        .flag("oldnames"),
        .flag("-autolink-library"),
        .flag("msvcrt"),
        .flag("-Xcc"),
        .flag("-D_MT"),
        .flag("-Xcc"),
        .flag("-D_DLL")
      )
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-use-ld=lld", "-c", "input.swift",
      ])
      let jobs = try await driver.planBuild()

      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .compile)

      expectJobInvocationMatches(
        jobs[0],
        .flag("-autolink-library"),
        .flag("oldnames"),
        .flag("-autolink-library"),
        .flag("msvcrt"),
        .flag("-Xcc"),
        .flag("-D_MT"),
        .flag("-Xcc"),
        .flag("-D_DLL")
      )
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-libc", "MultiThreadedDLL", "-use-ld=lld", "-c",
        "input.swift",
      ])
      let jobs = try await driver.planBuild()

      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .compile)

      expectJobInvocationMatches(
        jobs[0],
        .flag("-autolink-library"),
        .flag("oldnames"),
        .flag("-autolink-library"),
        .flag("msvcrt"),
        .flag("-Xcc"),
        .flag("-D_MT"),
        .flag("-Xcc"),
        .flag("-D_DLL")
      )
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-libc", "MTd", "-use-ld=lld", "-c", "input.swift",
      ])
      let jobs = try await driver.planBuild()

      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .compile)

      expectJobInvocationMatches(
        jobs[0],
        .flag("-autolink-library"),
        .flag("oldnames"),
        .flag("-autolink-library"),
        .flag("libcmtd"),
        .flag("-Xcc"),
        .flag("-D_MT")
      )
    }
  }
}
