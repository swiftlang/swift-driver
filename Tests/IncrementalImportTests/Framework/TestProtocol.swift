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

/// A framework for easily adding multi-module tests of the incremental imports
/// It uses enumerations for Modules and Sources because the tests must be
/// able to name particular modules and paths, and enum cases give static checkability.
/// Each test creates a struct, conforming to this protocol, requiring only the line:
/// `fileprivate let paths = Paths<SomeModuleType>`
/// where `SomeModuleType` is an `enum` conforming to `ModuleProtocol`.
protocol TestProtocol {
  associatedtype Step: StepProtocol
  typealias Phase = Step.Phase
  typealias Module = Phase.Module

  init(withIncrementalImports: Bool, testDir: AbsolutePath)
  var withIncrementalImports: Bool {get}
  var testDir: AbsolutePath {get}

  static var start: Phase {get}
  static var steps: [Step] {get}
}

extension TestProtocol {
  /// The top-level function, runs the whole test.
  static func test() throws {
    for withIncrementalImports in [false, true] { 
      try withTemporaryDirectory { tempDir in
        Self(withIncrementalImports: withIncrementalImports,
             testDir: tempDir)
          .test()
      }
    }
  }

  /// Run the test with or without incremental imports.
  private func test() {
    XCTAssertNoThrow(
      try localFileSystem.changeCurrentWorkingDirectory(to: testDir))
    createDerivedDatasAndOFMs()

    Self.start.buildFromScratch(
      in: testDir,
      withIncrementalImports: withIncrementalImports)
    for step in Self.steps {
      step.mutateAndRebuildAndCheck(
        in: testDir,
        withIncrementalImports: withIncrementalImports)
    }
  }
  private func createDerivedDatasAndOFMs() {
    for module in Module.allCases {
      module.createDerivedDataAndOFM(in: testDir)
    }
  }
}
