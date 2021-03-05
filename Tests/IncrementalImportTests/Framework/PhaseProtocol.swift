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


// MARK: - PhaseProtocol

protocol PhaseProtocol: TestPartProtocol {
  associatedtype Module: ModuleProtocol
  typealias Source = Module.Source

  var jobs: [CompileJob<Module>] {get}
}

extension PhaseProtocol {
  var name: String {rawValue}

  /// Performs a mutation of the mutable source file
  private func mutate(in testDir: AbsolutePath) {
    for job in jobs {
      job.mutate(in: testDir)
    }
  }

  /// All (original) sources involved in this phase, recompiled or not
  var allOriginals: [Source] {
    Array( jobs.reduce(into: Set<Source>()) { sources, job in
      sources.formUnion(job.originals)
    })
  }

  func buildFromScratch(
    in testDir: AbsolutePath,
    withIncrementalImports: Bool) {
    mutateAndRebuildAndCheck(
      in: testDir,
      expecting: expectingFromScratch,
      withIncrementalImports: withIncrementalImports,
      stepName: "setup")
  }

  func mutateAndRebuildAndCheck(
    in testDir: AbsolutePath,
    expecting: [Source],
    withIncrementalImports: Bool,
    stepName: String
  ) {
    print(stepName)

    mutate(in: testDir)
    let compiledSources = build(in: testDir, withIncrementalImports: withIncrementalImports)

    XCTAssertEqual(Set(compiledSources), Set(expecting),
                   "Compiled != Expected, withIncrementalImports: \(withIncrementalImports), step \(stepName)")
  }

  /// Builds the entire project, returning what was recompiled.
   private func build(in testDir: AbsolutePath,
                       withIncrementalImports: Bool) -> [Source] {
     jobs.flatMap{ $0.build(in: testDir, withIncrementalImports: withIncrementalImports) }
   }
  var expectingFromScratch: [Source] {
    Array(
      jobs.reduce(into: Set()) {
        expectations, job in
        expectations.formUnion(job.fromScratchExpectations)
      }
    )
  }


}
