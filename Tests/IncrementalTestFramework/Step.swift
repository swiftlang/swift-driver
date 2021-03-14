//===--------------- Step.swift - Swift Testing ----------------------===//
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

  /// By using the file & line where the step was constructed, the failures show which step failed
  let file: StaticString
  let line: UInt

  /// Create a `Step`
  /// - Parameters:
  ///    - adding: The names of the markers to delete and thus uncomment code
  ///    - building: The modules to compile
  ///    - expecting: What is expected
  ///    - file: Where to place test errors
  ///    - line: Where to place test errors
  public init(adding addOns: String...,
              building modules: [Module],
              _ expected: Expectation,
              file: StaticString = #file,
              line: UInt = #line) {
    self.init(adding: addOns,
              building: modules,
              expected,
              file: file,
              line: line)
  }

  /// Create a `Step`
  /// - Parameters:
  ///    - adding: The names of the markers to delete and thus uncomment code
  ///    - building: The modules to compile
  ///    - expecting: What is expected
  ///    - line: Where to place test errors
  public init(adding addOns: [String],
              building modules: [Module],
              _ expected: Expectation,
              file: StaticString = #file,
              line: UInt = #line) {
    self.addOns = addOns.map(AddOn.init(named:))
    self.modules = modules
    self.expected = expected
    self.file = file
    self.line = line
  }

  public func contains(addOn name: String) -> Bool {
    addOns.map {$0.name} .contains(name)
  }

  /// Perform this step. Fails an `XCTest` assertion if what is recompiled is not as expected, or if
  /// running an executable does not produce an expected result.
  /// - Parameters:
  ///    - stepIndex: The index of this step in the test, from zero. Used for error messages, etc.
  func perform(stepIndex: Int, in context: Context) throws {
    let stepContext = context.with(stepIndex: stepIndex, file: file, line: line)
    if stepContext.verbose {
      print("\n*** performing step \(stepIndex): \(whatIsBuilt), \(stepContext) ***\n")
    }
    let compiledSources = try modules.flatMap {
      try $0.compile(addOns: addOns, in: stepContext)
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
