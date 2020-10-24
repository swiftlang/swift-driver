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

@_spi(Testing) import SwiftDriver

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
    let data = try Data(contentsOf: URL(fileURLWithPath: String(testInputPath)))
    let graph = try SourceFileDependencyGraph(data: data)
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
    XCTAssert(try! isCloseEnough(buildRecord.inputInfos[VirtualPath(path: file2 )]!
                                  .previousModTime.legacyDriverSecsAndNanos,
                                 [1570318778, 0]))
    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath(path: gazorp)]!.status,
                   .needsNonCascadingBuild)
    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath(path: gazorp)]!
                    .previousModTime.legacyDriverSecsAndNanos,
                   [0, 0])
    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath(path: main  )]!.status,
                   .upToDate)
    XCTAssert(try! isCloseEnough( buildRecord.inputInfos[VirtualPath(path: main  )]!
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


  func testIncremental() throws {
    try withTemporaryDirectory { path in
      let module = "theModule"
      let OFM = path.appending(component: "OFM.json")
      let baseNamesAndContents = [
        "main": "let foo = 1",
        "other": "let bar = foo"
      ]
      let inputPathsAndContents = baseNamesAndContents.map {
        (path.appending(component: $0.key + ".swift"), $0.value)
      }
      let derivedDataPath = path.appending(component: "derivedData")
      try! localFileSystem.createDirectory(derivedDataPath)
      writeOutputFileMapData(module: module,
                             inputPaths: inputPathsAndContents.map {$0.0},
                             derivedData: derivedDataPath,
                             to: OFM)
      for (base, contents) in baseNamesAndContents {
        let filePath = path.appending(component: "\(base).swift")
        try localFileSystem.writeFileContents(filePath) {
          $0 <<< contents
        }
      }
      let args: [String] = [
        "swiftc",
        "module-name", module,
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

      let autolinkExpectations = [
        "Starting Extracting autolink information for module theModule",
        "Finished Extracting autolink information for module theModule",
      ]
      .map (Diagnostic.Message.remark)

      func doABuild(_ message: String, expecting expectations: [Diagnostic.Message]) throws {
        print("*** starting build \(message) ***")
        try assertDriverDiagnostics(args: args) {driver, verifier in
          verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)
          expectations.forEach {verifier.expect($0)}
          if driver.isAutolinkExtractJobNeeded {
            autolinkExpectations.forEach {verifier.expect($0)}
          }
          let jobs = try! driver.planBuild()
          try? driver.run(jobs: jobs)
        }
        print("")
      }
      func doABuild(_ message: String, expectingRemarks texts: [String]) throws {
        try doABuild(message, expecting: texts.map {.remark($0)} )
      }
      func touch(_ name: String) {
        print("*** touching \(name) ***")
        let (path, contents) = inputPathsAndContents.filter {$0.0.pathString.contains(name)}.first!
        try! localFileSystem.writeFileContents(path) { $0 <<< contents }
      }
      func replace(contentsOf name: String, with replacement: String ) {
        print("*** replacing \(name) ***")
        let path = inputPathsAndContents.filter {$0.0.pathString.contains(name)}.first!.0
        try! localFileSystem.writeFileContents(path) { $0 <<< replacement }
      }
      let masterSwiftDepsPath = derivedDataPath.appending(component: "theModule-master.swiftdeps")

      try! doABuild("initial", expectingRemarks: [
        // Leave off the part after the colon because it varies on Linux:
        // MacOS: The operation could not be completed. (TSCBasic.FileSystemError error 3.).
        // Linux: The operation couldn’t be completed. (TSCBasic.FileSystemError error 3.)
        "Incremental compilation has been disabled, because incremental compilation could not read build record at \(masterSwiftDepsPath)",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ]
      )
      #if true
      try! doABuild("no-change", expectingRemarks: [
        "Incremental compilation: Skipping current {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping current {compile: other.o <= other.swift}",
        "Incremental compilation: Skipping: {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping: {compile: other.o <= other.swift}",
        "Incremental compilation: Skipping {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping {compile: other.o <= other.swift}",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ])
      touch("other")
      try! doABuild("non-propagating", expectingRemarks: [
        "Incremental compilation: Skipping current {compile: main.o <= main.swift}",
        "Incremental compilation: Scheduing changed input {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial): {compile: other.o <= other.swift}",
        "Incremental compilation: not scheduling dependents of other.swift; unknown changes",
        "Incremental compilation: Skipping: {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping {compile: main.o <= main.swift}",
        "Queueing Compiling other.swift",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 1 constituents: other.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ])
      #endif
      replace(contentsOf: "main", with: "let foo = \"hello\"")
      try! doABuild("propagating into 2nd wave", expectingRemarks: [
        "Incremental compilation: Scheduing changed input {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping current {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial): {compile: main.o <= main.swift}",
        "Incremental compilation: not scheduling dependents of main.swift; unknown changes",
        "Incremental compilation: Skipping: {compile: other.o <= other.swift}",
        "Incremental compilation: Skipping {compile: other.o <= other.swift}",
        "Queueing Compiling main.swift",
        "Scheduling discovered {compile: other.o <= other.swift}",
        "Queueing Compiling other.swift",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Forming batch job from 1 constituents: main.swift",
        "Starting Compiling main.swift",
        "Finished Compiling main.swift",
        "Incremental compilation: Traced: interface of main.swiftdeps -> interface of top-level name foo -> implementation of other.swiftdeps",
        "Incremental compilation: Queuing because of dependencies discovered later: {compile: other.o <= other.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 1 constituents: other.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
     ])
    }
  }
}
