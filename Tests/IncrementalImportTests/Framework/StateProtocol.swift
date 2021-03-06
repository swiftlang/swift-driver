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


// MARK: - StateProtocol

protocol StateProtocol: TestPartProtocol {
  associatedtype Module: ModuleProtocol
  typealias Source = Module.Source

  var jobs: [PlannedCompileJob<Module>] {get}
}

extension StateProtocol {
  var name: String {rawValue}

  /// Performs a mutation of the mutable source file
  private func mutate(_ context: TestContext) {
    for job in jobs {
      job.mutate(context)
    }
  }

  /// All (original) sources involved in this state, recompiled or not
  var allOriginals: [Source] {
    Array( jobs.reduce(into: Set<Source>()) { sources, job in
      sources.formUnion(job.originals)
    })
  }

  func buildFromScratch(_ context: TestContext) {
    let compiledSources = mutateAndRebuild(context)
    expectingFromScratch.check(against: compiledSources, context, stepName: "setup")
  }

  func mutateAndRebuild(_ context: TestContext) -> [Source] {
    mutate(context)
    return build(context)
  }

  /// Builds the entire project, returning what was recompiled.
   private func build(_ context: TestContext) -> [Source] {
     jobs.flatMap{ $0.build(context) }
   }

  var expectingFromScratch: Expectation<Source> {
    Expectation(with: allOriginals, without: allOriginals)
  }
}
