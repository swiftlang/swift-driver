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

@Suite struct SpecialModeTests {

  @Test func help() async throws {
    do {
      var driver = try TestDriver(args: ["swift", "--help"], env: envWithFakeSwiftHelp)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let helpJob = plannedJobs.first!
      #expect(helpJob.kind == .help)
      #expect(helpJob.requiresInPlaceExecution)
      #expect(helpJob.tool.name.hasSuffix("swift-help"))
      let expected: [Job.ArgTemplate] = [.flag("swift")]
      #expect(helpJob.commandLine == expected)
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-help-hidden"], env: envWithFakeSwiftHelp)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let helpJob = plannedJobs.first!
      #expect(helpJob.kind == .help)
      #expect(helpJob.requiresInPlaceExecution)
      #expect(helpJob.tool.name.hasSuffix("swift-help"))
      let expected: [Job.ArgTemplate] = [.flag("swiftc"), .flag("-show-hidden")]
      #expect(helpJob.commandLine == expected)
    }
  }

  @Test func repl() async throws {
    // Do not run this test if no LLDB is found in the toolchain.
    try #require(try testEnvHasLLDB(), "No LLDB found in toolchain")

    func isExpectedLLDBREPLFlag(_ arg: Job.ArgTemplate) -> Bool {
      if case let .squashedArgumentList(option: opt, args: args) = arg {
        return opt == "--repl=" && !args.contains("-module-name")
      }
      return false
    }

    do {
      var driver = try TestDriver(args: ["swift"], env: envWithFakeSwiftHelp)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)

      let helpJob = plannedJobs[0]
      #expect(helpJob.tool.name.contains("swift-help"))
      expectJobInvocationMatches(helpJob, .flag("intro"))
    }

    do {
      var driver = try TestDriver(args: ["swift", "-repl"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let replJob = plannedJobs.first!
      #expect(replJob.tool.name.contains("lldb"))
      #expect(replJob.requiresInPlaceExecution)
      #expect(replJob.commandLine.contains(where: { isExpectedLLDBREPLFlag($0) }))
    }

    do {
      let (mode, args) = try Driver.invocationRunMode(forArgs: ["swift", "repl"])
      expectEqual(mode, .normal(isRepl: true))
      var driver = try TestDriver(args: args)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let replJob = plannedJobs.first!
      #expect(replJob.tool.name.contains("lldb"))
      #expect(replJob.requiresInPlaceExecution)
      #expect(replJob.commandLine.contains(where: { isExpectedLLDBREPLFlag($0) }))
    }

    do {
      #expect {
        try TestDriver(args: ["swift", "-deprecated-integrated-repl"])
      } throws: { error in
        (error as? Driver.Error) == Driver.Error.integratedReplRemoved
      }
    }

    do {
      var driver = try TestDriver(args: ["swift", "-repl", "/foo/bar/Test.swift"])
      await #expect { try await driver.planBuild() } throws: { error in
        (error as? PlanningError) == .replReceivedInput
      }
    }

