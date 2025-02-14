//===--------------- JobExecutorTests.swift - Swift Execution Tests -------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import TestUtilities

extension Job.ArgTemplate: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .flag(value)
  }
}

class JobCollectingDelegate: JobExecutionDelegate {
  struct StubProcess: ProcessProtocol {
    static func launchProcess(arguments: [String], env: [String : String]) throws -> StubProcess {
      return .init()
    }

    static func launchProcessAndWriteInput(arguments: [String], env: [String : String],
                                           inputFileHandle: FileHandle) throws -> StubProcess {
      return .init()
    }

    var processID: TSCBasic.Process.ProcessID { .init(-1) }

    func waitUntilExit() throws -> ProcessResult {
      return ProcessResult(
        arguments: [],
        environment: [:],
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
}

extension DarwinToolchain {
  /// macOS SDK path, for testing only.
  var sdk: Result<AbsolutePath, Swift.Error> {
    Result {
      let result = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path",
        environment: env
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

final class JobExecutorTests: XCTestCase {
  func testDarwinBasic() throws {
    #if os(macOS)
    let hostTriple = try Driver(args: ["swiftc", "test.swift"]).hostTriple
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.vars)
    let toolchain = DarwinToolchain(env: ProcessEnv.vars, executor: executor)
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
      XCTAssertEqual(output, "5\n")
      XCTAssertEqual(delegate.started.count, 3)

      let fooObject = try resolver.resolve(.path(.temporary(try RelativePath(validating: "foo.o"))))
      XCTAssertTrue(localFileSystem.exists(try AbsolutePath(validating: fooObject)), "expected foo.o to be present in the temporary directory")
      try resolver.removeTemporaryDirectory()
      XCTAssertFalse(localFileSystem.exists(try AbsolutePath(validating: fooObject)), "expected foo.o to be removed from the temporary directory")
    }
#endif
  }

  /// Ensure the executor is capable of forwarding its standard input to the compile job that requires it.
  func testInputForwarding() throws {
    #if os(macOS)
    let hostTriple = try Driver(args: ["swiftc", "test.swift"]).hostTriple
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.vars)
    let toolchain = DarwinToolchain(env: ProcessEnv.vars, executor: executor)
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
      XCTAssertEqual(output, "Hello, World\n")
    }
#endif
  }

  func testStubProcessProtocol() throws {
#if os(Windows)
    throw XCTSkip("processId.getter returning `-1`")
#else
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
    try executor.execute(env: ProcessEnv.vars, fileSystem: localFileSystem)

    XCTAssertEqual(try delegate.finished[0].1.utf8Output(), "test")
#endif
  }

  func testSwiftDriverExecOverride() throws {
    var env = ProcessEnv.vars
    let envVarName = "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC"
    let dummyPath = "/some/garbage/path/fnord"
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: env)

    // DarwinToolchain
    env.removeValue(forKey: envVarName)
    let normalSwiftPath = try DarwinToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    // Match Toolchain temporary shim of a fallback to looking for "swift" before failing.
    XCTAssertTrue(normalSwiftPath.basenameWithoutExt == "swift-frontend" ||
                  normalSwiftPath.basenameWithoutExt == "swift")

    env[envVarName] = dummyPath
    let overriddenSwiftPath = try DarwinToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    XCTAssertEqual(overriddenSwiftPath, try AbsolutePath(validating: dummyPath))

    // GenericUnixToolchain
    env.removeValue(forKey: envVarName)
    let unixSwiftPath = try GenericUnixToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    XCTAssertTrue(unixSwiftPath.basenameWithoutExt == "swift-frontend" ||
                  unixSwiftPath.basenameWithoutExt == "swift")

    env[envVarName] = dummyPath
    let unixOverriddenSwiftPath = try GenericUnixToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    XCTAssertEqual(unixOverriddenSwiftPath, try AbsolutePath(validating: dummyPath))
  }

  func testInputModifiedDuringSingleJobBuild() throws {
#if os(Windows)
    throw XCTSkip("Requires -sdk")
#else
    try withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main, bytes: "let foo = 1")

