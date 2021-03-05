//===------- IncrementalImportTestFramework.swift - Swift Testing ---------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
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


// MARK: - SourceProtocol
/// Each test must implement an enum that enumerates the sources in the test
/// Each source is the contents of some source file version

protocol SourceProtocol: TestPartProtocol {

  /// Each source file must supply a `SourceDescription` object, which contains (versions of)
  /// the source code and recompilation expectations if any.
  var code: String {get}

  /// What I replace if an alternate, otherwise should be self
  var original: Self {get}
}

extension SourceProtocol {
  /// The basename without extension of the source file, e.g. for a file named "main.swift", this would be "main"
  var name: String { rawValue }

  func sourcePath(_ context: TestContext) -> AbsolutePath {
    context.testDir.appending(component: "\(original.name).swift")
  }

  func mutate(_ context: TestContext) {
    XCTAssertNoThrow(
      try localFileSystem.writeIfChanged(path: sourcePath(context),
                                         bytes: ByteString(encodingAsUTF8: code)),
      file: context.testFile, line: context.testLine)
  }
}
