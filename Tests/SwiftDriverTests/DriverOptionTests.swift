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

@testable @_spi(Testing) import SwiftDriver
import SwiftOptions
import TSCBasic
import Testing
import TestUtilities

@Suite struct DriverOptionTests {

  @Test func invocationRunModes() throws {

    let driver1 = try Driver.invocationRunMode(forArgs: ["swift"])
    #expect(driver1.mode == .normal(isRepl: false))
    #expect(driver1.args == ["swift"])

    let driver2 = try Driver.invocationRunMode(forArgs: ["swift", "-buzz"])
    #expect(driver2.mode == .normal(isRepl: false))
    #expect(driver2.args == ["swift", "-buzz"])

    let driver3 = try Driver.invocationRunMode(forArgs: ["swift", "/"])
    #expect(driver3.mode == .normal(isRepl: false))
    #expect(driver3.args == ["swift", "/"])

    let driver4 = try Driver.invocationRunMode(forArgs: ["swift", "./foo"])
    #expect(driver4.mode == .normal(isRepl: false))
    #expect(driver4.args == ["swift", "./foo"])

    let driver5 = try Driver.invocationRunMode(forArgs: ["swift", "repl"])
    #expect(driver5.mode == .normal(isRepl: true))
    #expect(driver5.args == ["swift", "-repl"])

    let driver6 = try Driver.invocationRunMode(forArgs: ["swift", "foo", "bar"])
    #expect(driver6.mode == .subcommand(executableName("swift-foo")))
    #expect(driver6.args == [executableName("swift-foo"), "bar"])

    let driver7 = try Driver.invocationRunMode(forArgs: ["swift", "-frontend", "foo", "bar"])
    #expect(driver7.mode == .subcommand(executableName("swift-frontend")))
    #expect(driver7.args == [executableName("swift-frontend"), "foo", "bar"])

    let driver8 = try Driver.invocationRunMode(forArgs: ["swift", "-modulewrap", "foo", "bar"])
    #expect(driver8.mode == .subcommand(executableName("swift-frontend")))
    #expect(driver8.args == [executableName("swift-frontend"), "-modulewrap", "foo", "bar"])
  }

  @Test func subcommandsHandling() throws {

    #expect(throws: Never.self) { try TestDriver(args: ["swift"]) }
    #expect(throws: Never.self) { try TestDriver(args: ["swift", "-I=foo"]) }
    #expect(throws: Never.self) { try TestDriver(args: ["swift", ".foo"]) }
    #expect(throws: Never.self) { try TestDriver(args: ["swift", "/foo"]) }

    #expect(throws: (any Error).self) { try TestDriver(args: ["swift", "foo"]) }
  }

  @Test func driverKindParsing() async throws {
    func assertArgs(
      _ args: String...,
      parseTo driverKind: DriverKind,
      leaving remainingArgs: [String],
      sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
      var args = args
      let result = try Driver.determineDriverKind(args: &args)

      #expect(result == driverKind, sourceLocation: sourceLocation)
      #expect(args == remainingArgs, sourceLocation: sourceLocation)
    }
    func assertArgsThrow(
      _ args: String...,
      sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
      var args = args
      #expect(throws: (any Error).self) { try Driver.determineDriverKind(args: &args) }
    }

    try await assertArgs("swift", parseTo: .interactive, leaving: [])
    try await assertArgs("/path/to/swift", parseTo: .interactive, leaving: [])
    try await assertArgs("swiftc", parseTo: .batch, leaving: [])
    try await assertArgs(".build/debug/swiftc", parseTo: .batch, leaving: [])
    try await assertArgs("swiftc", "--driver-mode=swift", parseTo: .interactive, leaving: [])
    try await assertArgs("swift", "-zelda", parseTo: .interactive, leaving: ["-zelda"])
    try await assertArgs("swiftc", "--driver-mode=swift", "swiftc",
                         parseTo: .interactive, leaving: ["swiftc"])
    try await assertArgsThrow("driver")
    try await assertArgsThrow("swiftc", "--driver-mode=blah")
    try await assertArgsThrow("swiftc", "--driver-mode=")
  }

