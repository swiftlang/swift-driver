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
  let whenEnabled: Set<Source>
  let whenDisabled: Set<Source>

  private init(whenEnabled: Set<Source>, whenDisabled: Set<Source>) {
    self.whenEnabled = whenEnabled
    self.whenDisabled = whenDisabled
  }

  /// Create an `ExpectedCompilations`
  /// - Parameters:
  ///   - always: The sources to expect whether incremental imports are enabled or not
  ///   - andWhenDisabled: The additional sources to expect when incremental imports are disabled
  /// - Returns: An `ExpctecCompilations`
  public init(always: [Source], andWhenDisabled: [Source] = []) {
    self.init(whenEnabled: Set(always),
              whenDisabled: Set(always + andWhenDisabled))
  }

  public init(allSourcesOf modules: [Module]) {
    self.init(always: modules.flatMap {$0.sources})
  }

  /// Creates an `IncrementalImports` that expects no compilations.
  public static let none = Self(always: [])

  /// Check the actual compilations against what `self` expects.
  /// Fails an `XCTest assertion` with a somewhat wordy message of things are not hunky-dory.
  /// - Parameters:
  ///   - against: The actual compiled sources to check against.
  ///   - step: The `Step` that changed the source, ran the compiler, and needs to check the results.
  ///   - in: The context of this test.
  func check(against actuals: [Source], step: Step, in context: Context) {
    let expectedSet = Set(expected(when: context.incrementalImports))
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

  private func expected(when incrementalImports: Context.IncrementalImports) -> Set<Source> {
    switch incrementalImports {
    case .enabled: return whenEnabled
    case .disabled: return whenDisabled
    }
  }
}
