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

import Foundation
import Testing
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TestUtilities

extension Job.ArgTemplate: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .flag(value)
  }
}

class JobCollectingDelegate: JobExecutionDelegate {
  struct StubProcess: ProcessProtocol {
    static func launchProcess(arguments: [String], env: ProcessEnvironmentBlock) throws -> StubProcess {
      return .init()
    }

    static func launchProcessAndWriteInput(arguments: [String], env: ProcessEnvironmentBlock,
                                           inputFileHandle: FileHandle) throws -> StubProcess {
      return .init()
    }

    var processID: TSCBasic.Process.ProcessID { .init(-1) }

    func waitUntilExit() throws -> ProcessResult {
      return ProcessResult(
        arguments: [],
        environmentBlock: [:],
        exitStatus: .terminated(code: EXIT_SUCCESS),
        output: Result.success(ByteString("test").contents),
        stderrOutput: Result.success([])
      )
    }
  }

  var started: [Job] = []
  var finished: [(Job, ProcessResult)] = []

  func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    finished.append((job, result))
  }

  func jobStarted(job: Job, arguments: [String], pid: Int) {
    started.append(job)
  }

  func jobSkipped(job: Job) {}

  func getReproducerJob(job: Job, output: VirtualPath) -> Job? {
    nil
  }
}

extension DarwinToolchain {
  /// macOS SDK path, for testing only.
  var sdk: Result<AbsolutePath, Swift.Error> {
    Result {
      let result = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path",
        environment: env.legacyVars
      ).spm_chomp()
      return try AbsolutePath(validating: result)
    }
  }

  /// macOS resource directory, for testing only.
  var resourcesDirectory: Result<AbsolutePath, Swift.Error> {
    return Result {
      try AbsolutePath(validating: "../../lib/swift/macosx",
                       relativeTo: getToolPath(.swiftCompiler))
    }
  }

  var clangRT: Result<AbsolutePath, Error> {
    resourcesDirectory.map { try! AbsolutePath(validating: "../clang/lib/darwin/libclang_rt.osx.a",
                                               relativeTo: $0) }
  }

  var compatibility50: Result<AbsolutePath, Error> {
    get throws {
      resourcesDirectory.map { $0.appending(component: "libswiftCompatibility50.a") }
    }
  }

  var compatibilityDynamicReplacements: Result<AbsolutePath, Error> {
    get throws {
      resourcesDirectory.map { $0.appending(component: "libswiftCompatibilityDynamicReplacements.a") }
    }
  }
}

