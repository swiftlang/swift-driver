//===--------------- SwiftDriverTests.swift - Swift Driver Tests -======---===//
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
import SwiftDriver
import TSCBasic
import TSCUtility

final class SwiftDriverTests: XCTestCase {
    func testParsing() throws {
      // Form an options table
      let options = OptionTable()
      // Parse each kind of option
      let results = try options.parse([
        "input1", "-color-diagnostics", "-Ifoo", "-I", "bar spaces",
        "-I=wibble", "input2", "-module-name", "main",
        "-sanitize=a,b,c", "--", "-foo", "-bar"])
      XCTAssertEqual(results.description,
                     "input1 -color-diagnostics -I foo -I 'bar spaces' -I=wibble input2 -module-name main -sanitize=a,b,c -- -foo -bar")
    }

  func testParseErrors() {
    let options = OptionTable()

    XCTAssertThrowsError(try options.parse(["-unrecognized"])) { error in
      XCTAssertEqual(error as? OptionParseError, .unknownOption(index: 0, argument: "-unrecognized"))
    }

    XCTAssertThrowsError(try options.parse(["-I"])) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 0, argument: "-I"))
    }

    XCTAssertThrowsError(try options.parse(["-color-diagnostics", "-I"])) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 1, argument: "-I"))
    }

    XCTAssertThrowsError(try options.parse(["-module-name"])) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 0, argument: "-module-name"))
    }
  }

  func testDriverKindParsing() throws {
    func assertArgs(
      _ args: String...,
      parseTo driverKind: DriverKind,
      leaving remainingArgs: ArraySlice<String>,
      file: StaticString = #file, line: UInt = #line
    ) throws {
      var slice = args[...]
      let result = try Driver.determineDriverKind(args: &slice)
      
      XCTAssertEqual(result, driverKind, file: file, line: line)
      XCTAssertEqual(slice, remainingArgs, file: file, line: line)
    }
    func assertArgsThrow(
      _ args: String...,
      file: StaticString = #file, line: UInt = #line
    ) throws {
      var slice = args[...]
      XCTAssertThrowsError(try Driver.determineDriverKind(args: &slice))
    }

    try assertArgs("swift", parseTo: .interactive, leaving: [])
    try assertArgs("/path/to/swift", parseTo: .interactive, leaving: [])
    try assertArgs("swiftc", parseTo: .batch, leaving: [])
    try assertArgs(".build/debug/swiftc", parseTo: .batch, leaving: [])
    try assertArgs("swiftc", "-frontend", parseTo: .frontend, leaving: [])
    try assertArgs("swiftc", "-modulewrap", parseTo: .moduleWrap, leaving: [])
    try assertArgs("/path/to/swiftc", "-modulewrap",
                   parseTo: .moduleWrap, leaving: [])

    try assertArgs("swiftc", "--driver-mode=swift", parseTo: .interactive, leaving: [])
    try assertArgs("swiftc", "--driver-mode=swift-autolink-extract", parseTo: .autolinkExtract, leaving: [])
    try assertArgs("swiftc", "--driver-mode=swift-indent", parseTo: .indent, leaving: [])
    try assertArgs("swift", "--driver-mode=swift-autolink-extract", parseTo: .autolinkExtract, leaving: [])
    
    try assertArgs("swift", "-zelda", parseTo: .interactive, leaving: ["-zelda"])
    try assertArgs("/path/to/swiftc", "-modulewrap", "savannah",
                   parseTo: .moduleWrap, leaving: ["savannah"])
    try assertArgs("swiftc", "--driver-mode=swift", "swiftc",
                   parseTo: .interactive, leaving: ["swiftc"])

    try assertArgsThrow("driver")
    try assertArgsThrow("swiftc", "--driver-mode=blah")
    try assertArgsThrow("swiftc", "--driver-mode=")
  }

  func testCompilerMode() throws {
    do {
      let driver1 = try Driver(args: ["swift", "main.swift"])
      XCTAssertEqual(driver1.compilerMode, .immediate)

      let driver2 = try Driver(args: ["swift"])
      XCTAssertEqual(driver2.compilerMode, .repl)
    }

    do {
      let driver1 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization"])
      XCTAssertEqual(driver1.compilerMode, .singleCompile)

      let driver2 = try Driver(args: ["swiftc", "main.swift", "-g"])
      XCTAssertEqual(driver2.compilerMode, .standardCompile)
    }
  }

  func testInputFiles() throws {
    let driver1 = try Driver(args: ["swift", "a.swift", "/tmp/b.swift"])
    XCTAssertEqual(driver1.inputFiles,
                   [ TypedVirtualPath(file: .relative(RelativePath("a.swift")), type: .swift),
                     TypedVirtualPath(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])
    let driver2 = try Driver(args: ["swift", "a.swift", "-working-directory", "/wobble", "/tmp/b.swift"])
    XCTAssertEqual(driver2.inputFiles,
                   [ TypedVirtualPath(file: .absolute(AbsolutePath("/wobble/a.swift")), type: .swift),
                     TypedVirtualPath(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])

    let driver3 = try Driver(args: ["swift", "-"])
    XCTAssertEqual(driver3.inputFiles, [ TypedVirtualPath(file: .standardInput, type: .swift )])

    let driver4 = try Driver(args: ["swift", "-", "-working-directory" , "-wobble"])
    XCTAssertEqual(driver4.inputFiles, [ TypedVirtualPath(file: .standardInput, type: .swift )])
  }

  func testPrimaryOutputKinds() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift", "-emit-module"])
    XCTAssertEqual(driver1.compilerOutputType, .swiftModule)
    XCTAssertEqual(driver1.linkerOutputType, nil)

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver2.compilerOutputType, .object)
    XCTAssertEqual(driver2.linkerOutputType, .dynamicLibrary)

    let driver3 = try Driver(args: ["swiftc", "-static", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver3.compilerOutputType, .object)
    XCTAssertEqual(driver3.linkerOutputType, .staticLibrary)
  }

  func testPrimaryOutputKindsDiagnostics() throws {
      try assertDriverDiagnostics(args: "swift", "-i") {
          $1.expect(.error_i_mode(.interactive))
      }
  }

  func testDebugSettings() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module") { driver in
      XCTAssertNil(driver.debugInfoLevel)
      XCTAssertEqual(driver.debugInfoFormat, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g") { driver in
      XCTAssertEqual(driver.debugInfoLevel, .astTypes)
      XCTAssertEqual(driver.debugInfoFormat, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "-g", "foo.swift", "-gline-tables-only") { driver in
      XCTAssertEqual(driver.debugInfoLevel, .lineTables)
      XCTAssertEqual(driver.debugInfoFormat, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=codeview") { driver in
      XCTAssertEqual(driver.debugInfoLevel, .astTypes)
      XCTAssertEqual(driver.debugInfoFormat, .codeView)
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-debug-info-format=dwarf") {
      $1.expect(.error("option '-debug-info-format=' is missing a required argument (-g)"))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=notdwarf") {
      $1.expect(.error("invalid value 'notdwarf' in '-debug-info-format='"))
    }
    
    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-gdwarf-types", "-debug-info-format=codeview") {
      $1.expect(.error("argument 'codeview' is not allowed with '-gdwarf-types'"))
    }
  }

  func testModuleSettings() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift") { driver in
      XCTAssertNil(driver.moduleOutput)
      XCTAssertEqual(driver.moduleName, "foo")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.auxiliary(VirtualPath.temporary(RelativePath("foo.swiftmodule"))))
      XCTAssertEqual(driver.moduleName, "foo")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-module-name", "wibble", "bar.swift", "-g") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.auxiliary( VirtualPath.temporary(RelativePath("wibble.swiftmodule"))))
      XCTAssertEqual(driver.moduleName, "wibble")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "-emit-module", "foo.swift", "-module-name", "wibble", "bar.swift") { driver in
      XCTAssertEqual(driver.moduleOutput, ModuleOutput.topLevel(try VirtualPath(path: "wibble.swiftmodule")))
      XCTAssertEqual(driver.moduleName, "wibble")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift") { driver in
      XCTAssertNil(driver.moduleOutput)
      XCTAssertEqual(driver.moduleName, "main")
    }
    
    try assertNoDriverDiagnostics(args: "swiftc", "-repl") { driver in
      XCTAssertNil(driver.moduleOutput)
      XCTAssertEqual(driver.moduleName, "REPL")
    }
    
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so") { driver in
      XCTAssertEqual(driver.moduleName, "Wibble")
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so", "-module-name", "Swift") {
      $1.expect(.error_stdlib_module_name(moduleName: "Swift", explicitModuleName: true))
    }
  }
  
  func testModuleNameFallbacks() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "file.foo.swift")
    try assertNoDriverDiagnostics(args: "swiftc", ".foo.swift")
    try assertNoDriverDiagnostics(args: "swiftc", "foo-bar.swift")
  }

  func testStandardCompileJobs() throws {
    var driver1 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-target", "x86_64-apple-macosx10.15"])
    let plannedJobs = try driver1.planBuild()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssertEqual(plannedJobs[0].outputs.count, 1)
    XCTAssertEqual(plannedJobs[0].outputs.first!.file, VirtualPath.temporary(RelativePath("foo.o")))
    XCTAssertEqual(plannedJobs[1].outputs.count, 1)
    XCTAssertEqual(plannedJobs[1].outputs.first!.file, VirtualPath.temporary(RelativePath("bar.o")))
    XCTAssertTrue(plannedJobs[2].tool.name.contains("ld"))
    XCTAssertEqual(plannedJobs[2].outputs.count, 1)
    XCTAssertEqual(plannedJobs[2].outputs.first!.file, VirtualPath.relative(RelativePath("Test")))

    // Forwarding of arguments.
    var driver2 = try Driver(args: ["swiftc", "-color-diagnostics", "foo.swift", "bar.swift", "-working-directory", "/tmp", "-api-diff-data-file", "diff.txt", "-Xfrontend", "-HI", "-no-color-diagnostics", "-target", "powerpc-apple-macosx10.4", "-g"])
    let plannedJobs2 = try driver2.planBuild()
    XCTAssert(plannedJobs2[0].commandLine.contains(Job.ArgTemplate.path(.absolute(try AbsolutePath(validating: "/tmp/diff.txt")))))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-HI")))
    XCTAssert(!plannedJobs2[0].commandLine.contains(.flag("-Xfrontend")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-no-color-diagnostics")))
    XCTAssert(!plannedJobs2[0].commandLine.contains(.flag("-color-diagnostics")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-target")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("powerpc-apple-macosx10.4")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-enable-anonymous-context-mangled-names")))

    var driver3 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-module-name", "Test"])
    let plannedJobs3 = try driver3.planBuild()
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-module-name")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("Test")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-parse-as-library")))
  }

  func testOutputFileMapLoading() throws {
    let contents = """
    {
      "": {
        "swift-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps"
      },
      "/tmp/foo/Sources/foo/foo.swift": {
        "dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d",
        "object": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o",
        "swiftmodule": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo~partial.swiftmodule",
        "swift-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swiftdeps"
      }
    }
    """

    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path) { $0 <<< contents }
        let outputFileMap = try OutputFileMap.load(file: file.path, diagnosticEngine: diags)

        let object = try outputFileMap.getOutput(inputFile: .init(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .object)
        XCTAssertEqual(object.name, "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o")

        let masterDeps = try outputFileMap.getOutput(inputFile: .init(path: ""), outputType: .swiftDeps)
        XCTAssertEqual(masterDeps.name, "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps")
      }
    }
  }

  func testOutputFileMapStoring() throws {
    // Create sample OutputFileMap:

    // Rather than writing VirtualPath(path:...) over and over again, make strings, then fix it
    let stringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps"],
      "foo.swift" : [
        .dependencies: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d",
        .object: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o",
        .swiftModule: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo~partial.swiftmodule",
        .swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swiftdeps"
        ]
    ]
    let pathyEntries = try Dictionary(uniqueKeysWithValues:
      stringyEntries.map { try
        (
          VirtualPath(path: $0.key),
          Dictionary(uniqueKeysWithValues: $0.value.map { try ($0.key, VirtualPath(path: $0.value))})
        )})
    let sampleOutputFileMap = OutputFileMap(entries: pathyEntries)

    try withTemporaryFile { file in
      try sampleOutputFileMap.store(file: file.path, diagnosticEngine: DiagnosticsEngine())
      let contentsForDebugging = try localFileSystem.readFileContents(file.path).cString
      _ = contentsForDebugging
      let recoveredOutputFileMap = try OutputFileMap.load(file: file.path, diagnosticEngine: DiagnosticsEngine())
      XCTAssertEqual(sampleOutputFileMap, recoveredOutputFileMap)
    }
  }

  func testResponseFileExpansion() throws {
    try withTemporaryDirectory { path in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
      try localFileSystem.writeFileContents(fooPath) {
        $0 <<< "hello\nbye\nbye\\ to\\ you\n@\(barPath.pathString)"
      }
      try localFileSystem.writeFileContents(barPath) {
        $0 <<< "from\nbar\n@\(fooPath.pathString)"
      }
      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@" + fooPath.pathString, "something"], diagnosticsEngine: diags)
      XCTAssertEqual(args, ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      XCTAssertEqual(diags.diagnostics.count, 1)
      XCTAssert(diags.diagnostics.first!.description.contains("is recursively expanded"))
    }
  }
  
  /// Tests how response files tokens such as spaces, comments, escaping characters and quotes, get parsed and expanded.
  func testResponseFileTokenization() throws {
    try withTemporaryDirectory { path  in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
      let escapingPath = path.appending(component: "escaping.rsp")
      
      try localFileSystem.writeFileContents(fooPath) {
        $0 <<< #"""
        Command1 --kkc
        //This is a comment
        // this is another comment
        but this is \\\\\a command
        @\#(barPath.pathString)
        @YouAren'tAFile
        """#
      }
      
      try localFileSystem.writeFileContents(barPath) {
        $0 <<< #"""
        swift
        "rocks!"
        compiler
        -Xlinker
        
        @loader_path
        mkdir "Quoted Dir"
        cd Unquoted \\Dir
        // Bye!
        """#
      }
      
      try localFileSystem.writeFileContents(escapingPath) {
        $0 <<< "swift\n--driver-mode=swift\tc\n-v\r\n//comment\n\"the end\""
      }
      let args = try Driver.expandResponseFiles(["@" + fooPath.pathString], diagnosticsEngine: diags)
      XCTAssertEqual(args, [#"Command1 --kkc"#, #"but this is \\a command"#, #"swift"#, #""rocks!""# ,#"compiler"#, #"-Xlinker"#, #"@loader_path"#, #"mkdir "Quoted Dir""#, #"cd Unquoted \Dir"#, #"@YouAren'tAFile"#])
      let escapingArgs = try Driver.expandResponseFiles(["@" + escapingPath.pathString], diagnosticsEngine: diags)
      XCTAssertEqual(escapingArgs, ["swift", "--driver-mode=swiftc", "-v","\"the end\""])
    }
  }
  
  func testLinking() throws {
    let commonArgs = ["swiftc", "foo.swift", "bar.swift",  "-module-name", "Test"]
    do {
      // macOS target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)
      
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dylib")))
      XCTAssertTrue(cmd.contains(.flag("-arch")))
      XCTAssertTrue(cmd.contains(.flag("x86_64")))
      XCTAssertTrue(cmd.contains(.flag("-macosx_version_min")))
      XCTAssertTrue(cmd.contains(.flag("10.15.0")))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // iOS target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "arm64-apple-ios10.0"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dylib")))
      XCTAssertTrue(cmd.contains(.flag("-arch")))
      XCTAssertTrue(cmd.contains(.flag("arm64")))
      XCTAssertTrue(cmd.contains(.flag("-iphoneos_version_min")))
      XCTAssertTrue(cmd.contains(.flag("10.0.0")))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // Xlinker flags
      var driver = try Driver(args: commonArgs + ["-emit-library", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dylib")))
      XCTAssertTrue(cmd.contains(.flag("-w")))
      XCTAssertTrue(cmd.contains(.flag("-L")))
      XCTAssertTrue(cmd.contains(.path(.absolute(AbsolutePath("/tmp")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // static linking
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-static")))
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.a"))

      // The regular Swift driver doesn't pass Xlinker flags to the static
      // linker, so be consistent with this
      XCTAssertFalse(cmd.contains(.flag("-w")))
      XCTAssertFalse(cmd.contains(.flag("-L")))
      XCTAssertFalse(cmd.contains(.path(.absolute(AbsolutePath("/tmp")))))

      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // executable linking
      var driver = try Driver(args: commonArgs + ["-emit-executable", "-target", "x86_64-apple-macosx10.15"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .autolinkExtract })

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "Test"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // linux target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-unknown-linux"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("Test.autolink")))))

      let linkJob = plannedJobs[3]
      XCTAssertEqual(linkJob.kind, .link)
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(cmd.contains(.flag("-shared")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.so"))

      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-static")))
    }

    do {
      // static linux linking
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-target", "x86_64-unknown-linux"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertTrue(autolinkCmd.contains(.path(.temporary(RelativePath("Test.autolink")))))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      // we'd expect "ar crs libTest.a foo.o bar.o"
      XCTAssertTrue(cmd.contains(.flag("crs")))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("foo.o")))))
      XCTAssertTrue(cmd.contains(.path(.temporary(RelativePath("bar.o")))))
      XCTAssertEqual(linkJob.outputs[0].file, try VirtualPath(path: "libTest.a"))

      XCTAssertFalse(cmd.contains(.flag("-o")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }
  }

  func testSanitizerArgs() throws {
  // FIXME: This doesn't work on Linux.
  #if os(macOS)
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-target", "x86_64-apple-macosx",
      "-module-name", "Test"
    ]
    do {
      // address sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=address"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains {
        if case .path(let path) = $0 {
          return path.name.contains("darwin/libclang_rt.asan_osx_dynamic.dylib")
        }
        return false
      })
    }

    do {
      // thread sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=thread"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=thread")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains {
        if case .path(let path) = $0 {
          return path.name.contains("darwin/libclang_rt.tsan_osx_dynamic.dylib")
        }
        return false
      })
    }

    do {
      // undefined behavior sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=undefined"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=undefined")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains {
        if case .path(let path) = $0 {
          return path.name.contains("darwin/libclang_rt.ubsan_osx_dynamic.dylib")
        }
        return false
      })
    }

    // FIXME: This test will fail when run on macOS, because the driver uses
    //        the existence of the runtime support libraries to determine if
    //        a sanitizer is supported. Until we allow cross-compiling with
    //        sanitizers, we'll need to disable this test on macOS
    #if os(Linux)
    do {
      // linux multiple sanitizers
      var driver = try Driver(
        args: commonArgs + [
          "-target", "x86_64-unknown-linux",
          "-sanitize=address", "-sanitize=undefined"
        ]
      )
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=undefined")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=address,undefined")))
    }
    #endif
  #endif
  }

  func testBatchModeCompiles() throws {
    var driver1 = try Driver(args: ["swiftc", "foo1.swift", "bar1.swift", "foo2.swift", "bar2.swift", "foo3.swift", "bar3.swift", "foo4.swift", "bar4.swift", "foo5.swift", "bar5.swift", "wibble.swift", "-module-name", "Test", "-target", "x86_64-apple-macosx10.15", "-enable-batch-mode", "-driver-batch-count", "3"])
    let plannedJobs = try driver1.planBuild()
    XCTAssertEqual(plannedJobs.count, 4)
    XCTAssertEqual(plannedJobs[0].outputs.count, 4)
    XCTAssertEqual(plannedJobs[0].outputs.first!.file, VirtualPath.temporary(RelativePath("foo1.o")))
    XCTAssertEqual(plannedJobs[1].outputs.count, 4)
    XCTAssertEqual(plannedJobs[1].outputs.first!.file, VirtualPath.temporary(RelativePath("foo3.o")))
    XCTAssertEqual(plannedJobs[2].outputs.count, 3)
    XCTAssertEqual(plannedJobs[2].outputs.first!.file, VirtualPath.temporary(RelativePath("foo5.o")))
    XCTAssertTrue(plannedJobs[3].tool.name.contains("ld"))
    XCTAssertEqual(plannedJobs[3].outputs.count, 1)
    XCTAssertEqual(plannedJobs[3].outputs.first!.file, VirtualPath.relative(RelativePath("Test")))
  }

  func testMergeModulesOnly() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module", "-import-objc-header", "TestInputHeader.h", "-emit-dependencies", "-emit-module-doc-path", "/foo/bar/Test.swiftdoc"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs.count, 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .temporary(RelativePath("foo.swiftmodule")))
      XCTAssertEqual(plannedJobs[0].outputs[1].file, .temporary(RelativePath("foo.swiftdoc")))
      XCTAssertEqual(plannedJobs[0].outputs[2].file, .temporary(RelativePath("foo.d")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))

      XCTAssertEqual(plannedJobs[1].outputs.count, 3)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .temporary(RelativePath("bar.swiftmodule")))
      XCTAssertEqual(plannedJobs[1].outputs[1].file, .temporary(RelativePath("bar.swiftdoc")))
      XCTAssertEqual(plannedJobs[1].outputs[2].file, .temporary(RelativePath("bar.d")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-import-objc-header")))

      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .absolute(AbsolutePath("/foo/bar/Test.swiftdoc")))
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("-import-objc-header")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", "/foo/bar/Test.swiftmodule" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, VirtualPath.absolute(AbsolutePath("/foo/bar/Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .absolute(AbsolutePath("/foo/bar/Test.swiftdoc")))
    }

    do {
      // Make sure the swiftdoc path is correct for a relative module
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", "Test.swiftmodule" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .relative(RelativePath("Test.swiftdoc")))
    }

    do {
      // Make sure the swiftdoc path is correct for an inferred module
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-doc", "-emit-module"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 2)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .relative(RelativePath("Test.swiftmodule")))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .relative(RelativePath("Test.swiftdoc")))
    }

  }

  func testTargetTriple() throws {
    let driver1 = try Driver(args: ["swiftc", "-c", "foo.swift", "-module-name", "Foo"])

    let expectedDefaultContents: String
    #if os(macOS)
    expectedDefaultContents = "x86_64-apple-darwin"
    #elseif os(Linux)
    expectedDefaultContents = "-unknown-linux"
    #else
    expectedDefaultContents = "-"
    #endif

    XCTAssert(driver1.targetTriple.triple.contains(expectedDefaultContents),
              "Default triple \(driver1.targetTriple) contains \(expectedDefaultContents)")

    let driver2 = try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-watchos12", "foo.swift", "-module-name", "Foo"])
    XCTAssertEqual(driver2.targetTriple.triple, "x86_64-apple-watchos12")

    let driver3 = try Driver(args: ["swiftc", "-c", "-target", "x86_64-watchos12", "foo.swift", "-module-name", "Foo"])
    XCTAssertEqual(driver3.targetTriple.triple, "x86_64-unknown-watchos12")
  }

  func testDSYMGeneration() throws {
    let commonArgs = [
      "swiftc", "-target", "x86_64-apple-macosx",
      "foo.swift", "bar.swift", "-emit-executable",
      "-module-name", "Test"
    ]

    do {
      // No dSYM generation (no -g)
      var driver = try Driver(args: commonArgs)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .generateDSYM })
    }

    do {
      // No dSYM generation (-gnone)
      var driver = try Driver(args: commonArgs + ["-gnone"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.contains { $0.kind == .generateDSYM })
    }

    do {
      // dSYM generation (-g)
      var driver = try Driver(args: commonArgs + ["-g"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 5)
      let generateDSYMJob = plannedJobs.last!
      XCTAssertEqual(generateDSYMJob.kind, .generateDSYM)

      XCTAssertEqual(generateDSYMJob.outputs.last?.file, try VirtualPath(path: "Test.dSYM"))

      let cmd = generateDSYMJob.commandLine
      XCTAssertTrue(cmd.contains(.path(try VirtualPath(path: "Test"))))
    }
  }

  func testDOTFileEmission() throws {
    var driver = try Driver(args: [
      "swiftc", "-emit-executable", "test.swift", "-emit-module",
      "-target", "x86_64-apple-macosx"
    ])
    let plannedJobs = try driver.planBuild()

    var serializer = DOTJobGraphSerializer(jobs: plannedJobs)
    var output = ""
    serializer.writeDOT(to: &output)

    XCTAssertEqual(output,
    """
    digraph Jobs {
      "compile (swift)" [style=bold];
      "test.swift" [fontsize=12];
      "test.swift" -> "compile (swift)" [color=blue];
      "test.o" [fontsize=12];
      "compile (swift)" -> "test.o" [color=green];
      "test.swiftmodule" [fontsize=12];
      "compile (swift)" -> "test.swiftmodule" [color=green];
      "test.swiftdoc" [fontsize=12];
      "compile (swift)" -> "test.swiftdoc" [color=green];
      "mergeModule (swift)" [style=bold];
      "test.swiftmodule" -> "mergeModule (swift)" [color=blue];
      "mergeModule (swift)" -> "test.swiftmodule" [color=green];
      "mergeModule (swift)" -> "test.swiftdoc" [color=green];
      "link (ld)" [style=bold];
      "test.o" -> "link (ld)" [color=blue];
      "test" [fontsize=12];
      "link (ld)" -> "test" [color=green];
    }

    """)
  }

  func testRegressions() throws {
    // FIXME: This doesn't work on Linux.
  #if os(macOS)
    var driverWithEmptySDK = try Driver(args: ["swiftc", "-sdk", "", "file.swift"])
    _ = try driverWithEmptySDK.planBuild()
  #endif
  }
  
  func testToolchainUtilities() throws {
    // FIXME: This doesn't work on Linux.
  #if os(macOS)
    let swiftVersion = try DarwinToolchain(env: ProcessEnv.vars).swiftCompilerVersion()
    assertString(swiftVersion, contains: "Swift version ")
  #endif
  }
}

func assertString(
  _ haystack: String, contains needle: String, _ message: String = "",
  file: StaticString = #file, line: UInt = #line
) {
  XCTAssertTrue(haystack.contains(needle), """
                \(String(reflecting: needle)) not found in \
                \(String(reflecting: haystack))\
                \(message.isEmpty ? "" : ": " + message)
                """, file: file, line: line)
}
