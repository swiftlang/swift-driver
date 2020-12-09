//===--------------- IncrementalCompilationTests.swift - Swift Testing ----===//
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

@testable import SwiftDriver

final class NonincrementalCompilationTests: XCTestCase {
  func testBuildRecordReading() throws {
    let buildRecord = try! BuildRecord(contents: Inputs.buildRecord)
    XCTAssertEqual(buildRecord.swiftVersion,
                   "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)")
    XCTAssertEqual(buildRecord.argsHash, "abbbfbcaf36b93e58efaadd8271ff142")

    try XCTAssertEqual(buildRecord.buildTime,
                       Date(legacyDriverSecsAndNanos: [1570318779, 32358000]))
    try XCTAssertEqual(buildRecord.inputInfos,
                       [
                        VirtualPath(path: "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift"):
                          InputInfo(status: .needsCascadingBuild,
                                    previousModTime: Date(legacyDriverSecsAndNanos: [1570318778, 0])),
                        VirtualPath(path: "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift"):
                          InputInfo(status: .upToDate,
                                    previousModTime: Date(legacyDriverSecsAndNanos: [1570083660, 0])),
                        VirtualPath(path: "/Volumes/gazorp.swift"):
                          InputInfo(status: .needsNonCascadingBuild,
                                    previousModTime:  Date(legacyDriverSecsAndNanos: [0, 0]))
                       ])
  }