      var driver = try Driver(args: ["swift", main.pathString])
      let jobs = try driver.planBuild()
      XCTAssertEqual(jobs.count, 1)
      XCTAssertTrue(jobs[0].requiresInPlaceExecution)
      let soleJob = try XCTUnwrap(jobs.first)

      // Sleep for 1s to allow for quiescing mtimes on filesystems with
      // insufficient timestamp precision.
      Thread.sleep(forTimeInterval: 1)

      // Change the file
      try localFileSystem.writeFileContents(main, bytes: "let foo = 1")
      // Ensure that the file modification since the start of the build planning process
      // results in a corresponding error.
      XCTAssertThrowsError(try soleJob.verifyInputsNotModified(since: driver.recordedInputModificationDates, fileSystem: localFileSystem)) {
        XCTAssertEqual($0 as? Job.InputError,
                       .inputUnexpectedlyModified(TypedVirtualPath(file: VirtualPath.absolute(main).intern(), type: .swift)))
      }

    }
#endif
  }

  func testShellEscapingArgsInJobDescription() throws {
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
    XCTAssertEqual(try executor.description(of: job, forceResponseFiles: false),
                   #""\path\to\the tool" "\with space" \withoutspace"#)
#else
    XCTAssertEqual(try executor.description(of: job, forceResponseFiles: false),
                   "'/path/to/the tool' '/with space' /withoutspace")
#endif
  }

  func testInputModifiedDuringMultiJobBuild() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main, bytes: "let foo = 1")

      let other = path.appending(component: "other.swift")
      try localFileSystem.writeFileContents(other, bytes: "let bar = 2")

      let output = path.appending(component: "a.out")

      // Sleep for 1s to allow for quiescing mtimes on filesystems with
      // insufficient timestamp precision.
      Thread.sleep(forTimeInterval: 1)

      try assertDriverDiagnostics(args: ["swiftc", main.pathString, other.pathString,
                                         "-o", output.pathString]) {driver, verifier in
        let jobs = try driver.planBuild()
        XCTAssertTrue(jobs.count > 1)

        // Change the file
        try localFileSystem.writeFileContents(other, bytes: "let bar = 3")

        verifier.expect(.error("input file '\(other.description)' was modified during the build"))
        // There's a tool-specific linker error that usually happens here from
        // whatever job runs last - probably the linker.
        // It's no use testing for a particular error message, let's just make
        // sure we emit the diagnostic we need.
        verifier.permitUnexpected(.error)
        XCTAssertThrowsError(try driver.run(jobs: jobs))
      }
    }
  }

  func testTemporaryFileWriting() throws {
    try withTemporaryDirectory { path in
      let resolver = try ArgsResolver(fileSystem: localFileSystem, temporaryDirectory: .absolute(path))
      let tmpPath = VirtualPath.temporaryWithKnownContents(try .init(validating: "one.txt"), "hello, world!".data(using: .utf8)!)
      let resolvedOnce = try resolver.resolve(.path(tmpPath))
      let readContents = try localFileSystem.readFileContents(.init(validating: resolvedOnce))
      XCTAssertEqual(readContents, "hello, world!")
      let resolvedTwice = try resolver.resolve(.path(tmpPath))
      XCTAssertEqual(resolvedOnce, resolvedTwice)
      let readContents2 = try localFileSystem.readFileContents(.init(validating: resolvedTwice))
      XCTAssertEqual(readContents2, readContents)
    }
  }

  func testResolveSquashedArgs() throws {
    try withTemporaryDirectory { path in
      let resolver = try ArgsResolver(fileSystem: localFileSystem, temporaryDirectory: .absolute(path))
      let tmpPath = VirtualPath.temporaryWithKnownContents(try .init(validating: "one.txt"), "hello, world!".data(using: .utf8)!)
      let tmpPath2 = VirtualPath.temporaryWithKnownContents(try .init(validating: "two.txt"), "goodbye!".data(using: .utf8)!)
      let resolvedCommandLine = try resolver.resolve(
        .squashedArgumentList(option: "--opt=", args: [.path(tmpPath), .path(tmpPath2)]))
      XCTAssertEqual(resolvedCommandLine, "--opt=\(path.appending(component: "one.txt").pathString) \(path.appending(component: "two.txt").pathString)")
#if os(Windows)
      XCTAssertEqual(resolvedCommandLine.spm_shellEscaped(),
                     #""--opt=\#(path.appending(component: "one.txt").pathString) \#(path.appending(component: "two.txt").pathString)""#)
#else
      XCTAssertEqual(resolvedCommandLine.spm_shellEscaped(), "'--opt=\(path.appending(component: "one.txt").pathString) \(path.appending(component: "two.txt").pathString)'")
#endif
    }
  }

  private func getHostToolchainSdkArg(_ executor: SwiftDriverExecutor) throws -> [String] {
    #if os(macOS)
    let toolchain = DarwinToolchain(env: ProcessEnv.vars, executor: executor)
    return try ["-sdk", toolchain.sdk.get().pathString]
    #elseif os(Windows)
    let toolchain = WindowsToolchain(env: ProcessEnv.vars, executor: executor)
    if let path = try toolchain.defaultSDKPath(nil) {
      return ["-sdk", path.nativePathString(escaped: false)]
    }
    return []
    #else
    return []
    #endif
  }

  func testSaveTemps() throws {
    do {
      try withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")

        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.vars)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try Driver(args: ["swiftc", main.pathString,
                                       "-driver-filelist-threshold", "0",
                                       "-o", outputPath.pathString] + getHostToolchainSdkArg(executor),
                                diagnosticsOutput: .engine(diags),
                                fileSystem: localFileSystem,
                                executor: executor)
        let jobs = try driver.planBuild()
        XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
        XCTAssertEqual(jobs[0].outputs.count, 1)
        let compileOutput = jobs[0].outputs[0].file
        guard matchTemporary(compileOutput, "main.o") else {
          XCTFail("unexpected output")
          return
        }
        try driver.run(jobs: jobs)
        XCTAssertTrue(localFileSystem.exists(outputPath))
        // -save-temps wasn't passed, so ensure the temporary file was removed.
        XCTAssertFalse(
          localFileSystem.exists(try .init(validating: try executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
        XCTAssertFalse(localFileSystem.exists(try .init(validating: try executor.resolver.resolve(.path(compileOutput)))))
      }
    }

    do {
      try withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")
        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.vars)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try Driver(args: ["swiftc", main.pathString,
                                       "-save-temps",
                                       "-driver-filelist-threshold", "0",
                                       "-o", outputPath.pathString] + getHostToolchainSdkArg(executor),
                                diagnosticsOutput: .engine(diags),
                                fileSystem: localFileSystem,
                                executor: executor)
        let jobs = try driver.planBuild()
        XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
        XCTAssertEqual(jobs[0].outputs.count, 1)
        let compileOutput = jobs[0].outputs[0].file
        guard matchTemporary(compileOutput, "main.o") else {
          XCTFail("unexpected output")
          return
        }
        try driver.run(jobs: jobs)
        XCTAssertTrue(localFileSystem.exists(outputPath))
        // -save-temps was passed, so ensure the temporary file was not removed.
        XCTAssertTrue(
          localFileSystem.exists(try .init(validating: executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
        XCTAssertTrue(localFileSystem.exists(try .init(validating: executor.resolver.resolve(.path(compileOutput)))))
      }
    }

    do {
      try withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")
        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.vars)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try Driver(args: ["swiftc", main.pathString,
                                       "-driver-filelist-threshold", "0",
                                       "-Xfrontend", "-debug-crash-immediately",
                                       "-o", outputPath.pathString] + getHostToolchainSdkArg(executor),
                                diagnosticsOutput: .engine(diags),
                                fileSystem: localFileSystem,
                                executor: executor)
        let jobs = try driver.planBuild()
        XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
        XCTAssertEqual(jobs[0].outputs.count, 1)
        let compileOutput = jobs[0].outputs[0].file
        guard matchTemporary(compileOutput, "main.o") else {
          XCTFail("unexpected output")
          return
        }
        try? driver.run(jobs: jobs)
        // A job crashed, so ensure any temporary files written so far are preserved.
        XCTAssertTrue(
          localFileSystem.exists(try .init(validating: executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
      }
    }
  }
}
