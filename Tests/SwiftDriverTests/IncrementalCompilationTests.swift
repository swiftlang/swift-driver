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

@_spi(Testing) import SwiftDriver

final class IncrementalCompilationTests: XCTestCase {
  func testInputInfoMapReading() throws {
    let inputInfoMap = try! InputInfoMap(contents: Inputs.inputInfoMap)
    XCTAssertEqual(inputInfoMap.swiftVersion,
      "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)")
    XCTAssertEqual(inputInfoMap.argsHash, "abbbfbcaf36b93e58efaadd8271ff142")

    try XCTAssertEqual(inputInfoMap.buildTime,
                       Date(legacyDriverSecsAndNanos: [1570318779, 32358000]))
    try XCTAssertEqual(inputInfoMap.inputInfos,
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
      build_time: [1570318779, 32358000]
      inputs:
        "\(file2)": !dirty [1570318778, 0]
        "\(main)": [1570083660, 0]
        "\(gazorp)": !private [0,0]
      """
    let buildRecord = try InputInfoMap(contents: inputString)
    XCTAssertEqual(buildRecord.swiftVersion, version)
    XCTAssertEqual(buildRecord.argsHash, options)
    XCTAssertEqual(buildRecord.inputInfos.count, 3)
    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath(path: file2 )]!.status,
                   .needsCascadingBuild)
    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath(path: gazorp)]!.status,
                   .needsNonCascadingBuild)
    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath(path: main  )]!.status,
                   .upToDate)

    let outputString = try buildRecord.encode()
    XCTAssertEqual(inputString, outputString)
  }
}