  @Test func compilerMode() throws {
    do {
      let driver1 = try TestDriver(args: ["swift", "main.swift"])
      #expect(driver1.compilerMode == .immediate)

      let driver2 = try TestDriver(args: ["swift"])
      #expect(driver2.compilerMode == .intro)
    }

    do {
      let driver1 = try TestDriver(args: ["swiftc", "main.swift", "-whole-module-optimization"])
      #expect(driver1.compilerMode == .singleCompile)

      let driver2 = try TestDriver(args: ["swiftc", "main.swift", "-whole-module-optimization", "-no-whole-module-optimization"])
      #expect(driver2.compilerMode == .standardCompile)

      let driver3 = try TestDriver(args: ["swiftc", "main.swift", "-g"])
      #expect(driver3.compilerMode == .standardCompile)
    }
  }

  @Test func joinedPathOptions() async throws {
    var driver = try TestDriver(args: ["swiftc", "-c", "-I=/some/dir", "-F=other/relative/dir", "foo.swift"])
    let jobs = try await driver.planBuild()
    try expectJobInvocationMatches(jobs[0], .joinedOptionAndPath("-I=", .absolute(.init(validating: "/some/dir"))))
    try expectJobInvocationMatches(jobs[0], .joinedOptionAndPath("-F=", toPath("other/relative/dir")))
  }

  @Test func relativeOptionOrdering() async throws {
    var driver = try TestDriver(args: ["swiftc", "foo.swift",
                                   "-F", "/path/to/frameworks",
                                   "-I", "/path/to/modules",
                                   "-Fsystem", "/path/to/systemframeworks",
                                   "-Isystem", "/path/to/systemmodules",
                                   "-F", "/path/to/more/frameworks",
                                   "-I", "/path/to/more/modules"])
    let jobs = try await driver.planBuild()
    #expect(jobs[0].kind == .compile)
    // The relative ordering of -F and -Fsystem options should be preserved.
    // The relative ordering of -I and -Isystem, and -F and -Fsystem options should be preserved,
    // but all -I options should come before all -F options.
    try expectJobInvocationMatches(jobs[0],
                                     .flag("-I"),
                                     .path(.absolute(.init(validating: "/path/to/modules"))),
                                     .flag("-Isystem"),
                                     .path(.absolute(.init(validating: "/path/to/systemmodules"))),
                                     .flag("-I"),
                                     .path(.absolute(.init(validating: "/path/to/more/modules"))),
                                     .flag("-F"),
                                     .path(.absolute(.init(validating: "/path/to/frameworks"))),
                                     .flag("-Fsystem"),
                                     .path(.absolute(.init(validating: "/path/to/systemframeworks"))),
                                     .flag("-F"),
                                     .path(.absolute(.init(validating: "/path/to/more/frameworks"))))
  }