  func testReadBinarySourceFileDependencyGraph() throws {
    let packageRootPath = URL(fileURLWithPath: #file).pathComponents
      .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
    let testInputPath = packageRootPath + "/TestInputs/Incremental/main.swiftdeps"
    let graph = try SourceFileDependencyGraph(pathString: String(testInputPath))
    XCTAssertEqual(graph.majorVersion, 1)
    XCTAssertEqual(graph.minorVersion, 0)
    XCTAssertEqual(graph.compilerVersionString, "Swift version 5.3-dev (LLVM f516ac602c, Swift c39f31febd)")
    graph.verify()
    var saw0 = false
    var saw1 = false
    var saw2 = false
    graph.forEachNode { node in
      switch (node.sequenceNumber, node.key.designator) {
      case let (0, .sourceFileProvide(name: name)):
        saw0 = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(name, "main.swiftdeps")
        XCTAssertEqual(node.fingerprint, "ec443bb982c3a06a433bdd47b85eeba2")
        XCTAssertEqual(node.defsIDependUpon, [2])
        XCTAssertTrue(node.isProvides)
      case let (1, .sourceFileProvide(name: name)):
        saw1 = true
        XCTAssertEqual(node.key.aspect, .implementation)
        XCTAssertEqual(name, "main.swiftdeps")
        XCTAssertEqual(node.fingerprint, "ec443bb982c3a06a433bdd47b85eeba2")
        XCTAssertEqual(node.defsIDependUpon, [])
        XCTAssertTrue(node.isProvides)
      case let (2, .topLevel(name: name)):
        saw2 = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(name, "a")
        XCTAssertNil(node.fingerprint)
        XCTAssertEqual(node.defsIDependUpon, [])
        XCTAssertFalse(node.isProvides)
      default:
        XCTFail()
      }
    }
    XCTAssertTrue(saw0)
    XCTAssertTrue(saw1)
    XCTAssertTrue(saw2)
  }

  func testReadComplexSourceFileDependencyGraph() throws {
    let packageRootPath = URL(fileURLWithPath: #file).pathComponents
      .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
    let testInputPath = packageRootPath + "/TestInputs/Incremental/hello.swiftdeps"
    let graph = try SourceFileDependencyGraph(pathString: String(testInputPath))
    XCTAssertEqual(graph.majorVersion, 1)
    XCTAssertEqual(graph.minorVersion, 0)
    XCTAssertEqual(graph.compilerVersionString, "Swift version 5.3-dev (LLVM 4510748e505acd4, Swift 9f07d884c97eaf4)")
    graph.verify()

    // Check that a node chosen at random appears as expected.
    var foundNode = false
    graph.forEachNode { node in
      if case let .member(context: context, name: name) = node.key.designator,
         node.sequenceNumber == 25
      {
        XCTAssertFalse(foundNode)
        foundNode = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(context, "5hello1BV")
        XCTAssertEqual(name, "init")
        XCTAssertEqual(node.defsIDependUpon, [])
        XCTAssertFalse(node.isProvides)
      }
    }
    XCTAssertTrue(foundNode)
    
    // Check that an edge chosen at random appears as expected.
    var foundEdge = false
    graph.forEachArc { defNode, useNode in
      if defNode.sequenceNumber == 0 && useNode.sequenceNumber == 10 {
        switch (defNode.key.designator, useNode.key.designator) {
        case let (.sourceFileProvide(name: defName),
                  .potentialMember(context: useContext)):
          XCTAssertFalse(foundEdge)
          foundEdge = true

          XCTAssertEqual(defName, "/Users/owenvoorhees/Desktop/hello.swiftdeps")
          XCTAssertEqual(defNode.fingerprint, "38b457b424090ac2e595be0e5f7e3b5b")

          XCTAssertEqual(useContext, "5hello1AC")
          XCTAssertEqual(useNode.fingerprint, "b83bbc0b4b0432dbfabff6556a3a901f")

        default:
          XCTFail()
        }
      }
    }
    XCTAssertTrue(foundEdge)
  }

  func testExtractSourceFileDependencyGraphFromSwiftModule() throws {
    let packageRootPath = URL(fileURLWithPath: #file).pathComponents
      .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
    let testInputPath = packageRootPath + "/TestInputs/Incremental/hello.swiftmodule"
    let data = try Data(contentsOf: URL(fileURLWithPath: String(testInputPath)))
    let graph = try SourceFileDependencyGraph(data: data, fromSwiftModule: true)
    XCTAssertEqual(graph.majorVersion, 1)
    XCTAssertEqual(graph.minorVersion, 0)
    XCTAssertEqual(graph.compilerVersionString, "Apple Swift version 5.3-dev (LLVM 240312aa7333e90, Swift 15bf0478ad7c47c)")
    graph.verify()

    // Check that a node chosen at random appears as expected.
    var foundNode = false
    graph.forEachNode { node in
      if case .nominal(context: "5hello3FooV") = node.key.designator,
         node.sequenceNumber == 4
      {
        XCTAssertFalse(foundNode)
        foundNode = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(node.defsIDependUpon, [0])
        XCTAssertTrue(node.isProvides)
      }
    }
    XCTAssertTrue(foundNode)
  }

  func testDateConversion() {
    let sn =  [0, 8000]
    let d = try! Date(legacyDriverSecsAndNanos: sn)
    XCTAssert(isCloseEnough(d.legacyDriverSecsAndNanos, sn))
  }
  func testReadAndWriteBuildRecord() throws {
    let version = "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
    let options = "abbbfbcaf36b93e58efaadd8271ff142"
    let file2 = "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift"
    let main = "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift"
    let gazorp = "/Volumes/gazorp.swift"
    let inputString =
      """
      version: "\(version)"
      options: "\(options)"
      build_time: [1570318779, 32357931]
      inputs:
        "\(file2)": !dirty [1570318778, 0]
        "\(main)": [1570083660, 0]
        "\(gazorp)": !private [0, 0]

      """
    let buildRecord = try BuildRecord(contents: inputString)
    XCTAssertEqual(buildRecord.swiftVersion, version)
    XCTAssertEqual(buildRecord.argsHash, options)
    XCTAssertEqual(buildRecord.inputInfos.count, 3)
    XCTAssert(isCloseEnough(buildRecord.buildTime.legacyDriverSecsAndNanos,
                            [1570318779, 32357931]))

    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath(path: file2 )]!.status,
                   .needsCascadingBuild)
    XCTAssert(try! isCloseEnough(
                XCTUnwrap(buildRecord.inputInfos[VirtualPath(path: file2 )])
                  .previousModTime.legacyDriverSecsAndNanos,
                [1570318778, 0]))
    XCTAssertEqual(try! XCTUnwrap(buildRecord.inputInfos[VirtualPath(path: gazorp)]).status,
                   .needsNonCascadingBuild)
    XCTAssertEqual(try! XCTUnwrap(buildRecord.inputInfos[VirtualPath(path: gazorp)])
                    .previousModTime.legacyDriverSecsAndNanos,
                   [0, 0])
    XCTAssertEqual(try! XCTUnwrap(buildRecord.inputInfos[VirtualPath(path: main  )]).status,
                   .upToDate)
    XCTAssert(try! isCloseEnough( XCTUnwrap(buildRecord.inputInfos[VirtualPath(path: main  )])
                                    .previousModTime.legacyDriverSecsAndNanos,
                                  [1570083660, 0]))

    let outputString = try buildRecord.encode()
    XCTAssertEqual(inputString, outputString)
  }
  /// The date conversions are not exact
  func isCloseEnough(_ a: [Int], _ b: [Int]) -> Bool {
    a[0] == b[0] && abs(a[1] - b[1]) <= 100
  }


  /// Run a test with two files, main and other.swift, passing on the additional arguments
  /// expecting certain diagnostics.
  private func runDriver(
    with otherArgs: [String],
    expecting expectations: [Diagnostic.Message],
    alsoExpectingWhenAutolinking autolinkExpectations: [Diagnostic.Message] = []
  ) throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "let foo = 1"
      }
      let other = path.appending(component: "other.swift")
      try localFileSystem.writeFileContents(other) {
        $0 <<< "let bar = 2"
      }
      try assertDriverDiagnostics(args: [
        "swiftc", "-module-name", "theModule",
        main.pathString, other.pathString
      ] + otherArgs) {driver, verifier in
        verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)

