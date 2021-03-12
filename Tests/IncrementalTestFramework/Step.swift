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
  let addOns: [AddOn]
  /// The `Modules` to be rebuild
  let compilations: [Module]
  /// The desired outcome
  let expectation: ExpectedCompilations

  /// By using the file & line where the step was constructed, the failures show which step failed
  let file: StaticString
  let line: UInt

  /// Create a `Step`
  /// - Parameters:
  ///    - adding: The names of the markers to delete and thus uncomment code
  ///    - compiling: The modules to compile
  ///    - expecting: What is expected
  ///    - file: Where to place test errors
  ///    - line: Where to place test errors
  public init(adding addOns: String...,
              compiling compilations: [Module],
              expecting expectation: ExpectedCompilations,
              file: StaticString = #file,
              line: UInt = #line) {
    self.init(adding: addOns,
              compiling: compilations,
              expecting: expectation,
              file: file,
              line: line)
  }

  /// Create a `Step`
  /// - Parameters:
  ///    - adding: The names of the markers to delete and thus uncomment code
  ///    - compiling: The modules to compile
  ///    - expecting: What is expected
  ///    - file: Where to place test errors
  ///    - line: Where to place test errors
  public init(adding addOns: [String],
              compiling compilations: [Module],
              expecting expectation: ExpectedCompilations,
              file: StaticString = #file,
              line: UInt = #line) {
    self.addOns = addOns.map(AddOn.init(named:))
    self.compilations = compilations
    self.expectation = expectation
    self.file = file
    self.line = line
  }

  /// Create a `Step` that expects to recompile everything. Useful for the first step in the test.
  /// - Parameters:
  ///    - adding: The names of the markers to delete and thus uncomment code
  ///    - compiling: The modules to compile
  ///    - file: Where to place test errors
  ///    - line: Where to place test errors  public init(adding addOns: [String] = [],
  public init(adding addOns: [String] = [],
              compiling compilations: [Module],
              file: StaticString = #file,
              line: UInt = #line) {
    self.init(
      adding: addOns,
      compiling: compilations,
      expecting: ExpectedCompilations(allSourcesOf: compilations),
      file: file,
      line: line)
  }

  /// Perform this step. Fails an `XCTest` assertion if what is recompiled is not as expected.
  /// - Parameters:
  ///    - stepIndex: The index of this step in the test, from zero. Used for error messages, etc.
  func perform(stepIndex: Int, in context: Context) throws {
    let stepContext = context.with(file: file, line: line)
    if stepContext.verbose {
      print("\n*** performing step \(stepIndex): \(whatIsBuilt), \(context) ***\n")
    }
    let compiledSources = try compilations.flatMap {
      try $0.compile(addOns: addOns, in: stepContext)
    }
    expectation.check(against: compiledSources, step: self, stepIndex: stepIndex, in: stepContext)
  }

  var whatIsBuilt: String {
    "adding \(addOns.map {$0.name}), compiling \(compilations.map {$0.name}.joined(separator: ", "))"
  }
}
