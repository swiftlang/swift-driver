//===------------------- Expectation.swift - Swift Testing ----------------===//
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

/// What is supposed to be recompiled when taking a step.
/// (See `TestProtocol`.)
struct Expectation<Source: SourceProtocol> {

  /// Expected when incremental imports are enabled
  private let withIncrementalImports: [Source]

  // Expected when incremental imports are disabled
  private let withoutIncrementalImports: [Source]

  init(with: [Source], without: [Source]) {
    self.withIncrementalImports = with
    self.withoutIncrementalImports = without
  }

  /// Return the appropriate expectation
  private func when(in context: TestContext) -> [Source] {
    context.withIncrementalImports
      ? withIncrementalImports : withoutIncrementalImports
  }

  /// Check actuals against expectations
  func check(against actuals: [Source], _ context: TestContext, stepName: String) {
    let expected = when(in: context)
    let expectedSet = Set(expected.map {$0.name})
    let actualsSet = Set(actuals.map {$0.name})

    let extraCompilations = actualsSet.subtracting(expectedSet)
    let missingCompilations = expectedSet.subtracting(actualsSet)

    XCTAssertEqual(
      extraCompilations, [],
      "Extra compilations, \(context), step \(stepName)",
      file: context.testFile, line: context.testLine)

    XCTAssertEqual(
      missingCompilations, [],
      "Missing compilations, \(context), step \(stepName)",
      file: context.testFile, line: context.testLine)
  }
}
