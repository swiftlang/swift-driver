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
  typealias State = Step.State
  typealias Module = State.Module

  init()

  static var start: State {get}
  static var steps: [Step] {get}
}

extension TestProtocol {
  /// The top-level function, runs the whole test.
  static func test(testFile: StaticString = #file, testLine: UInt = #line) throws {
    for withIncrementalImports in [false, true] { 
      try withTemporaryDirectory { testDir in
        Self()
          .test(TestContext(in: testDir,
                            withIncrementalImports: withIncrementalImports,
                            testFile: testFile,
                            testLine: testLine))
      }
    }
  }

  /// Run the test with or without incremental imports.
  private func test(_ context: TestContext) {
    XCTAssertNoThrow(
      try localFileSystem.changeCurrentWorkingDirectory(to: context.testDir),
      file: context.testFile, line: context.testLine)
    createDerivedDatas(context)

    Self.start.buildFromScratch(context)
    for step in Self.steps {
      step.mutateAndRebuildAndCheck(context)
    }
  }

  private func createDerivedDatas(_ context: TestContext) {
    for module in Module.allCases {
      module.createDerivedData(context)
    }
  }
}
