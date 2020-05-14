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

import SwiftDriver

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

  func testReadSourceFileDependencyGraph() throws {
    let graph = try SourceFileDependencyGraph(contents: Inputs.fineGrainedSourceFileDependencyGraph)

    graph.verify()

    var found = false
    graph.forEachNode { node in
      guard node.sequenceNumber == 10 else { return }
      found = true
      XCTAssertEqual(node.key.kind, .nominal)
      XCTAssertEqual(node.key.aspect, .interface)
      XCTAssertEqual(node.key.context, "5hello3FooV")
      XCTAssertTrue(node.key.name.isEmpty)
      XCTAssertEqual(node.fingerprint, "8daabb8cdf69d8e8702b4788be12efd6")
      XCTAssertTrue(node.isProvides)

      graph.forEachDefDependedUpon(by: node) { def in
        XCTAssertTrue(def.sequenceNumber == SourceFileDependencyGraph.sourceFileProvidesInterfaceSequenceNumber)
        XCTAssertEqual(def.key.kind, .sourceFileProvide)
        XCTAssertEqual(def.key.aspect, .interface)
        XCTAssertTrue(def.key.context.isEmpty)
        XCTAssertTrue(def.key.name.hasSuffix("/hello.swiftdeps"))
        XCTAssertEqual(def.fingerprint, "85188db3503106210367dbcb7f5d1524")
        XCTAssertTrue(def.isProvides)
      }
    }
    XCTAssertTrue(found)
  }
}

