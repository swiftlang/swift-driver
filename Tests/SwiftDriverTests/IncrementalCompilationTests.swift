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
     let contents = """
    version: "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
    options: "abbbfbcaf36b93e58efaadd8271ff142"
    build_time: [1570318779, 32358000]
    inputs:
      "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift": !dirty [1570318778, 0]
      "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift": [1570083660, 0]
      "/Volumes/gazorp.swift": !private [0,0]
"""

    let inputInfoMap = try! InputInfoMap(contents: contents)
    //    print(inputInfoMap.buildTime)
    //    inputInfoMap.inputs.forEach {
    //    print($0.key, $0.value)
    //    }
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
}