  @Test func runtimeCompatibilityVersion() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "a.swift", "-runtime-compatibility-version", "none")
  }

  @Test func inputFiles() throws {
    let driver1 = try TestDriver(args: ["swiftc", "a.swift", "/tmp/b.swift"])
    try expectEqual(driver1.inputFiles,
                   [ TypedVirtualPath(file: try toPath("a.swift").intern(), type: .swift),
                     TypedVirtualPath(file: VirtualPath.absolute(try AbsolutePath(validating: "/tmp/b.swift")).intern(), type: .swift) ])

    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "wobble")
    let tempDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "tmp")

    let driver2 = try TestDriver(args: ["swiftc", "a.swift", "-working-directory", workingDirectory.pathString, rebase("b.swift", at: tempDirectory)])
    try expectEqual(driver2.inputFiles,
                   [ TypedVirtualPath(file: VirtualPath.absolute(try AbsolutePath(validating: rebase("a.swift", at: workingDirectory))).intern(), type: .swift),
                     TypedVirtualPath(file: VirtualPath.absolute(try AbsolutePath(validating: rebase("b.swift", at: tempDirectory))).intern(), type: .swift) ])

    let driver3 = try TestDriver(args: ["swift", "-"])
    #expect(driver3.inputFiles == [ TypedVirtualPath(file: .standardInput, type: .swift )])

    let driver4 = try TestDriver(args: ["swift", "-", "-working-directory" , "-wobble"])
    #expect(driver4.inputFiles == [ TypedVirtualPath(file: .standardInput, type: .swift )])
  }

  @Test func dashE() async throws {
    let fs = localFileSystem

    var driver1 = try TestDriver(args: ["swift", "-e", "print(1)", "-e", "print(2)", "foo/bar.swift", "baz/quux.swift"])
    #expect(driver1.inputFiles.count == 1)
    #expect(driver1.inputFiles[0].file.basename == "main.swift")
    let tempFileContentsForDriver1 = try fs.readFileContents(try #require(driver1.inputFiles[0].file.absolutePath))
    #expect(tempFileContentsForDriver1.description.hasSuffix("\nprint(1)\nprint(2)\n"))

    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 1)
    #expect(plannedJobs[0].kind == .interpret)
    expectEqual(plannedJobs[0].commandLine.drop(while: { $0 != .flag("--") }),
                   [.flag("--"), .flag("foo/bar.swift"), .flag("baz/quux.swift")])

    #expect(throws: (any Error).self) { try TestDriver(args: ["swiftc", "baz/main.swift", "-e", "print(1)"]) }
  }

  @Test func dashEJoined() throws {
    #expect {
      try TestDriver(args: ["swift", "-eprint(1)", "foo/bar.swift", "baz/quux.swift"])
    } throws: { error in
      (error as? OptionParseError) == .unknownOption(index: 0, argument: "-eprint(1)")
    }
  }

  @Test func primaryOutputKinds() throws {
    let driver1 = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module"])
    #expect(driver1.compilerOutputType == .swiftModule)
    #expect(driver1.linkerOutputType == nil)

    let driver2 = try TestDriver(args: ["swiftc", "foo.swift", "-emit-library"])
    #expect(driver2.compilerOutputType == .object)
    #expect(driver2.linkerOutputType == .dynamicLibrary)

    let driver3 = try TestDriver(args: ["swiftc", "-static", "foo.swift", "-emit-library"])
    #expect(driver3.compilerOutputType == .object)
    #expect(driver3.linkerOutputType == .staticLibrary)

    let driver4 = try TestDriver(args: ["swiftc", "-lto=llvm-thin", "foo.swift", "-emit-library"])
    #expect(driver4.compilerOutputType == .llvmBitcode)
    let driver5 = try TestDriver(args: ["swiftc", "-lto=llvm-full", "foo.swift", "-emit-library"])
    #expect(driver5.compilerOutputType == .llvmBitcode)
  }

  @Test func ltoOutputModeClash() throws {
    let driver1 = try TestDriver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-static",
                                    "-emit-library", "-target", "x86_64-apple-macosx10.9"])
    #expect(driver1.compilerOutputType == .llvmBitcode)

    let driver2 = try TestDriver(args: ["swiftc", "foo.swift", "-lto=llvm-full",
                                    "-emit-library", "-target", "x86_64-apple-macosx10.9"])
    #expect(driver2.compilerOutputType == .llvmBitcode)

    let driver3 = try TestDriver(args: ["swiftc", "foo.swift", "-lto=llvm-full",
                                    "c", "-target", "x86_64-apple-macosx10.9"])
    #expect(driver3.compilerOutputType == .llvmBitcode)

    let driver4 = try TestDriver(args: ["swiftc", "foo.swift", "-c","-lto=llvm-full",
                                    "-target", "x86_64-apple-macosx10.9"])
    #expect(driver4.compilerOutputType == .llvmBitcode)

    let driver5 = try TestDriver(args: ["swiftc", "foo.swift", "-c","-lto=llvm-full",
                                    "-emit-bc", "-target", "x86_64-apple-macosx10.9"])
    #expect(driver5.compilerOutputType == .llvmBitcode)

    let driver6 = try TestDriver(args: ["swiftc", "foo.swift", "-emit-bc", "-c","-lto=llvm-full",
                                    "-target", "x86_64-apple-macosx10.9"])
    #expect(driver6.compilerOutputType == .llvmBitcode)
  }

  @Test func ltoOutputPath() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-c", "-target", "x86_64-apple-macosx10.9"])
      #expect(driver.compilerOutputType == .llvmBitcode)
      #expect(driver.linkerOutputType == nil)
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].outputs.count == 1)
      #expect(jobs[0].outputs[0].file.basename == "foo.bc")
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-c", "-target", "x86_64-apple-macosx10.9", "-o", "foo.o"])
      #expect(driver.compilerOutputType == .llvmBitcode)
      #expect(driver.linkerOutputType == nil)
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].outputs.count == 1)
      #expect(jobs[0].outputs[0].file.basename == "foo.o")
    }
  }

  @Test func primaryOutputKindsDiagnostics() async throws {
      try await assertDriverDiagnostics(args: "swift", "-i") {
        $1.expect(.error("the flag '-i' is no longer required and has been removed; use 'swift input-filename'"))
      }
  }

  @Test func filePrefixMapInvalidDiagnostic() async throws {
    try await assertDriverDiagnostics(args: "swiftc", "-c", "foo.swift", "-o", "foo.o", "-file-prefix-map", "invalid") {
      $1.expect(.error("values for '-file-prefix-map' must be in the format 'original=remapped', but 'invalid' was provided"))
    }
  }

  @Test func filePrefixMapMultiplePassToFrontend() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-file-prefix-map", "foo=bar", "-file-prefix-map", "dog=doggo") { driver in
        let jobs = try await driver.planBuild()
        let commandLine = jobs[0].commandLine
        let index = commandLine.firstIndex(of: .flag("-file-prefix-map"))
        let lastIndex = commandLine.lastIndex(of: .flag("-file-prefix-map"))
        #expect(index != nil)
        #expect(lastIndex != nil)
        #expect(index != lastIndex)
        expectEqual(commandLine[index!.advanced(by: 1)], .flag("foo=bar"))
        expectEqual(commandLine[lastIndex!.advanced(by: 1)], .flag("dog=doggo"))
    }
  }

  @Test func indexIncludeLocals() async throws {
    // Make sure `-index-include-locals` is only passed to the frontend when
    // requested, not by default.
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-index-store-path", "/tmp/idx") { driver in
        let jobs = try await driver.planBuild()
        let commandLine = jobs[0].commandLine
        expectCommandLineContains(commandLine, .flag("-index-store-path"))
        #expect(!commandLine.contains(.flag("-index-include-locals")))
    }
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-index-store-path", "/tmp/idx", "-index-include-locals") { driver in
        let jobs = try await driver.planBuild()
        let commandLine = jobs[0].commandLine
        expectCommandLineContains(commandLine, .flag("-index-store-path"))
        expectCommandLineContains(commandLine, .flag("-index-include-locals"))
    }
  }

  @Test func debugSettings() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module") { driver in
      #expect(driver.debugInfo.level == nil)
      #expect(driver.debugInfo.format == .dwarf)
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g") { driver in
      #expect(driver.debugInfo.level == .astTypes)
      #expect(driver.debugInfo.format == .dwarf)
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "-g", "foo.swift", "-gline-tables-only") { driver in
      #expect(driver.debugInfo.level == .lineTables)
      #expect(driver.debugInfo.format == .dwarf)
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-debug-prefix-map", "foo=bar=baz", "-debug-prefix-map", "qux=") { driver in
        let jobs = try await driver.planBuild()
        expectJobInvocationMatches(jobs[0], .flag("-debug-prefix-map"), .flag("foo=bar=baz"), .flag("-debug-prefix-map"), .flag("qux="))
    }

    do {
      var env = ProcessEnv.block
      env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
      env["RC_DEBUG_PREFIX_MAP"] = "old=new"
      var driver = try TestDriver(args: ["swiftc", "-c", "-target", "arm64-apple-macos12", "foo.swift"], env: env)
      let jobs = try await driver.planBuild()
      expectJobInvocationMatches(jobs[0], .flag("-debug-prefix-map"), .flag("old=new"))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-debug-prefix-map", "foo", "-debug-prefix-map", "bar") {
        $1.expect(.error("values for '-debug-prefix-map' must be in the format 'original=remapped', but 'foo' was provided"))
        $1.expect(.error("values for '-debug-prefix-map' must be in the format 'original=remapped', but 'bar' was provided"))
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=codeview") { driver in
      #expect(driver.debugInfo.level == .astTypes)
      #expect(driver.debugInfo.format == .codeView)

      let jobs = try await driver.planBuild()
      expectJobInvocationMatches(jobs[0], .flag("-debug-info-format=codeview"))
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=dwarf") { driver in
      #expect(driver.debugInfo.format == .dwarf)

      let jobs = try await driver.planBuild()
      expectJobInvocationMatches(jobs[0], .flag("-debug-info-format=dwarf"))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-debug-info-format=dwarf") {
      $1.expect(.error("option '-debug-info-format=' is missing a required argument (-g)"))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=notdwarf") {
      $1.expect(.error("invalid value 'notdwarf' in '-debug-info-format='"))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-gdwarf-types", "-debug-info-format=codeview") {
      $1.expect(.error("argument '-debug-info-format=codeview' is not allowed with '-gdwarf-types'"))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-dwarf-version=0") {
      $1.expect(.error("invalid value '0' in '-dwarf-version="))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-dwarf-version=6") {
      $1.expect(.error("invalid value '6' in '-dwarf-version="))
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-file-compilation-dir", ".") { driver in
      let jobs = try await driver.planBuild()
      let path = try VirtualPath.intern(path: ".")
      expectJobInvocationMatches(jobs[0], .flag("-file-compilation-dir"), .path(VirtualPath.lookup(path)))
    }

    let workingDirectory = try AbsolutePath(validating: "/tmp")
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-working-directory", workingDirectory.nativePathString(escaped: false)) { driver in
      let jobs = try await driver.planBuild()
      let path = try VirtualPath.intern(path: workingDirectory.nativePathString(escaped: false))
      expectJobInvocationMatches(jobs[0], .flag("-file-compilation-dir"), .path(VirtualPath.lookup(path)))
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c") { driver in
      let jobs = try await driver.planBuild()
      expectJobInvocationMatches(jobs[0], .flag("-file-compilation-dir"))
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-c", "-file-compilation-dir", ".") { driver in
      let jobs = try await driver.planBuild()
      #expect(!jobs[0].commandLine.contains(.flag("-file-compilation-dir")))
    }
  }

  @Test func coverageSettings() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-coverage-prefix-map", "foo=bar=baz", "-coverage-prefix-map", "qux=") { driver in
      let jobs = try await driver.planBuild()
      expectJobInvocationMatches(jobs[0], .flag("-coverage-prefix-map"), .flag("foo=bar=baz"), .flag("-coverage-prefix-map"), .flag("qux="))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-coverage-prefix-map", "foo", "-coverage-prefix-map", "bar") {
      $1.expect(.error("values for '-coverage-prefix-map' must be in the format 'original=remapped', but 'foo' was provided"))
      $1.expect(.error("values for '-coverage-prefix-map' must be in the format 'original=remapped', but 'bar' was provided"))
    }
  }

  @Test func hermeticSealAtLink() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-experimental-hermetic-seal-at-link", "-lto=llvm-full") { driver in
      let jobs = try await driver.planBuild()
      let commandLine = jobs[0].commandLine
      expectCommandLineContains(commandLine, .flag("-enable-llvm-vfe"))
      expectCommandLineContains(commandLine, .flag("-enable-llvm-wme"))
      expectCommandLineContains(commandLine, .flag("-conditional-runtime-records"))
      expectCommandLineContains(commandLine, .flag("-internalize-at-link"))
      expectCommandLineContains(commandLine, .flag("-lto=llvm-full"))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-experimental-hermetic-seal-at-link") {
      $1.expect(.error("-experimental-hermetic-seal-at-link requires -lto=llvm-full or -lto=llvm-thin"))
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-experimental-hermetic-seal-at-link", "-lto=llvm-full", "-enable-library-evolution") {
      $1.expect(.error("Cannot use -experimental-hermetic-seal-at-link with -enable-library-evolution"))
    }
  }

  @Test func abiDescriptorOnlyWhenEnableEvolution() async throws {
    let flagName = "-empty-abi-descriptor"
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift") { driver in
      let jobs = try await driver.planBuild()
      expectJobInvocationMatches(jobs[0], .flag(flagName))
    }
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-enable-library-evolution") { driver in
      let jobs = try await driver.planBuild()
      let command = jobs[0].commandLine
      #expect(!command.contains(.flag(flagName)))
    }
  }

  @Test func moduleSettings() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift") { driver in
      #expect(driver.moduleOutputInfo.output == nil)
      #expect(driver.moduleOutputInfo.name == "foo")
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g") { driver in
      let pathHandle = driver.moduleOutputInfo.output?.outputPath
      #expect(matchTemporary(VirtualPath.lookup(pathHandle!), "foo.swiftmodule"))
      #expect(driver.moduleOutputInfo.name == "foo")
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-module-name", "wibble", "bar.swift", "-g") { driver in
      let pathHandle = driver.moduleOutputInfo.output?.outputPath
      #expect(matchTemporary(VirtualPath.lookup(pathHandle!), "wibble.swiftmodule"))
      #expect(driver.moduleOutputInfo.name == "wibble")
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "-emit-module", "foo.swift", "-module-name", "wibble", "bar.swift") { driver in
      let expectedOutput : ModuleOutputInfo.ModuleOutput = .topLevel(try toPath("wibble.swiftmodule").intern())
      #expect(driver.moduleOutputInfo.output == expectedOutput)
      #expect(driver.moduleOutputInfo.name == "wibble")
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift") { driver in
      #expect(driver.moduleOutputInfo.output == nil)
      #expect(driver.moduleOutputInfo.name == "main")
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so") { driver in
      #expect(driver.moduleOutputInfo.name == "Wibble")
    }

    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so", "-module-name", "Swift") {
        $1.expect(.error("module name \"Swift\" is reserved for the standard library"))
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "some/dir/libFoo.so", "-module-name", "MyModule") { driver in
      let expectedOutput : ModuleOutputInfo.ModuleOutput = .topLevel(try toPath("some/dir/MyModule.swiftmodule").intern())
      #expect(driver.moduleOutputInfo.output == expectedOutput)
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "/", "-module-name", "MyModule") { driver in
      let expectedOutput : ModuleOutputInfo.ModuleOutput = .topLevel(try VirtualPath.intern(path: "/MyModule.swiftmodule"))
      #expect(driver.moduleOutputInfo.output == expectedOutput)
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "../../some/other/dir/libFoo.so", "-module-name", "MyModule") { driver in
      let expectedOutput : ModuleOutputInfo.ModuleOutput = .topLevel(try toPath("../../some/other/dir/MyModule.swiftmodule").intern())
      #expect(driver.moduleOutputInfo.output == expectedOutput)
    }
  }

  @Test func moduleNameFallbacks() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "file.foo.swift")
    try await assertNoDriverDiagnostics(args: "swiftc", ".foo.swift")
    try await assertNoDriverDiagnostics(args: "swiftc", "foo-bar.swift")
  }

  @Test func packageNameFlag() async throws {
    // -package-name com.perf.my-pkg (valid string)
    try await assertNoDriverDiagnostics(args: "swiftc", "file.swift", "bar.swift", "-module-name", "MyModule", "-package-name", "com.perf.my-pkg", "-emit-module", "-emit-module-path", "../../path/to/MyModule.swiftmodule") { driver in
      #expect(driver.packageName == "com.perf.my-pkg")
      let expectedOutput : ModuleOutputInfo.ModuleOutput = .topLevel(try toPath("../../path/to/MyModule.swiftmodule").intern())
      #expect(driver.moduleOutputInfo.output == expectedOutput)
    }

    // -package-name is not passed and file doesn't contain `package` decls; should pass
    try await assertNoDriverDiagnostics(args: "swiftc", "file.swift") { driver in
      #expect(driver.packageName == nil)
      #expect(driver.moduleOutputInfo.name == "file")
    }

    // -package-name 123a!@#$ (valid string)
    try await assertNoDriverDiagnostics(args: "swiftc", "file.swift", "-module-name", "Foo", "-package-name", "123a!@#$") { driver in
      #expect(driver.packageName == "123a!@#$")
    }

    // -package-name input is an empty string
    try await assertDriverDiagnostics(args: "swiftc", "file.swift", "-package-name", "") {
      $1.expect(.error("package-name is empty"))
    }
  }

  @Test func moduleABIName() async throws {
    var driver = try TestDriver(
      args: ["swiftc", "foo.swift", "-module-name", "Mod", "-module-abi-name", "ABIMod"]
    )
    let jobs = try await driver.planBuild()
    let compileJob = try jobs.findJob(.compile)
    #expect(compileJob.commandLine.contains(.flag("-module-abi-name")))
    #expect(compileJob.commandLine.contains(.flag("ABIMod")))
  }

  @Test func allowableClient() async throws {
    var driver = try TestDriver(
      args: ["swiftc", "foo.swift", "-allowable-client", "Foo", "-allowable-client", "Bar"]
    )
    let jobs = try await driver.planBuild()
    let compileJob = try jobs.findJob(.compile)
    #expect(compileJob.commandLine.contains(.flag("-allowable-client")))
    #expect(compileJob.commandLine.contains(.flag("Foo")))
    #expect(compileJob.commandLine.contains(.flag("Bar")))
  }

  @Test func publicModuleName() async throws {
    var driver = try TestDriver(
      args: ["swiftc", "foo.swift", "-public-module-name", "PublicFacing"]
    )
    let jobs = try await driver.planBuild()
    let compileJob = try jobs.findJob(.compile)

    if driver.isFrontendArgSupported(.publicModuleName) {
      #expect(compileJob.commandLine.contains(.flag("-public-module-name")))
      #expect(compileJob.commandLine.contains(.flag("PublicFacing")))
    } else {
      #expect(!compileJob.commandLine.contains(.flag("-public-module-name")))
      #expect(!compileJob.commandLine.contains(.flag("PublicFacing")))
    }
  }

  @Test func moduleNaming() async throws {
    try expectEqual(try TestDriver(args: ["swiftc", "foo.swift"]).moduleOutputInfo.name, "foo")
    try expectEqual(try TestDriver(args: ["swiftc", "foo.swift", "-o", "a.out"]).moduleOutputInfo.name, "a")

    // This is silly, but necessary for compatibility with the integrated driver.
    try expectEqual(try TestDriver(args: ["swiftc", "foo.swift", "-o", "a.out.optimized"]).moduleOutputInfo.name, "main")

    try expectEqual(try TestDriver(args: ["swiftc", "foo.swift", "-o", "a.out.optimized", "-module-name", "bar"]).moduleOutputInfo.name, "bar")
    try expectEqual(try TestDriver(args: ["swiftc", "foo.swift", "-o", "+++.out"]).moduleOutputInfo.name, "main")
    try expectEqual(try TestDriver(args: ["swift"]).moduleOutputInfo.name, "REPL")
    try expectEqual(try TestDriver(args: ["swiftc", "foo.swift", "-emit-library", "-o", "libBaz.dylib"]).moduleOutputInfo.name, "Baz")

    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "", "file.foo.swift"]
    ) {
      $1.expect(.error("module name \"\" is not a valid identifier"))
    }

    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "123", "file.foo.swift"]
    ) {
      $1.expect(.error("module name \"123\" is not a valid identifier"))
    }
  }

  @Test func duplicateName() async throws {
    await assertDiagnostics { diagnosticsEngine, verify in
      _ = try? TestDriver(args: ["swiftc", "-c", "/foo.swift", "/foo.swift"], diagnosticsEngine: diagnosticsEngine)
      verify.expect(.error("filename \"foo.swift\" used twice: '/foo.swift' and '/foo.swift'"))
      verify.expect(.note("filenames are used to distinguish private declarations with the same name"))
    }

    await assertDiagnostics { diagnosticsEngine, verify in
      _ = try? TestDriver(args: ["swiftc", "-c", "/foo.swift", "/foo/foo.swift"], diagnosticsEngine: diagnosticsEngine)
      verify.expect(.error("filename \"foo.swift\" used twice: '/foo.swift' and '/foo/foo.swift'"))
      verify.expect(.note("filenames are used to distinguish private declarations with the same name"))
    }
  }
}