@Suite(.serialized) struct JobExecutorTests {
  @Test(.requireHostOS(.macosx)) func darwinBasic() async throws {
    let hostTriple = try TestDriver(args: ["swiftc", "test.swift"]).hostTriple
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.block)
    let toolchain = DarwinToolchain(env: ProcessEnv.block, executor: executor)
    try withTemporaryDirectory { path in
      let foo = path.appending(component: "foo.swift")
      let main = path.appending(component: "main.swift")

      try localFileSystem.writeFileContents(foo, bytes: "let foo = 5")
      try localFileSystem.writeFileContents(main, bytes: "print(foo)")

      let exec = path.appending(component: "main")

      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      resolver.pathMapping = [
        .relative(try .init(validating: "foo.swift")): foo.pathString,
        .relative(try .init(validating: "main.swift")): main.pathString,
        .relative(try .init(validating: "main")): exec.pathString,
      ]

      let inputs: [String: TypedVirtualPath] = [
        "foo" : .init(file: VirtualPath.relative(try .init(validating: "foo.swift")).intern(), type: .swift),
        "main": .init(file: VirtualPath.relative(try .init(validating: "main.swift")).intern(), type: .swift)
      ]

      let compileFoo = Job(
        moduleName: "main",
        kind: .compile,
        tool: try toolchain.resolvedTool(.swiftCompiler),
        commandLine: [
          "-frontend",
          "-c",
          "-primary-file",
          .path(inputs[ "foo"]!.file),
          .path(inputs["main"]!.file),
          "-target", .flag(hostTriple.triple),
          "-enable-objc-interop",
          "-sdk",
          .path(.absolute(try toolchain.sdk.get())),
          "-module-name", "main",
          "-o", .path(.temporary(try RelativePath(validating: "foo.o"))),
        ],
        inputs: Array(inputs.values),
        primaryInputs: [inputs["foo"]!],
        outputs: [.init(file: VirtualPath.temporary(try RelativePath(validating: "foo.o")).intern(), type: .object)]
      )

      let compileMain = Job(
        moduleName: "main",
        kind: .compile,
        tool: try toolchain.resolvedTool(.swiftCompiler),
        commandLine: [
          "-frontend",
          "-c",
          .path(.relative(try .init(validating: "foo.swift"))),
          "-primary-file",
          .path(inputs["main"]!.file),
          "-target", .flag(hostTriple.triple),
          "-enable-objc-interop",
          "-sdk",
          .path(.absolute(try toolchain.sdk.get())),
          "-module-name", "main",
          "-o", .path(.temporary(try RelativePath(validating: "main.o"))),
        ],
        inputs: Array(inputs.values),
        primaryInputs: [inputs["main"]!],
        outputs: [.init(file: VirtualPath.temporary(try RelativePath(validating: "main.o")).intern(), type: .object)]
      )

      let link = Job(
        moduleName: "main",
        kind: .link,
        tool: try toolchain.resolvedTool(.dynamicLinker),
        commandLine: [
          .path(.temporary(try RelativePath(validating: "foo.o"))),
          .path(.temporary(try RelativePath(validating: "main.o"))),
          .path(.absolute(try toolchain.clangRT.get())),
          "--sysroot", .path(.absolute(try toolchain.sdk.get())),
          "-lobjc", .flag("--target=\(hostTriple.triple)"),
          "-L", .path(.absolute(try toolchain.resourcesDirectory.get())),
          "-L", .path(.absolute(try toolchain.sdkStdlib(sdk: toolchain.sdk.get()))),
          "-rpath", "/usr/lib/swift", "-o",
          .path(.relative(try .init(validating: "main"))),
        ],
        inputs: [
          .init(file: VirtualPath.temporary(try RelativePath(validating: "foo.o")).intern(), type: .object),
          .init(file: VirtualPath.temporary(try RelativePath(validating: "main.o")).intern(), type: .object),
        ],
        primaryInputs: [],
        outputs: [.init(file: VirtualPath.relative(try .init(validating: "main")).intern(), type: .image)]
      )
      let delegate = JobCollectingDelegate()
      let executor = MultiJobExecutor(workload: .all([compileFoo, compileMain, link]),
                                      resolver: resolver, executorDelegate: delegate, diagnosticsEngine: DiagnosticsEngine())
      try executor.execute(env: toolchain.env, fileSystem: localFileSystem)

      let output = try TSCBasic.Process.checkNonZeroExit(args: exec.pathString)
      #expect(output == "5\n")
      #expect(delegate.started.count == 3)

      let fooObject = try resolver.resolve(.path(.temporary(try RelativePath(validating: "foo.o"))))
      #expect(localFileSystem.exists(try AbsolutePath(validating: fooObject)), "expected foo.o to be present in the temporary directory")
      try resolver.removeTemporaryDirectory()
      #expect(!localFileSystem.exists(try AbsolutePath(validating: fooObject)), "expected foo.o to be removed from the temporary directory")
    }
  }

  /// Ensure the executor is capable of forwarding its standard input to the compile job that requires it.
  @Test(.requireHostOS(.macosx)) func inputForwarding() async throws {
    let hostTriple = try TestDriver(args: ["swiftc", "test.swift"]).hostTriple
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.block)
    let toolchain = DarwinToolchain(env: ProcessEnv.block, executor: executor)
    try withTemporaryDirectory { path in
      let exec = path.appending(component: "main")
      let compile = Job(
        moduleName: "main",
        kind: .compile,
        tool: try toolchain.resolvedTool(.swiftCompiler),
        commandLine: [
          "-frontend",
          "-c",
          "-primary-file",
          // This compile job must read the input from STDIN
          "-",
          "-target", .flag(hostTriple.triple),
          "-enable-objc-interop",
          "-sdk",
          .path(.absolute(try toolchain.sdk.get())),
          "-module-name", "main",
          "-o", .path(.temporary(try RelativePath(validating: "main.o"))),
        ],
        inputs: [TypedVirtualPath(file: .standardInput, type: .swift )],
        primaryInputs: [TypedVirtualPath(file: .standardInput, type: .swift )],
        outputs: [.init(file: VirtualPath.temporary(try RelativePath(validating: "main.o")).intern(),
                        type: .object)]
      )
      let link = Job(
        moduleName: "main",
        kind: .link,
        tool: try toolchain.resolvedTool(.dynamicLinker),
        commandLine: [
          .path(.temporary(try RelativePath(validating: "main.o"))),
          "--sysroot", .path(.absolute(try toolchain.sdk.get())),
          "-lobjc", .flag("--target=\(hostTriple.triple)"),
          "-L", .path(.absolute(try toolchain.resourcesDirectory.get())),
          "-L", .path(.absolute(try toolchain.sdkStdlib(sdk: toolchain.sdk.get()))),
          "-o", .path(.absolute(exec)),
        ],
        inputs: [
          .init(file: VirtualPath.temporary(try RelativePath(validating: "main.o")).intern(), type: .object),
        ],
        primaryInputs: [],
        outputs: [.init(file: VirtualPath.relative(try .init(validating: "main")).intern(), type: .image)]
      )

      // Create a file with inpuit
      let inputFile = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(inputFile, bytes: "print(\"Hello, World\")")

      // We are going to override he executors standard input FileHandle to the above
      // input file, to simulate it being piped over standard input to this compilation.
      let testFile: FileHandle = FileHandle(forReadingAtPath: inputFile.description)!
      let delegate = JobCollectingDelegate()
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let executor = MultiJobExecutor(workload: .all([compile, link]),
                                      resolver: resolver, executorDelegate: delegate,
                                      diagnosticsEngine: DiagnosticsEngine(),
                                      inputHandleOverride: testFile)
      try executor.execute(env: toolchain.env, fileSystem: localFileSystem)

      // Execute the resulting program
      let output = try TSCBasic.Process.checkNonZeroExit(args: exec.pathString)
      #expect(output == "Hello, World\n")
    }
  }

  @Test(.skipHostOS(.win32, comment: "processId.getter returning `-1`"))
  func stubProcessProtocol() throws {
    let job = Job(
      moduleName: "main",
      kind: .compile,
      tool: ResolvedTool(path: try AbsolutePath(validating: "/usr/bin/swift"), supportsResponseFiles: false),
      commandLine: [.flag("something")],
      inputs: [],
      primaryInputs: [],
      outputs: [.init(file: VirtualPath.temporary(try RelativePath(validating: "main")).intern(), type: .object)]
    )

    let delegate = JobCollectingDelegate()
    let executor = MultiJobExecutor(
      workload: .all([job]), resolver: try ArgsResolver(fileSystem: localFileSystem),
      executorDelegate: delegate,
      diagnosticsEngine: DiagnosticsEngine(),
      processType: JobCollectingDelegate.StubProcess.self
    )
    try executor.execute(env: ProcessEnv.block, fileSystem: localFileSystem)

    #expect(try delegate.finished[0].1.utf8Output() == "test")
  }

  @Test func swiftDriverExecOverride() throws {
    var env = ProcessEnv.block
    let envVarName = ProcessEnvironmentKey("SWIFT_DRIVER_SWIFT_FRONTEND_EXEC")
    let dummyPath = "/some/garbage/path/fnord"
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: env)

    // DarwinToolchain
    env.removeValue(forKey: envVarName)
    let normalSwiftPath = try DarwinToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    // Match Toolchain temporary shim of a fallback to looking for "swift" before failing.
    #expect(normalSwiftPath.basenameWithoutExt == "swift-frontend" ||
                  normalSwiftPath.basenameWithoutExt == "swift")

    env[envVarName] = dummyPath
    let overriddenSwiftPath = try DarwinToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    #expect(try overriddenSwiftPath == AbsolutePath(validating: dummyPath))

    // GenericUnixToolchain
    env.removeValue(forKey: envVarName)
    let unixSwiftPath = try GenericUnixToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    #expect(unixSwiftPath.basenameWithoutExt == "swift-frontend" ||
                  unixSwiftPath.basenameWithoutExt == "swift")

    env[envVarName] = dummyPath
    let unixOverriddenSwiftPath = try GenericUnixToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    #expect(try unixOverriddenSwiftPath == AbsolutePath(validating: dummyPath))
  }

  @Test(.skipHostOS(.win32, comment: "Requires -sdk"))
  func inputModifiedDuringSingleJobBuild() async throws {
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main, bytes: "let foo = 1")

      var driver = try TestDriver(args: ["swift", main.pathString])
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].requiresInPlaceExecution)
      let soleJob = try #require(jobs.first)

      // Touch timestamp file, which in process ensures the file system timestamp changed.
      try! localFileSystem.touch(path.appending(component: "timestamp"))

      // Change the file
      try localFileSystem.writeFileContents(main, bytes: "let foo = 1")
      // Ensure that the file modification since the start of the build planning process
      // results in a corresponding error.
      #expect(throws: (any Error).self) { try soleJob.verifyInputsNotModified(since: driver.recordedInputMetadata.mapValues{$0.mTime}, fileSystem: localFileSystem) }

    }
  }

  @Test func shellEscapingArgsInJobDescription() throws {
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: [:])
    let job = Job(moduleName: "Module",
                  kind: .compile,
                  tool: ResolvedTool(
                    path: try AbsolutePath(validating: "/path/to/the tool"),
                    supportsResponseFiles: false),
                  commandLine: [.path(.absolute(try .init(validating: "/with space"))),
                                .path(.absolute(try .init(validating: "/withoutspace")))],
                  inputs: [], primaryInputs: [], outputs: [])
