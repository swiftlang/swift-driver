//===--------------- IncrementalCompilation.swift - Incremental -----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import TSCBasic
import TSCUtility
import SwiftOptions

/// An instance of `IncrementalCompilationState` encapsulates the data necessary
/// to make incremental build scheduling decisions.
///
/// The primary form of interaction with the incremental compilation state is
/// using it as an oracle to discover the jobs to execute as the incremental
/// build progresses. After a job completes, call
/// `protectedState.collectJobsDiscoveredToBeNeededAfterFinishing(job:)`
/// to both update the incremental state and recieve an array of jobs that
/// need to be executed in response.
///
/// Jobs become "unstuck" as their inputs become available, or may be discovered
/// by this class as fresh dependency information is integrated.
///
/// Threading Considerations
/// ========================
///
/// The public API surface of this class is thread safe, but not re-entrant.
/// FIXME: This should be an actor.
public final class IncrementalCompilationState {
    
  private var protectedState: ProtectedState

  /// All of the pre-compile or compilation job (groups) known to be required (i.e. in 1st wave).
  /// Already batched, and in order of input files.
  public let mandatoryJobsInOrder: [Job]

  /// Jobs to run *after* the last compile, for instance, link-editing.
  public let jobsAfterCompiles: [Job]
  
  public let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup


  // MARK: - Creating IncrementalCompilationState
  /// Return nil if not compiling incrementally
  internal init(
    driver: inout Driver,
    jobsInPhases: JobsInPhases,
    initialState: InitialStateForPlanning
  ) throws {
    let reporter = initialState.incrementalOptions.contains(.showIncremental)
      ? Reporter(diagnosticEngine: driver.diagnosticEngine,
                 outputFileMap: driver.outputFileMap)
      : nil
    
    reporter?.reportOnIncrementalImports(
      initialState.incrementalOptions.contains(.enableCrossModuleIncrementalBuild))

    let firstWave =
      try FirstWaveComputer(initialState: initialState, jobsInPhases: jobsInPhases,
                            driver: driver, reporter: reporter).compute(batchJobFormer: &driver)

    self.info = initialState.graph.info
    self.protectedState = ProtectedState(
      skippedCompileGroups: firstWave.initiallySkippedCompileGroups,
      initialState.graph,
      &driver,
      info.confinementQueue)
    self.mandatoryJobsInOrder = firstWave.mandatoryJobsInOrder
    self.jobsAfterCompiles = jobsInPhases.afterCompiles
  }
  
  var confinementQueue: DispatchQueue {
    info.confinementQueue
  }
  
  /// Block any threads from mutating `ProtectedState`
  public func blockingConcurrentMutation<R>(
    _ fn: (ProtectedState) throws -> R
  ) rethrows -> R {
    try confinementQueue.sync {try fn(protectedState)}
  }
  
  /// Block any other threads from doing anything to `ProtectedState`
  public func blockingConcurrentAccessOrMutation<R>(
    _ fn: (inout ProtectedState) throws -> R
  ) rethrows -> R {
    try confinementQueue.sync(flags: .barrier) {
      try fn(&protectedState)
    }
  }
}

fileprivate extension IncrementalCompilationState.Reporter {
  func reportOnIncrementalImports(_ enabled: Bool) {
    report(
      "\(enabled ? "Enabling" : "Disabling") incremental cross-module building")
  }
}