        expectations.forEach {verifier.expect($0)}
        if driver.isAutolinkExtractJobNeeded {
          autolinkExpectations.forEach {verifier.expect($0)}
        }

        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }
    }
  }

  func testShowJobLifecycleAndIncremental() throws {
    // Legacy MacOS driver output:
    //    Adding standard job to task queue: {compile: main.o <= main.swift}
    //    Added to TaskQueue: {compile: main.o <= main.swift}
    //    Adding standard job to task queue: {compile: other.o <= other.swift}
    //    Added to TaskQueue: {compile: other.o <= other.swift}
    //    Job finished: {compile: main.o <= main.swift}
    //    Job finished: {compile: other.o <= other.swift}

    try runDriver( with: [
      "-c",
      "-driver-show-job-lifecycle",
      "-driver-show-incremental",
    ],
    expecting: [
      .remark("Starting Compiling main.swift"),
      .remark("Finished Compiling main.swift"),
      .remark("Starting Compiling other.swift"),
      .remark("Finished Compiling other.swift"),
    ],
    alsoExpectingWhenAutolinking: [
      .remark("Starting Extracting autolink information for module theModule"),
      .remark("Finished Extracting autolink information for module theModule"),
    ])

  }
  func testNoIncremental() throws {
    try runDriver( with: [
      "-c",
      "-incremental",
    ],
    expecting: [
      .warning("ignoring -incremental (currently requires an output file map)")
    ])
    // Legacy driver output:
    //    <unknown>:0: warning: ignoring -incremental (currently requires an output file map)
  }
}


final class IncrementalCompilationTests: XCTestCase {

  var tempDir: AbsolutePath = AbsolutePath("/tmp")