#if os(Windows)
    #expect(try executor.description(of: job, forceResponseFiles: false) ==
                   #""\path\to\the tool" "\with space" \withoutspace"#)
#else
    #expect(try executor.description(of: job, forceResponseFiles: false) ==
                   "'/path/to/the tool' '/with space' /withoutspace")
#endif
  }

  @Test func inputModifiedDuringMultiJobBuild() async throws {
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main, bytes: "let foo = 1")

      let other = path.appending(component: "other.swift")
      try localFileSystem.writeFileContents(other, bytes: "let bar = 2")

      let output = path.appending(component: "a.out")

      // Touch timestamp file, which in process ensures the file system timestamp changed.
      try! localFileSystem.touch(path.appending(component: "timestamp"))

      try await assertDriverDiagnostics(args: ["swiftc", main.pathString, other.pathString,
                                         "-o", output.pathString]) {driver, verifier in
        let jobs = try await driver.planBuild()
        #expect(jobs.count > 1)

        // Change the file
        try localFileSystem.writeFileContents(other, bytes: "let bar = 3")

        verifier.expect(.error("input file '\(other.description)' was modified during the build"))
        // There's a tool-specific linker error that usually happens here from
        // whatever job runs last - probably the linker.
        // It's no use testing for a particular error message, let's just make
        // sure we emit the diagnostic we need.
        verifier.permitUnexpected(.error)
        await #expect(throws: (any Error).self) { try await driver.run(jobs: jobs) }
      }
    }
  }

  @Test func temporaryFileWriting() throws {
    try withTemporaryDirectory { path in
      let resolver = try ArgsResolver(fileSystem: localFileSystem, temporaryDirectory: .absolute(path))
      let tmpPath = VirtualPath.temporaryWithKnownContents(try .init(validating: "one.txt"), "hello, world!".data(using: .utf8)!)
      let resolvedOnce = try resolver.resolve(.path(tmpPath))
      let readContents = try localFileSystem.readFileContents(.init(validating: resolvedOnce))
      #expect(readContents == "hello, world!")
      let resolvedTwice = try resolver.resolve(.path(tmpPath))
      #expect(resolvedOnce == resolvedTwice)
      let readContents2 = try localFileSystem.readFileContents(.init(validating: resolvedTwice))
      #expect(readContents2 == readContents)
    }
  }

  @Test func resolveSquashedArgs() throws {
    try withTemporaryDirectory { path in
      let resolver = try ArgsResolver(fileSystem: localFileSystem, temporaryDirectory: .absolute(path))
      let tmpPath = VirtualPath.temporaryWithKnownContents(try .init(validating: "one.txt"), "hello, world!".data(using: .utf8)!)
      let tmpPath2 = VirtualPath.temporaryWithKnownContents(try .init(validating: "two.txt"), "goodbye!".data(using: .utf8)!)
      let resolvedCommandLine = try resolver.resolve(
        .squashedArgumentList(option: "--opt=", args: [.path(tmpPath), .path(tmpPath2)]))
      #expect(resolvedCommandLine == "--opt=\(path.appending(component: "one.txt").pathString) \(path.appending(component: "two.txt").pathString)")
#if os(Windows)
      #expect(resolvedCommandLine.spm_shellEscaped() ==
                     #""--opt=\#(path.appending(component: "one.txt").pathString) \#(path.appending(component: "two.txt").pathString)""#)
#else
      #expect(resolvedCommandLine.spm_shellEscaped() == "'--opt=\(path.appending(component: "one.txt").pathString) \(path.appending(component: "two.txt").pathString)'")
#endif
    }
  }

  private func getHostToolchainSdkArg(_ executor: SwiftDriverExecutor) throws -> [String] {
    #if os(macOS)
    let toolchain = DarwinToolchain(env: ProcessEnv.block, executor: executor)
    return try ["-sdk", toolchain.sdk.get().pathString]
    #elseif os(Windows)
    let toolchain = WindowsToolchain(env: ProcessEnv.block, executor: executor)
    if let path = try toolchain.defaultSDKPath(nil) {
      return ["-sdk", path.nativePathString(escaped: false)]
    }
    return []
    #else
    return []
    #endif
  }

  @Test func saveTemps() async throws {
    do {
      try await withTemporaryDirectory(removeTreeOnDeinit: true) { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")

        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.block)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try TestDriver(args: ["swiftc", main.pathString,
                                       "-driver-filelist-threshold", "0",
                                       "-o", outputPath.pathString] + getHostToolchainSdkArg(executor),
                                diagnosticsEngine: diags,
                                executor: executor)
        let jobs = try await driver.planBuild()
        #expect(jobs.removingAutolinkExtractJobs().map(\.kind) == [.compile, .link])
        #expect(jobs[0].outputs.count == 1)
        let compileOutput = jobs[0].outputs[0].file
        guard matchTemporary(compileOutput, "main.o") else {
          Issue.record("unexpected output")
          return
        }
        try await driver.run(jobs: jobs)
        #expect(localFileSystem.exists(outputPath))
        // -save-temps wasn't passed, so ensure the temporary file was removed.
        #expect(
          !localFileSystem.exists(try .init(validating: try executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
        #expect(!localFileSystem.exists(try .init(validating: try executor.resolver.resolve(.path(compileOutput)))))
      }
    }

    do {
      try await withTemporaryDirectory(removeTreeOnDeinit: true) { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")
        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.block)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try TestDriver(args: ["swiftc", main.pathString,
                                       "-save-temps",
                                       "-sil-output-dir", path.pathString,
                                       "-ir-output-dir", path.pathString,
                                       "-driver-filelist-threshold", "0",
                                       "-o", outputPath.pathString] + getHostToolchainSdkArg(executor),
                                diagnosticsEngine: diags,
                                executor: executor)
        let jobs = try await driver.planBuild()
        #expect(jobs.removingAutolinkExtractJobs().map(\.kind) == [.compile, .link])
        // With -save-temps, we now have additional SIL and IR outputs, so expect more outputs
        #expect(jobs[0].outputs.count >= 1, "Should have at least the object file output")
        // Find the main object file output
        let objectOutput = jobs[0].outputs.first { $0.type == .object }
        #expect(objectOutput != nil, "Should have object file output")
        let compileOutput = objectOutput!.file
        guard matchTemporary(compileOutput, "main.o") else {
          Issue.record("unexpected output")
          return
        }
        try await driver.run(jobs: jobs)
        #expect(localFileSystem.exists(outputPath))
        // -save-temps was passed, so ensure the temporary file was not removed.
        #expect(
          localFileSystem.exists(try .init(validating: executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
        #expect(localFileSystem.exists(try .init(validating: executor.resolver.resolve(.path(compileOutput)))))
      }
    }

    do {
      try await withTemporaryDirectory(removeTreeOnDeinit: true) { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")
        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.block)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try TestDriver(args: ["swiftc", main.pathString,
                                       "-driver-filelist-threshold", "0",
                                       "-Xfrontend", "-debug-crash-immediately",
                                       "-o", outputPath.pathString] + getHostToolchainSdkArg(executor),
                                diagnosticsEngine: diags,
                                executor: executor)
        let jobs = try await driver.planBuild()
        #expect(jobs.removingAutolinkExtractJobs().map(\.kind) == [.compile, .link])
        #expect(jobs[0].outputs.count == 1)
        let compileOutput = jobs[0].outputs[0].file
        guard matchTemporary(compileOutput, "main.o") else {
          Issue.record("unexpected output")
          return
        }
        try? await driver.run(jobs: jobs)
        // A job crashed, so ensure any temporary files written so far are preserved.
        #expect(
          localFileSystem.exists(try .init(validating: executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
      }
    }

  }

  /// Test that -save-temps also saves SIL and IR intermediate files.
  @Test(.requireFrontendArgSupport(.silOutputPath), .requireFrontendArgSupport(.irOutputPath))
  func saveTempsSILAndIR() async throws {
    try await withTemporaryDirectory(removeTreeOnDeinit: true) { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")
      let diags = DiagnosticsEngine()
      let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                             processSet: ProcessSet(),
                                             fileSystem: localFileSystem,
                                             env: ProcessEnv.block)
      let outputPath = path.appending(component: "finalOutput")
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-save-temps",
                                     "-o", outputPath.pathString] + getHostToolchainSdkArg(executor),
                              diagnosticsEngine: diags,
                              executor: executor)
      let jobs = try await driver.planBuild()
      let compileJobs = jobs.removingAutolinkExtractJobs()
      #expect(compileJobs.map(\.kind) == [.compile, .link])

      let compileJob = compileJobs[0]

      #expect(compileJob.commandLine.contains(.flag("-sil-output-path")))
      #expect(compileJob.commandLine.contains(.flag("-ir-output-path")))

      let hasMultipleOutputs = compileJob.outputs.count > 1
      #expect(hasMultipleOutputs, "Should have additional SIL/IR outputs when using -save-temps")
    }
  }
}
