//===------------- TestProtocol.swift - Swift Testing ---------------------===//
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
/// It uses enumerations for `Step`s, `State`s, `Module`s and `Source`s because the tests must be
/// able to name these, and enum cases give static checkability.
/// (One cannot misspell a name, and using `switch`es, one cannot omit a case.)

/// Each test creates a `struct`, conforming to this protocol.
/// That `struct` must:
/// - Include a type `Step`
/// - Specify the initial state for all the source versions in the test.
/// - Specify the sequence of steps that constitute the test.
///
/// A state is a a collection of compile jobs to be run, where each compile job specifies a module
/// and a set of source versions.
///
/// A step is a state to which the source files will be updated, and the expected files to be recompiled.
protocol TestProtocol {
  associatedtype State: StateProtocol
  typealias Module = State.Module

  init()

  /// The initial state to put the sources in including the initial compile jobs.
  static var start: State {get}

  /// The sequence of states to move to and what is expected when so doing.
  static var steps: [Step<State>] {get}
}

extension TestProtocol {
  /// The top-level function, runs the whole test.
  static func test(verbose: Bool,
                   testFile: StaticString = #file,
                   testLine: UInt = #line
  ) throws {
    for withIncrementalImports in [false, true] { 
      try withTemporaryDirectory { rootDir in
        Self()
          .test(TestContext(in: rootDir,
                            withIncrementalImports: withIncrementalImports,
                            verbose: verbose,
                            testFile: testFile,
                            testLine: testLine))
      }
    }
  }

  /// Run the test with or without incremental imports.
  private func test(_ context: TestContext) {
    XCTAssertNoThrow(
      try localFileSystem.changeCurrentWorkingDirectory(to: context.rootDir),
      file: context.testFile, line: context.testLine)
    createDerivedDataDirs(context)

    Self.start.enterInitialStateAndCheck(context)
    for step in Self.steps {
      step.mutateAndRebuildAndCheck(context)
    }
  }

  private func createDerivedDataDirs(_ context: TestContext) {
    for module in Module.allCases {
      module.createDerivedDataDir(context)
    }
  }
}
