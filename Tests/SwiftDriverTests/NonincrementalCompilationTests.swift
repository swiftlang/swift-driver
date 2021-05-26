//===------------ NonincrementalCompilationTests.swift - Swift Testing ----===//
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
import SwiftOptions
import TestUtilities


/// Testing the machinery for incremental compilation with nonincremental test cases.
final class NonincrementalCompilationTests: XCTestCase {
  func testBuildRecordReading() throws {
    let buildRecord = try XCTUnwrap(
      BuildRecord(contents: Inputs.buildRecord,
                                  failedToReadOutOfDateMap: {XCTFail($0 ?? "Failed to read map")}))
    XCTAssertEqual(buildRecord.swiftVersion,
                   "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)")
    XCTAssertEqual(buildRecord.argsHash, "abbbfbcaf36b93e58efaadd8271ff142")

    try XCTAssertEqual(buildRecord.buildStartTime,
                       Date(legacyDriverSecsAndNanos: [1570318779, 32358000]))
    try XCTAssertEqual(buildRecord.buildEndTime,
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

  func testBuildRecordWithoutOptionsReading() throws {
    let buildRecord = try XCTUnwrap(
      BuildRecord(
        contents: Inputs.buildRecordWithoutOptions,
        failedToReadOutOfDateMap: {XCTFail($0 ?? "Failed to read map")}))
    XCTAssertEqual(buildRecord.swiftVersion,
                   "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)")
    XCTAssertEqual(buildRecord.argsHash, nil)

    try XCTAssertEqual(buildRecord.buildStartTime,
                       Date(legacyDriverSecsAndNanos: [1570318779, 32358000]))
    try XCTAssertEqual(buildRecord.buildEndTime,
                       Date(legacyDriverSecsAndNanos: [1570318779, 32358010]))
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
    let absolutePath = try XCTUnwrap(Fixture.fixturePath(at: RelativePath("Incremental"),
                                                         for: "main.swiftdeps"))
    let dependencySource = DependencySource(VirtualPath.absolute(absolutePath).intern())!
    let graph = try XCTUnwrap(
      try SourceFileDependencyGraph(
        contentsOf: dependencySource,
        on: localFileSystem))
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
    let absolutePath = try XCTUnwrap(Fixture.fixturePath(at: RelativePath("Incremental"),
                                                         for: "hello.swiftdeps"))
    let graph = try XCTUnwrap(
      try SourceFileDependencyGraph(
        contentsOf: DependencySource(VirtualPath.absolute(absolutePath).intern())!,
        on: localFileSystem))
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
    let absolutePath = try XCTUnwrap(Fixture.fixturePath(at: RelativePath("Incremental"),
                                                         for: "hello.swiftmodule"))
    let data = try localFileSystem.readFileContents(absolutePath)
    let graph = try XCTUnwrap(
      try SourceFileDependencyGraph(data: data,
                                    from: DependencySource(VirtualPath.absolute(absolutePath).intern())!,
                                    fromSwiftModule: true))
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
      build_start_time: [1570318779, 32357931]
      build_end_time: [1580318779, 33357858]
      inputs:
        "\(file2)": !dirty [1570318778, 0]
        "\(main)": [1570083660, 0]
        "\(gazorp)": !private [0, 0]

      """
    let buildRecord = try XCTUnwrap (BuildRecord(contents: inputString, failedToReadOutOfDateMap: {_ in}))
    XCTAssertEqual(buildRecord.swiftVersion, version)
    XCTAssertEqual(buildRecord.argsHash, options)
    XCTAssertEqual(buildRecord.inputInfos.count, 3)
    XCTAssert(isCloseEnough(buildRecord.buildStartTime.legacyDriverSecsAndNanos,
                            [1570318779, 32357931]))
    XCTAssert(isCloseEnough(buildRecord.buildEndTime.legacyDriverSecsAndNanos,
                            [1580318779, 33357941]))

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
    XCTAssert(try! isCloseEnough(XCTUnwrap(buildRecord.inputInfos[VirtualPath(path: main  )])
                                   .previousModTime.legacyDriverSecsAndNanos,
                                 [1570083660, 0]))

    let outputString = try XCTUnwrap (buildRecord.encode(currentArgsHash: options,
                                                         diagnosticEngine: DiagnosticsEngine()))
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
        "swiftc", "-module-name", "theModule", "-working-directory", path.pathString,
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
