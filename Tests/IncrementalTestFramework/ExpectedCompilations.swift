//===-------------- ExpectedCompilations.swift - Swift Testing -------------===//
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

/// The `Source`s expected to be compiled in a `Step`, when incremental imports are either enabled or disabled.
public struct ExpectedCompilations {
  let expected: Set<Source>

  public init(expected: Set<Source>) {
    self.expected = expected
  }

  public init(allSourcesOf modules: [Module]) {
    self.init(expected: Set(modules.flatMap {$0.sources}))
  }

  /// Creates an `IncrementalImports` that expects no compilations.
  public static let none = Self(expected: [])

  /// Check the actual compilations against what `self` expects.
  /// Fails an `XCTest assertion` with a somewhat wordy message of things are not hunky-dory.
  /// - Parameters:
  ///   - against: The actual compiled sources to check against.
  ///   - step: The `Step` that changed the source, ran the compiler, and needs to check the results.
  ///   - in: The context of this test.
  func check(against actuals: [Source], step: Step, in context: Context) {
    let expectedSet = Set(expected)
    let actualsSet = Set(actuals)

    let   extraCompilations =  actualsSet.subtracting(expectedSet).map {$0.name}.sorted()
    let missingCompilations = expectedSet.subtracting( actualsSet).map {$0.name}.sorted()

    XCTAssert(extraCompilations.isEmpty,
      "Extra compilations: \(extraCompilations), \(context.failMessage(step))",
      file: context.file, line: context.line)

    XCTAssert(missingCompilations.isEmpty,
      "Missing compilations: \(missingCompilations), \(context.failMessage(step))",
      file: context.file, line: context.line)
  }
}
