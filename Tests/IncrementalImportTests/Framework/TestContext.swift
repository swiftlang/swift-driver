//===-------------- TestContext.swift - Swift Testing ----------- ---------===//
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
import TSCBasic

/// Bundles up (incidental) values to be passed down to the various functions.
/// (See `TestProtocol`.)
struct TestContext: CustomStringConvertible {
  /// The root directory of the test; temporary
  let rootDir: AbsolutePath

  /// Are incremental imports enabled? Tests both ways.
  let withIncrementalImports: Bool

  /// The original locus of the test, for error-reporting.
  let testFile: StaticString
  let testLine: UInt

  init(in rootDir: AbsolutePath,
       withIncrementalImports: Bool,
       testFile: StaticString,
       testLine: UInt) {
    self.rootDir = rootDir
    self.withIncrementalImports = withIncrementalImports
    self.testFile = testFile
    self.testLine = testLine
  }

  var description: String {
    "\(withIncrementalImports ? "with" : "without") incremental imports"
  }
}