  let module = "theModule"
  var OFM: AbsolutePath {
    tempDir.appending(component: "OFM.json")
  }
  let baseNamesAndContents = [
    "main": "let foo = 1",
    "other": "let bar = foo"
  ]
  var inputPathsAndContents: [(AbsolutePath, String)] {
    baseNamesAndContents.map {
      (tempDir.appending(component: $0.key + ".swift"), $0.value)
    }
  }
  var derivedDataPath: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }
  var masterSwiftDepsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-master.swiftdeps")
  }
  var autolinkIncrementalExpectations: [String] {
    [
      "Incremental compilation: Queuing Extracting autolink information for module \(module)",
    ]
  }
  var autolinkLifecycleExpectations: [String] {
    [
      "Starting Extracting autolink information for module \(module)",
      "Finished Extracting autolink information for module \(module)",
    ]
  }
  var args: [String] {
    [
      "swiftc",
      "-module-name", module,
      "-o", derivedDataPath.appending(component: module + ".o").pathString,
      "-output-file-map", OFM.pathString,
      "-driver-show-incremental",
      "-driver-show-job-lifecycle",
      "-enable-batch-mode",
      //        "-v",
      "-save-temps",
      "-incremental",
    ]
    + inputPathsAndContents.map {$0.0.pathString} .sorted()
  }
  deinit {
    try? localFileSystem.removeFileTree(tempDir)
  }

  override func setUp() {
    self.tempDir = try! withTemporaryDirectory(removeTreeOnDeinit: false) {$0}
    try! localFileSystem.createDirectory(derivedDataPath)
    writeOutputFileMapData(module: module,
                           inputPaths: inputPathsAndContents.map {$0.0},
                           derivedData: derivedDataPath,
                           to: OFM)
    for (base, contents) in baseNamesAndContents {
      let filePath = tempDir.appending(component: "\(base).swift")
      try! localFileSystem.writeFileContents(filePath) {
        $0 <<< contents
      }
    }
  }

  // FIXME: why does it fail on Linux in CI?
  func testIncrementalDiagnostics() throws {
    #if !os(Linux)
    try testIncremental(checkDiagnostics: true)
    #endif
  }

  func testIncremental() throws {
    try testIncremental(checkDiagnostics: false)
  }

  /// Ensure that the mod date of the input comes back exactly the same via the build-record.
  /// Otherwise the up-to-date calculation in `IncrementalCompilationState` will fail.
  func testBuildRecordDateAccuracy() throws {
    tryInitial(false)
    (1...10).forEach { n in
      tryNoChange(true)
    }
  }



  func testIncremental(checkDiagnostics: Bool) throws {
    tryInitial(checkDiagnostics)
    #if true // sometimes want to skip for debugging
    tryNoChange(checkDiagnostics)
    tryTouchingOther(checkDiagnostics)
    tryTouchingBoth(checkDiagnostics)
    #endif
    tryReplacingMain(checkDiagnostics)
  }


  func tryInitial(_ checkDiagnostics: Bool) {
    try! doABuild(
      "initial",
      checkDiagnostics: checkDiagnostics,
      expectingRemarks: [
        // Leave off the part after the colon because it varies on Linux:
        // MacOS: The operation could not be completed. (TSCBasic.FileSystemError error 3.).
        // Linux: The operation couldn’t be completed. (TSCBasic.FileSystemError error 3.)
        "Disabling incremental build: could not read build record at",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }
  func tryNoChange(_ checkDiagnostics: Bool) {
    try! doABuild(
      "no-change",
      checkDiagnostics: checkDiagnostics,
      expectingRemarks: [
        "Incremental compilation: May skip current input: {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input: {compile: other.o <= other.swift}",
        "Incremental compilation: Skipping input: {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping input: {compile: other.o <= other.swift}",
      ],
      whenAutolinking: [])
  }
  func tryTouchingOther(_ checkDiagnostics: Bool) {
    touch("other")
    try! doABuild(
      "non-propagating",
      checkDiagnostics: checkDiagnostics,
      expectingRemarks: [
        "Incremental compilation: May skip current input: {compile: main.o <= main.swift}",
        "Incremental compilation: Scheduing changed input {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial): {compile: other.o <= other.swift}",
        "Incremental compilation: not scheduling dependents of other.swift; unknown changes",
        "Incremental compilation: Skipping input: {compile: main.o <= main.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 1 constituents: other.swift",
        "Incremental compilation: Queuing Compiling other.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
    ],
    whenAutolinking: autolinkLifecycleExpectations)
  }
  func tryTouchingBoth(_ checkDiagnostics: Bool) {
    touch("main")
    touch("other")
    try! doABuild(
      "non-propagating, both touched",
      checkDiagnostics: checkDiagnostics,
      expectingRemarks: [
        "Incremental compilation: Scheduing changed input {compile: main.o <= main.swift}",
        "Incremental compilation: Scheduing changed input {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial): {compile: main.o <= main.swift}",
        "Incremental compilation: Queuing (initial): {compile: other.o <= other.swift}",
        "Incremental compilation: not scheduling dependents of main.swift; unknown changes",
        "Incremental compilation: not scheduling dependents of other.swift; unknown changes",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Incremental compilation: Queuing Compiling main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
    ],
    whenAutolinking: autolinkLifecycleExpectations)
  }

  func tryReplacingMain(_ checkDiagnostics: Bool) {
    replace(contentsOf: "main", with: "let foo = \"hello\"")
    try! doABuild(
      "propagating into 2nd wave",
      checkDiagnostics: checkDiagnostics,
      expectingRemarks: [
        "Incremental compilation: Scheduing changed input {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input: {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial): {compile: main.o <= main.swift}",
        "Incremental compilation: not scheduling dependents of main.swift; unknown changes",
        "Incremental compilation: Skipping input: {compile: other.o <= other.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Forming batch job from 1 constituents: main.swift",
        "Incremental compilation: Queuing Compiling main.swift",
        "Starting Compiling main.swift",
        "Incremental compilation: Traced: interface of main.swiftdeps from: main.swift -> interface of top-level name foo from: main.swift -> implementation of other.swiftdeps from: other.swift",
        "Incremental compilation: Queuing because of dependencies discovered later: {compile: other.o <= other.swift}",
        "Incremental compilation: Scheduling discovered {compile: other.o <= other.swift}",
        "Finished Compiling main.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }

  func touch(_ name: String) {
    print("*** touching \(name) ***", to: &stderrStream); stderrStream.flush()
    let (path, contents) = try! XCTUnwrap(inputPathsAndContents.filter {$0.0.pathString.contains(name)}.first)
    try! localFileSystem.writeFileContents(path) { $0 <<< contents }
  }

  private func replace(contentsOf name: String, with replacement: String ) {
    print("*** replacing \(name) ***", to: &stderrStream); stderrStream.flush()
    let path = try! XCTUnwrap(inputPathsAndContents.filter {$0.0.pathString.contains("/" + name + ".swift")}.first).0
    let previousContents = try! localFileSystem.readFileContents(path).cString
    try! localFileSystem.writeFileContents(path) { $0 <<< replacement }
    let newContents = try! localFileSystem.readFileContents(path).cString
    XCTAssert(previousContents != newContents, "\(path.pathString) unchanged after write")
    XCTAssert(replacement == newContents, "\(path.pathString) failed to write")
  }
  func doABuild(_ message: String,
                checkDiagnostics: Bool,
                expectingRemarks texts: [String],
                whenAutolinking: [String]) throws {
    try doABuild(
      message,
      checkDiagnostics: checkDiagnostics,
      expecting: texts.map {.remark($0)},
      expectingWhenAutolinking: whenAutolinking.map {.remark($0)})
  }

  func doABuild(_ message: String,
                checkDiagnostics: Bool,
                expecting expectations: [Diagnostic.Message],
                expectingWhenAutolinking autolinkExpectations: [Diagnostic.Message]) throws {
    print("*** starting build \(message) ***", to: &stderrStream); stderrStream.flush()

    func doIt(_ driver: inout Driver) {
      let jobs = try! driver.planBuild()
      try? driver.run(jobs: jobs)
    }

    if checkDiagnostics {
      try assertDriverDiagnostics(args: args) {driver, verifier in
        verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)
        expectations.forEach {verifier.expect($0)}
        if driver.isAutolinkExtractJobNeeded {
          autolinkExpectations.forEach {verifier.expect($0)}
        }
        doIt(&driver)
      }
    }
    else {
      let diagnosticEngine = DiagnosticsEngine(handlers: [
        {print($0, to: &stderrStream); stderrStream.flush()}
      ])
      var driver = try Driver(args: args, env: ProcessEnv.vars,
                              diagnosticsEngine: diagnosticEngine,
                              fileSystem: localFileSystem)
      doIt(&driver)
    }
    print("", to: &stderrStream); stderrStream.flush()
  }

  /// Ensure that autolink output file goes with .o directory, to not prevent incremental omission of
  /// autolink job.
  /// Much of the code below is taking from testLinking(), but uses the output file map code here.
  func testAutolinkOutputPath() {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    env["SWIFT_DRIVER_DSYMUTIL_EXEC"] = "/garbage/dsymutil"

    var driver = try! Driver(
      args: args
        + ["-emit-library", "-target", "x86_64-unknown-linux"],
      env: env)
    let plannedJobs = try! driver.planBuild()
    let autolinkExtractJob = try! XCTUnwrap(
      plannedJobs
        .filter { $0.kind == .autolinkExtract }
        .first)
    let autoOuts = autolinkExtractJob.outputs.filter {$0.type == .autolink}
    XCTAssertEqual(autoOuts.count, 1)
    let autoOut = autoOuts[0]
    let expected = AbsolutePath(derivedDataPath, "\(module).autolink")
    XCTAssertEqual(autoOut.file.absolutePath, expected)
  }

  private func generateOutputFileMapDict(module: String, inputPaths: [AbsolutePath],
                                         derivedData: AbsolutePath
  ) -> [String: [String: String]] {
    let master = ["swift-dependencies": "\(derivedData.pathString)/\(module)-master.swiftdeps"]
    func baseNameEntry(_ s: AbsolutePath) -> [String: String] {
      [
        "dependencies": ".d",
        "diagnostics": ".dia",
        "llvm-bc": ".bc",
        "object": ".o",
        "swift-dependencies": ".swiftdeps",
        "swiftmodule": "-partial.swiftmodule"
      ]
      .mapValues {"\(derivedData.appending(component: s.basenameWithoutExt))\($0)"}
    }
    return Dictionary( uniqueKeysWithValues:
                        inputPaths.map { ("\($0)", baseNameEntry($0)) }
    )
    .merging(["": master]) {_, _ in fatalError()}
  }

  private func generateOutputFileMapData(module: String,
                                         inputPaths: [AbsolutePath],
                                         derivedData: AbsolutePath
  ) -> Data {
    let d: [String: [String: String]] = generateOutputFileMapDict(
      module: module,
      inputPaths: inputPaths,
      derivedData: derivedData)
    let enc = JSONEncoder()
    return try! enc.encode(d)
  }

  private func writeOutputFileMapData(module: String,
                                      inputPaths: [AbsolutePath],
                                      derivedData: AbsolutePath,
                                      to dst: AbsolutePath) {
    let d: Data = generateOutputFileMapData(module: module, inputPaths: inputPaths,
                                            derivedData: derivedData)
    try! localFileSystem.writeFileContents(dst, bytes: ByteString(d))
  }
}