    do {
      // Linked library arguments with space
      var driver = try TestDriver(args: ["swift", "-repl", "-l", "somelib", "-lotherlib"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let cmd = plannedJobs.first!.commandLine
      guard case let .squashedArgumentList(option: _, args: args) = cmd[0] else {
        Issue.record()
        return
      }
      #expect(args.contains(.flag("-lsomelib")))
      #expect(args.contains(.flag("-lotherlib")))
    }
  }

  @Test func immediateMode() async throws {
    do {
      var driver = try TestDriver(args: ["swift", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      #expect(job.requiresInPlaceExecution)
      expectEqual(job.inputs.count, 1)
      try expectEqual(job.inputs[0].file, try toPath("foo.swift"))
      expectEqual(job.outputs.count, 0)
      expectJobInvocationMatches(job, .flag("-frontend"))
      expectJobInvocationMatches(job, .flag("-interpret"))
      expectJobInvocationMatches(job, .flag("-module-name"), .flag("foo"))

      if driver.targetTriple.isMacOSX {
        expectJobInvocationMatches(job, .flag("-sdk"))
      }

      #expect(!job.commandLine.contains(.flag("--")))

      let envVar: String
      if driver.targetTriple.isDarwin {
        envVar = "DYLD_LIBRARY_PATH"
      } else if driver.targetTriple.isWindows {
        envVar = "Path"
      } else {
        // assume Unix
        envVar = "LD_LIBRARY_PATH"
      }

      // The library search path applies to import libraries not runtime
      // libraries on Windows.  There is no way to derive the path from the
      // command on Windows.
      if !driver.targetTriple.isWindows {
        #if os(macOS)
        // On darwin, swift ships in the OS. Immediate mode should use that runtime.
        #expect(!job.extraEnvironmentBlock.keys.contains(ProcessEnvironmentKey(envVar)))
        #else
        #expect(job.extraEnvironmentBlock.keys.contains(ProcessEnvironmentKey(envVar)))
        #endif
      }
    }

    do {
      var driver = try TestDriver(args: ["swift", "foo.swift", "-some", "args", "-for=foo"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      #expect(job.requiresInPlaceExecution)
      expectEqual(job.inputs.count, 1)
      try expectEqual(job.inputs[0].file, try toPath("foo.swift"))
      expectEqual(job.outputs.count, 0)
      expectJobInvocationMatches(job, .flag("-frontend"))
      expectJobInvocationMatches(job, .flag("-interpret"))
      expectJobInvocationMatches(job, .flag("-module-name"), .flag("foo"))
      expectJobInvocationMatches(job, .flag("--"))
      expectJobInvocationMatches(job, .flag("-some"))
      expectJobInvocationMatches(job, .flag("args"))
      expectJobInvocationMatches(job, .flag("-for=foo"))
    }

    do {
      var driver = try TestDriver(args: [
        "swift", "-L/path/to/lib", "-F/path/to/framework", "-lsomelib", "-l", "otherlib", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      #expect(job.requiresInPlaceExecution)
      expectEqual(job.inputs.count, 1)
      try expectEqual(job.inputs[0].file, try toPath("foo.swift"))
      expectEqual(job.outputs.count, 0)

      let envVar: ProcessEnvironmentKey
      if driver.targetTriple.isDarwin {
        envVar = "DYLD_LIBRARY_PATH"
      } else if driver.targetTriple.isWindows {
        envVar = "Path"
      } else {
        // assume Unix
        envVar = "LD_LIBRARY_PATH"
      }

      // The library search path applies to import libraries not runtime
      // libraries on Windows.  There is no way to derive the path from the
      // command on Windows.
      if !driver.targetTriple.isWindows {
        #expect(job.extraEnvironmentBlock[envVar, default: ""].contains("/path/to/lib"))
        if driver.targetTriple.isDarwin {
          #expect(job.extraEnvironmentBlock["DYLD_FRAMEWORK_PATH", default: ""].contains("/path/to/framework"))
        }
      }

      expectJobInvocationMatches(job, .flag("-lsomelib"))
      expectJobInvocationMatches(job, .flag("-lotherlib"))
    }
  }

  @Test func installAPI() async throws {
    let modulePath = "/tmp/FooMod.swiftmodule"
    var driver = try TestDriver(args: [
      "swiftc", "foo.swift", "-whole-module-optimization",
      "-module-name", "FooMod",
      "-emit-tbd", "-emit-tbd-path", "/tmp/FooMod.tbd",
      "-emit-module", "-emit-module-path", modulePath,
    ])
    let plannedJobs = try await driver.planBuild()
    #expect(plannedJobs.count == 1)
    #expect(plannedJobs[0].kind == .compile)

    expectJobInvocationMatches(plannedJobs[0], .flag("-frontend"))
    expectJobInvocationMatches(plannedJobs[0], .flag("-emit-module"))
    try expectJobInvocationMatches(plannedJobs[0], .flag("-o"), .path(VirtualPath(path: modulePath)))
  }

  @Test func updateCode() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-update-code", "foo.swift", "bar.swift",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)
      #expect(plannedJobs.map(\.kind) == [.compile, .compile, .link])
      #expect(
        commandContainsFlagTemporaryPathSequence(
          plannedJobs[0].commandLine,
          flag: "-emit-remap-file-path",
          filename: "foo.remap"
        )
      )
      #expect(
        commandContainsFlagTemporaryPathSequence(
          plannedJobs[1].commandLine,
          flag: "-emit-remap-file-path",
          filename: "bar.remap"
        )
      )
    }

    try await assertDriverDiagnostics(
      args: ["swiftc", "-update-code", "foo.swift", "bar.swift", "-enable-batch-mode", "-driver-batch-count", "1"]
    ) {
      _ = try? await $0.planBuild()
      $1.expect(.error("using '-update-code' in batch compilation mode is not supported"))
    }

    try await assertDriverDiagnostics(
      args: ["swiftc", "-update-code", "foo.swift", "bar.swift", "-wmo"]
    ) {
      _ = try? await $0.planBuild()
      $1.expect(.error("using '-update-code' in whole module optimization mode is not supported"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-update-code", "foo.swift", "-migrate-keep-objc-visibility",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs.map(\.kind) == [.compile, .link])
      #expect(
        commandContainsFlagTemporaryPathSequence(
          plannedJobs[0].commandLine,
          flag: "-emit-remap-file-path",
          filename: "foo.remap"
        )
      )
      expectJobInvocationMatches(plannedJobs[0], .flag("-migrate-keep-objc-visibility"))
    }
  }

  @Test func versionRequest() async throws {
    for arg in ["-version", "--version"] {
      var driver = try TestDriver(args: ["swift"] + [arg])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectEqual(job.kind, .versionRequest)
      expectEqual(job.commandLine, [.flag("--version")])
    }
  }

  @Test func noInputs() async throws {
    // A plain `swift` invocation requires lldb to be present
    if try testEnvHasLLDB() {
      do {
        var driver = try TestDriver(args: ["swift"], env: envWithFakeSwiftHelp)
        await #expect(throws: Never.self) { try await driver.planBuild() }
      }
    }
    do {
      var driver = try TestDriver(args: ["swiftc"], env: envWithFakeSwiftHelp)
      await #expect {
        try await driver.planBuild()
      } throws: { error in
        (error as? Driver.Error) == .noInputFiles
      }
    }
    do {
      var driver = try TestDriver(args: ["swiftc", "-whole-module-optimization"])
      await #expect {
        try await driver.planBuild()
      } throws: { error in
        (error as? Driver.Error) == .noInputFiles
      }
    }
  }

  @Test func printTargetInfo() async throws {
    do {
      var driver = try TestDriver(args: [
        "swift", "-print-target-info", "-target", "arm64-apple-ios12.0", "-sdk", "bar", "-resource-dir", "baz",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectEqual(job.kind, .printTargetInfo)
      expectJobInvocationMatches(job, .flag("-print-target-info"))
      expectJobInvocationMatches(job, .flag("-target"))
      expectJobInvocationMatches(job, .flag("-sdk"))
      expectJobInvocationMatches(job, .flag("-resource-dir"))
    }

    // In-process query
    do {
      let targetInfoArgs = ["-print-target-info", "-sdk", "/bar", "-resource-dir", "baz"]
      let driver = try TestDriver(args: ["swift"] + targetInfoArgs)
      let printTargetInfoJob = try driver.toolchain.printTargetInfoJob(
        target: nil,
        targetVariant: nil,
        sdkPath: .absolute(driver.absoluteSDKPath!),
        swiftCompilerPrefixArgs: []
      )
      var printTargetInfoCommand = try Driver.itemizedJobCommand(
        of: printTargetInfoJob,
        useResponseFiles: .disabled,
        using: ArgsResolver(fileSystem: InMemoryFileSystem())
      )
      Driver.sanitizeCommandForLibScanInvocation(&printTargetInfoCommand)
      let swiftScanLibPath = try #require(try driver.getSwiftScanLibPath())
      if localFileSystem.exists(swiftScanLibPath) {
        let libSwiftScanInstance = try SwiftScan(dylib: swiftScanLibPath)
        if libSwiftScanInstance.canQueryTargetInfo() {
          let _ = try Driver.queryTargetInfoInProcess(
            libSwiftScanInstance: libSwiftScanInstance,
            toolchain: driver.toolchain,
            fileSystem: localFileSystem,
            workingDirectory: localFileSystem.currentWorkingDirectory,
            invocationCommand: printTargetInfoCommand
          )
        }
      }
    }

    // Ensure that quoted paths are always escaped on the in-process query commands
    do {
      let targetInfoArgs = ["-print-target-info", "-sdk", "/tmp/foo bar", "-resource-dir", "baz"]
      let driver = try TestDriver(args: ["swift"] + targetInfoArgs)
      let printTargetInfoJob = try driver.toolchain.printTargetInfoJob(
        target: nil,
        targetVariant: nil,
        sdkPath: .absolute(driver.absoluteSDKPath!),
        swiftCompilerPrefixArgs: []
      )
      var printTargetInfoCommand = try Driver.itemizedJobCommand(
        of: printTargetInfoJob,
        useResponseFiles: .disabled,
        using: ArgsResolver(fileSystem: InMemoryFileSystem())
      )
      Driver.sanitizeCommandForLibScanInvocation(&printTargetInfoCommand)
      let swiftScanLibPath = try #require(try driver.getSwiftScanLibPath())
      if localFileSystem.exists(swiftScanLibPath) {
        let libSwiftScanInstance = try SwiftScan(dylib: swiftScanLibPath)
        if libSwiftScanInstance.canQueryTargetInfo() {
          let _ = try Driver.queryTargetInfoInProcess(
            libSwiftScanInstance: libSwiftScanInstance,
            toolchain: driver.toolchain,
            fileSystem: localFileSystem,
            workingDirectory: localFileSystem.currentWorkingDirectory,
            invocationCommand: printTargetInfoCommand
          )
        }
      }
    }

    do {
      struct MockExecutor: DriverExecutor {
        let resolver: ArgsResolver

        func execute(
          job: Job,
          forceResponseFiles: Bool,
          recordedInputMetadata: [TypedVirtualPath: FileMetadata]
        ) throws -> ProcessResult {
          return ProcessResult(
            arguments: [],
            environmentBlock: [:],
            exitStatus: .terminated(code: 0),
            output: .success(Array("bad JSON".utf8)),
            stderrOutput: .success([])
          )
        }
        func execute(
          workload: DriverExecutorWorkload,
          delegate: JobExecutionDelegate,
          numParallelJobs: Int,
          forceResponseFiles: Bool,
          recordedInputMetadata: [TypedVirtualPath: FileMetadata]
        ) throws {
          fatalError()
        }
        func checkNonZeroExit(args: String..., environment: [String: String]) throws -> String {
          return try Process.checkNonZeroExit(arguments: args, environmentBlock: ProcessEnvironmentBlock(environment))
        }
        func checkNonZeroExit(args: String..., environmentBlock: ProcessEnvironmentBlock) throws -> String {
          return try Process.checkNonZeroExit(arguments: args, environmentBlock: environmentBlock)
        }
        func description(of job: Job, forceResponseFiles: Bool) throws -> String {
          fatalError()
        }

        public func execute(
          job: Job,
          forceResponseFiles: Bool,
          recordedInputModificationDates: [TypedVirtualPath: TimePoint]
        ) throws -> ProcessResult {
          fatalError(
            "This DriverExecutor protocol method is only for backwards compatibility and should not be called directly"
          )
        }

        public func execute(
          workload: DriverExecutorWorkload,
          delegate: JobExecutionDelegate,
          numParallelJobs: Int,
          forceResponseFiles: Bool,
          recordedInputModificationDates: [TypedVirtualPath: TimePoint]
        ) throws {
          fatalError(
            "This DriverExecutor protocol method is only for backwards compatibility and should not be called directly"
          )
        }

        public func execute(
          jobs: [Job],
          delegate: JobExecutionDelegate,
          numParallelJobs: Int,
          forceResponseFiles: Bool,
          recordedInputModificationDates: [TypedVirtualPath: TimePoint]
        ) throws {
          fatalError(
            "This DriverExecutor protocol method is only for backwards compatibility and should not be called directly"
          )
        }
      }

      // Override path to libSwiftScan to force the fallback of using the executor
      var hideSwiftScanEnv = ProcessEnv.block
      hideSwiftScanEnv["SWIFT_DRIVER_SWIFTSCAN_LIB"] = "/bad/path/lib_InternalSwiftScan.dylib"
      #expect {
        try TestDriver(
          args: ["swift", "-print-target-info"],
          env: hideSwiftScanEnv,
          executor: MockExecutor(resolver: ArgsResolver(fileSystem: InMemoryFileSystem())),
          fileSystem: InMemoryFileSystem()
        )
      } throws: { error in
        if case .decodingError = error as? JobExecutionError { return true }
        Issue.record("not a decoding error: \(error)")
        return false
      }
    }

    #if !os(Windows)  // Windows uses Foundation instead of TSC for subprocesses
    do {
      #expect {
        try TestDriver(
          args: ["swift", "-print-target-info"],
          env: ["SWIFT_DRIVER_SWIFT_FRONTEND_EXEC": "/bad/path/to/swift-frontend"]
        )
      } throws: { error in
        if case .posix_spawn = error as? TSCBasic.SystemError { return true }
        if error as? JobExecutionError != nil { return true }
        Issue.record("unexpected error: \(error)")
        return false
      }
    }
    #endif

    do {
      var driver = try TestDriver(args: [
        "swift", "-print-target-info", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant",
        "x86_64-apple-macosx10.14", "-sdk", "bar", "-resource-dir", "baz",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectEqual(job.kind, .printTargetInfo)
      expectJobInvocationMatches(job, .flag("-print-target-info"))
      expectJobInvocationMatches(job, .flag("-target"))
      expectJobInvocationMatches(job, .flag("-target-variant"))
      expectJobInvocationMatches(job, .flag("-sdk"))
      expectJobInvocationMatches(job, .flag("-resource-dir"))
    }

    do {
      var driver = try TestDriver(args: ["swift", "-print-target-info", "-target", "x86_64-unknown-linux"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectEqual(job.kind, .printTargetInfo)
      expectJobInvocationMatches(job, .flag("-print-target-info"))
      expectJobInvocationMatches(job, .flag("-target"))
      #expect(!job.commandLine.contains(.flag("-use-static-resource-dir")))
    }

    do {
      var driver = try TestDriver(args: [
        "swift", "-print-target-info", "-target", "x86_64-unknown-linux", "-static-stdlib",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectEqual(job.kind, .printTargetInfo)
      expectJobInvocationMatches(job, .flag("-print-target-info"))
      expectJobInvocationMatches(job, .flag("-target"))
      expectJobInvocationMatches(job, .flag("-use-static-resource-dir"))
    }

    do {
      var driver = try TestDriver(args: [
        "swift", "-print-target-info", "-target", "x86_64-unknown-linux", "-static-executable",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectEqual(job.kind, .printTargetInfo)
      expectJobInvocationMatches(job, .flag("-print-target-info"))
      expectJobInvocationMatches(job, .flag("-target"))
      expectJobInvocationMatches(job, .flag("-use-static-resource-dir"))
    }
  }

  @Test func frontendSupportedArguments() throws {
    do {
      // General case: ensure supported frontend arguments have been computed, one way or another
      let driver = try TestDriver(args: [
        "swift", "-target", "arm64-apple-ios12.0",
        "-resource-dir", "baz",
      ])
      #expect(driver.supportedFrontendFlags.contains("emit-module"))
    }
    do {
      let driver = try TestDriver(args: [
        "swift", "-target", "arm64-apple-ios12.0",
        "-resource-dir", "baz",
      ])
      if let libraryBasedResult = try driver.querySupportedArgumentsForTest() {
        #expect(libraryBasedResult.contains("emit-module"))
      }
    }
    do {
      // Test the fallback path of computing the supported arguments using a swift-frontend
      // invocation, by pointing the driver to look for libSwiftScan in a place that does not
      // exist
      var env = ProcessEnv.block
      env["SWIFT_DRIVER_SWIFT_SCAN_TOOLCHAIN_PATH"] = "/some/nonexistent/path"
      let driver = try TestDriver(
        args: [
          "swift", "-target", "arm64-apple-ios12.0",
          "-resource-dir", "baz",
        ],
        env: env
      )
      #expect(driver.supportedFrontendFlags.contains("emit-module"))
    }
  }

  @Test func emitSupportedArguments() async throws {
    var driver = try TestDriver(args: ["swiftc", "-emit-supported-arguments"])

    let plannedJobs = try await driver.planBuild()
    #expect(plannedJobs.count == 1)
    let job = plannedJobs[0]
    expectEqual(job.kind, .emitSupportedFeatures)
    expectJobInvocationMatches(job, .flag("-frontend"))
    expectJobInvocationMatches(job, .flag("-emit-supported-features"))
  }

  @Test func printOutputFileMap() async throws {
    try await withTemporaryDirectory { path in
      // Replace the error stream with one we capture here.
      let errorStream = stderrStream

      let root = localFileSystem.currentWorkingDirectory!.appending(components: "build")

      let errorOutputFile = path.appending(component: "dummy_error_stream")
      TSCBasic.stderrStream = try ThreadSafeOutputByteStream(LocalFileOutputByteStream(errorOutputFile))

      let libObj: AbsolutePath = root.appending(component: "lib.o")
      let mainObj: AbsolutePath = root.appending(component: "main.o")
      let basicOutputFileMapObj: AbsolutePath = root.appending(component: "basic_output_file_map.o")

      let dummyInput: AbsolutePath = path.appending(component: "output_file_map_test.swift")
      let mainSwift: AbsolutePath = path.appending(components: "Inputs", "main.swift")
      let libSwift: AbsolutePath = path.appending(components: "Inputs", "lib.swift")
      let outputFileMap = path.appending(component: "output_file_map.json")

      let fileMap = ByteString(
        """
        {
            \"\(dummyInput.nativePathString(escaped: true))\": {
                \"object\": \"\(basicOutputFileMapObj.nativePathString(escaped: true))\"
            },
            \"\(mainSwift.nativePathString(escaped: true))\": {
                \"object\": \"\(mainObj.nativePathString(escaped: true))\"
            },
            \"\(libSwift.nativePathString(escaped: true))\": {
                \"object\": \"\(libObj.nativePathString(escaped: true))\"
            }
        }
        """.utf8
      )
      try localFileSystem.writeFileContents(outputFileMap, bytes: fileMap)

      var driver = try TestDriver(args: [
        "swiftc", "-driver-print-output-file-map",
        "-target", "x86_64-apple-macosx10.9",
        "-o", root.appending(component: "basic_output_file_map.out").nativePathString(escaped: false),
        "-module-name", "OutputFileMap",
        "-output-file-map", outputFileMap.nativePathString(escaped: false),
      ])
      try await driver.run(jobs: [])
      let invocationError = try localFileSystem.readFileContents(errorOutputFile).description

      #expect(
        invocationError.contains(
          "\(libSwift.nativePathString(escaped: false)) -> object: \"\(libObj.nativePathString(escaped: false))\""
        )
      )
      #expect(
        invocationError.contains(
          "\(mainSwift.nativePathString(escaped: false)) -> object: \"\(mainObj.nativePathString(escaped: false))\""
        )
      )
      #expect(
        invocationError.contains(
          "\(dummyInput.nativePathString(escaped: false)) -> object: \"\(basicOutputFileMapObj.nativePathString(escaped: false))\""
        )
      )

      // Restore the error stream to what it was
      TSCBasic.stderrStream = errorStream
    }
  }

  @Test func dumpASTOverride() async throws {
    try await assertDriverDiagnostics(args: ["swiftc", "-wmo", "-dump-ast", "foo.swift"]) {
      $1.expect(.warning("ignoring '-wmo' because '-dump-ast' was also specified"))
      let jobs = try await $0.planBuild()
      #expect(jobs[0].kind == .compile)
      #expect(!jobs[0].commandLine.contains("-wmo"))
      expectJobInvocationMatches(jobs[0], .flag("-dump-ast"))
    }

    try await assertDriverDiagnostics(args: [
      "swiftc", "-index-file", "-dump-ast",
      "foo.swift",
      "-index-file-path", "foo.swift",
      "-index-store-path", "store/path",
      "-index-ignore-system-modules",
    ]) {
      $1.expect(.warning("ignoring '-index-file' because '-dump-ast' was also specified"))
      let jobs = try await $0.planBuild()
      #expect(jobs[0].kind == .compile)
      #expect(!jobs[0].commandLine.contains("-wmo"))
      #expect(!jobs[0].commandLine.contains("-index-file"))
      #expect(!jobs[0].commandLine.contains("-index-file-path"))
      #expect(!jobs[0].commandLine.contains("-index-store-path"))
      #expect(!jobs[0].commandLine.contains("-index-ignore-stdlib"))
      #expect(!jobs[0].commandLine.contains("-index-system-modules"))
      #expect(!jobs[0].commandLine.contains("-index-ignore-system-modules"))
      expectJobInvocationMatches(jobs[0], .flag("-dump-ast"))
    }
  }

  @Test func dumpASTFormat() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-dump-ast", "-dump-ast-format", "json", "foo.swift",
    ])
    let plannedJobs = try await driver.planBuild()
    #expect(plannedJobs[0].kind == .compile)
    #expect(plannedJobs[0].commandLine.contains("-dump-ast"))
    #expect(plannedJobs[0].commandLine.contains("-dump-ast-format"))
    #expect(plannedJobs[0].commandLine.contains("json"))
  }

  @Test func deriveSwiftDocPath() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-emit-module", "/tmp/main.swift", "-emit-module-path", "test-ios-macabi.swiftmodule",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

    #expect(plannedJobs.count == 2)
    #expect(plannedJobs[0].kind == .emitModule)
    try expectJobInvocationMatches(plannedJobs[0], .flag("-o"), toPathOption("test-ios-macabi.swiftmodule"))
    try expectJobInvocationMatches(
      plannedJobs[0],
      .flag("-emit-module-doc-path"),
      toPathOption("test-ios-macabi.swiftdoc")
    )
    try expectJobInvocationMatches(
      plannedJobs[0],
      .flag("-emit-module-source-info-path"),
      toPathOption("test-ios-macabi.swiftsourceinfo")
    )
  }

  @Test func aDDITIONAL_SWIFT_DRIVER_FLAGS() async throws {
    var env = ProcessEnv.block
    env["ADDITIONAL_SWIFT_DRIVER_FLAGS"] = "-Xfrontend -unknown1 -Xfrontend -unknown2"
    var driver = try TestDriver(args: ["swiftc", "foo.swift", "-module-name", "Test"], env: env)
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

    #expect(plannedJobs.count == 2)

    expectJobInvocationMatches(plannedJobs[0], .flag("-unknown1"))
    expectJobInvocationMatches(plannedJobs[0], .flag("-unknown2"))

    #expect(plannedJobs[1].kind == .link)
  }
}
