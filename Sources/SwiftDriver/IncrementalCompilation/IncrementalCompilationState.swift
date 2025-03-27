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
import SwiftOptions

/// An instance of `IncrementalCompilationState` encapsulates the data necessary
/// to make incremental build scheduling decisions.
///
/// The primary form of interaction with the incremental compilation state is
/// using it as an oracle to discover the jobs to execute as the incremental
/// build progresses. After a job completes, call
/// `protectedState.collectJobsDiscoveredToBeNeededAfterFinishing(job:)`
/// to both update the incremental state and receive an array of jobs that
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

  /// State needed for incremental compilation that can change during a run and must be protected from
  /// concurrent mutation and access. Concurrent accesses are OK.
  private var protectedState: ProtectedState

  /// All of the pre-compile or compilation job (groups) known to be required (i.e. in 1st wave).
  /// Already batched, and in order of input files.
  public let mandatoryJobsInOrder: [Job]

  /// Jobs to run *after* the last compile, for instance, link-editing.
  public let jobsAfterCompiles: [Job]

  /// The skipped non compile jobs.
  public let skippedJobsNonCompile: [Job]

  public let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup

  internal let upToDateInterModuleDependencyGraph: InterModuleDependencyGraph?

  // MARK: - Creating IncrementalCompilationState
  /// Return nil if not compiling incrementally
  internal init(
    driver: inout Driver,
    jobsInPhases: JobsInPhases,
    initialState: InitialStateForPlanning,
    interModuleDepGraph: InterModuleDependencyGraph?
  ) throws {
    let reporter = initialState.incrementalOptions.contains(.showIncremental)
      ? Reporter(diagnosticEngine: driver.diagnosticEngine,
                 outputFileMap: driver.outputFileMap)
      : nil

    let firstWave = try FirstWaveComputer(
      initialState: initialState,
      jobsInPhases: jobsInPhases,
      driver: driver,
      interModuleDependencyGraph: interModuleDepGraph,
      reporter: reporter)
      .compute(batchJobFormer: &driver)

    self.info = initialState.graph.info
    self.upToDateInterModuleDependencyGraph = interModuleDepGraph
    self.protectedState = ProtectedState(
      skippedCompileJobs: firstWave.initiallySkippedCompileJobs,
      initialState.graph,
      jobsInPhases.allJobs.first(where: {$0.kind == .generatePCH}),
      &driver)
    self.mandatoryJobsInOrder = firstWave.mandatoryJobsInOrder
    self.jobsAfterCompiles = firstWave.jobsAfterCompiles
    self.skippedJobsNonCompile = firstWave.skippedNonCompileJobs
  }

  /// Allow concurrent access to while preventing mutation of ``IncrementalCompilationState/protectedState``
  public func blockingConcurrentMutationToProtectedState<R>(
    _ fn: (ProtectedState) throws -> R
  ) rethrows -> R {
    try blockingConcurrentMutation {try fn(protectedState)}
  }

  /// Block any other threads from doing anything to  or observing `protectedState`.
  public func blockingConcurrentAccessOrMutationToProtectedState<R>(
    _ fn: (inout ProtectedState) throws -> R
  ) rethrows -> R {
    try blockingConcurrentAccessOrMutation {
      try fn(&protectedState)
    }
  }
}

extension IncrementalCompilationState: IncrementalCompilationSynchronizer {
  public var incrementalCompilationQueue: DispatchQueue {
    info.incrementalCompilationQueue
  }
}
