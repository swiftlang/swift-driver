//===--- IncrementalCompilationInputs.swift - Test Inputs -----------------===//
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


enum Inputs {
  static var buildRecord: String {
    """
        version: "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
        options: "abbbfbcaf36b93e58efaadd8271ff142"
        build_start_time: [1570318779, 32358000]
        build_end_time: [1570318779, 32358010]
        inputs:
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift": !dirty [1570318778, 0]
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift": [1570083660, 0]
          "/Volumes/gazorp.swift": !private [0,0]
    """
  }
  static var buildRecordWithoutOptions: String {
    """
        version: "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
        build_start_time: [1570318779, 32358000]
        build_end_time: [1570318779, 32358010]
        inputs:
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift": !dirty [1570318778, 0]
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift": [1570083660, 0]
          "/Volumes/gazorp.swift": !private [0,0]
    """
  }
}
