//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Testing
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

/// Each test  consists of a sequence of `Step`s.
/// Each `Step` does three things:
/// 1. Update all of the source files to reflect the edits simulated by the `addOns`.
/// 2. Incrementally rebuild the modules.
/// 3. Check what was actually recompiled against what was expected to be recompiled.
public struct Step {
  /// The `AddOn`s to be applied to the sources.
  public let addOns: [AddOn]
  /// The `Modules` to be rebuild
  let modules: [Module]
  /// The desired outcome
  let expected: Expectation

  /// By using the sourceLocation where the step was constructed, the failures show which step failed
  let sourceLocation: SourceLocation

  /// Create a `Step`
  /// - Parameters:
  ///    - adding: The names of the markers to delete and thus uncomment code
  ///    - building: The modules to compile
  ///    - expecting: What is expected
  ///    - sourceLocation: Where to place test errors
  public init(adding addOns: String...,
              building modules: [Module],
              _ expected: Expectation,
              sourceLocation: SourceLocation = #_sourceLocation) {
    self.init(adding: addOns,
              building: modules,
              expected,
              sourceLocation: sourceLocation)
  }

  /// Create a `Step`
  /// - Parameters:
  ///    - adding: The names of the markers to delete and thus uncomment code
  ///    - building: The modules to compile
  ///    - expecting: What is expected
  ///    - sourceLocation: Where to place test errors
  public init(adding addOns: [String],
              building modules: [Module],
              _ expected: Expectation,
              sourceLocation: SourceLocation = #_sourceLocation) {
    self.addOns = addOns.map(AddOn.init(named:))
    self.modules = modules
    self.expected = expected
    self.sourceLocation = sourceLocation
  }

  public func contains(addOn name: String) -> Bool {
    addOns.map {$0.name} .contains(name)
  }

  /// Perform this step. Records a test issue if what is recompiled is not as expected, or if
  /// running an executable does not produce an expected result.
  /// - Parameters:
  ///    - stepIndex: The index of this step in the test, from zero. Used for error messages, etc.
  func perform(stepIndex: Int, in context: Context) async throws {
    let stepContext = context.with(stepIndex: stepIndex, sourceLocation: sourceLocation)
    if stepContext.verbose {
      print("\n*** performing step \(stepIndex): \(whatIsBuilt), \(stepContext) ***\n")
    }
    var compiledSources: [Source] = []
    for module in modules {
      compiledSources += try await module.compile(addOns: addOns, in: stepContext)
    }
    expected.compilations.check(against: compiledSources, step: self, in: stepContext)

    guard let expectedOutput = expected.output else {
      return
    }
    let processResult = try modules.last.flatMap {
      try $0.run(step: self, in: stepContext)
    }
    try expectedOutput.check(against: processResult, step: self, in: stepContext)
  }

  var whatIsBuilt: String {
    "adding \(addOns.map {$0.name}), compiling \(modules.map {$0.name}.joined(separator: ", "))"
  }
}
