//===--------------- StateProtocol.swift - Swift Testing ------------------===//
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

/// A state is a sequence of jobs to run, where each job defines the source-versions to be used.
/// A state is entered by mutating the source files and running the jobs.
/// (See `TestProtocol`.)
protocol StateProtocol: BasicEnumRequirements {
  associatedtype Module: ModuleProtocol
  typealias Source = Module.Source

  /// The jobs will be run in sequence.
  var jobs: [BuildJob<Module>] {get}
}

extension StateProtocol {
  /// Bring source files into agreement with desired versions
  private func updateChangedSources(_ context: TestContext) {
    for job in jobs {
      job.updateChangedSources(context)
    }
  }

  /// The original source-versions
  var allOriginals: [Source] {
    Array( jobs.reduce(into: Set<Source>()) { sources, job in
      sources.formUnion(job.originals)
    })
  }

  /// This state is the initial state. Create the sources, compile, and check.
  func enterInitialStateAndCheck(_ context: TestContext) {
    let compiledSources = enter(context)
    initialExpectations.check(against: compiledSources, context, stepName: "setup")
  }

  /// Enter this state: update the sources, compile, and return what was actually compiled.
  func enter(_ context: TestContext) -> [Source] {
    updateChangedSources(context)
    return compile(context)
  }

  /// Builds the entire project, returning what was recompiled.
   private func compile(_ context: TestContext) -> [Source] {
     jobs.flatMap{ $0.run(context) }
   }

  /// What should be compiled for the initial set up.
  var initialExpectations: Expectation<Source> {
    Expectation(with: allOriginals, without: allOriginals)
  }
}
