//===----------- SourceVersionProtocol.swift - Swift Testing --------------===//
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


// MARK: - SourceVersionProtocol
/// A `SourceVersion` is a particular version of some source file.
/// (See `TestProtocol`.)
protocol SourceVersionProtocol: NameableByRawValue, Hashable {

  /// The source code for this version, i.e. the file contents.
  var code: String {get}

  /// The basename without extension of the corresponding file.
  var fileName: String {get}
}

extension SourceVersionProtocol {

  func path(_ context: TestContext) -> AbsolutePath {
    context.rootDir.appending(component: "\(fileName).swift")
  }

  /// If this version is different from what is in the file, update the file.
  func updateIfChanged(_ context: TestContext) {
    XCTAssertNoThrow(
      try localFileSystem.writeIfChanged(path: path(context),
                                         bytes: ByteString(encodingAsUTF8: code)),
      file: context.testFile, line: context.testLine)
  }
}
