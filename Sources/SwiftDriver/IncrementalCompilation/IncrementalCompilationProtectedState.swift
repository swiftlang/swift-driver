//===---------- IncrementalCompilationActor.swift - Incremental -----------===//
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

import protocol TSCBasic.FileSystem

extension IncrementalCompilationState {
  /// Encapsulates the data necessary to make incremental build scheduling decisions and protects it from concurrent access.
  public struct ProtectedState {
    /// Keyed by primary input. As required compilations are discovered after the first wave, these shrink.
    ///
    /// This state is modified during the incremental build. All accesses must
    /// be protected by the confinement queue.
    fileprivate var skippedCompileJobs: [TypedVirtualPath: Job]

    /// Sadly, has to be `var` for formBatchedJobs
    ///
    /// After initialization, mutating accesses to the driver must be protected by
    /// the confinement queue.
    private var driver: Driver

    /// The oracle for deciding what depends on what. Applies to this whole module.
    /// fileprivate in order to control concurrency.
    fileprivate let moduleDependencyGraph: ModuleDependencyGraph

    fileprivate let jobCreatingPch: Job?
    fileprivate let reporter: Reporter?

    init(skippedCompileJobs: [TypedVirtualPath: Job],
         _ moduleDependencyGraph: ModuleDependencyGraph,
         _ jobCreatingPch: Job?,
         _ driver: inout Driver) {
      self.skippedCompileJobs = skippedCompileJobs
      self.moduleDependencyGraph = moduleDependencyGraph
      self.reporter = moduleDependencyGraph.info.reporter
      self.jobCreatingPch = jobCreatingPch
      self.driver = driver
    }
  }
}

extension IncrementalCompilationState.ProtectedState: IncrementalCompilationSynchronizer {
  public var incrementalCompilationQueue: DispatchQueue {
    moduleDependencyGraph.incrementalCompilationQueue
  }
}

// MARK: - 2nd wave
extension IncrementalCompilationState.ProtectedState {
  mutating func collectBatchedJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job
  ) throws -> [Job]? {
    mutationSafetyPrecondition()
    // batch in here to protect the Driver from concurrent access
    return try collectUnbatchedJobsDiscoveredToBeNeededAfterFinishing(job: finishedJob)
      .map {try driver.formBatchedJobs($0, showJobLifecycle: driver.showJobLifecycle, jobCreatingPch: jobCreatingPch)}
  }

  /// Remember a job (group) that is before a compile or a compile itself.
  /// `job` just finished. Update state, and return the skipped compile job (groups) that are now known to be needed.
  /// If no more compiles are needed, return nil.
  /// Careful: job may not be primary.
  fileprivate mutating func collectUnbatchedJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job) throws -> [Job]? {
      mutationSafetyPrecondition()
      // Find and deal with inputs that now need to be compiled
      let invalidatedInputs = collectInputsInvalidatedByRunning(finishedJob)
      assert(invalidatedInputs.isDisjoint(with: finishedJob.primarySwiftSourceFiles),
             "Primaries should not overlap secondaries.")

      if let reporter = self.reporter {
        for input in invalidatedInputs {
          reporter.report(
            "Queuing because of dependencies discovered later:", input)
        }
      }
      return try getUnbatchedJobs(for: invalidatedInputs)
    }

  /// After `job` finished find out which inputs must compiled that were not known to need compilation before
  fileprivate mutating func collectInputsInvalidatedByRunning(_ job: Job)-> Set<SwiftSourceFile> {
    mutationSafetyPrecondition()
    guard job.kind == .compile else {
      return Set<SwiftSourceFile>()
    }
    return job.primaryInputs.reduce(into: Set()) { invalidatedInputs, primaryInput in
      if let primary = SwiftSourceFile(ifSource: primaryInput) {
        invalidatedInputs.formUnion(collectInputsInvalidated(byCompiling: primary))
      }
    }
    .subtracting(job.primarySwiftSourceFiles) // have already compiled these
  }

  // "Mutating" because it mutates the graph, which may be a struct someday
  fileprivate mutating func collectInputsInvalidated(
    byCompiling input: SwiftSourceFile
  ) -> TransitivelyInvalidatedSwiftSourceFileSet {
    mutationSafetyPrecondition()
    if let found = moduleDependencyGraph.collectInputsRequiringCompilation(byCompiling: input) {
      return found
    }
    self.reporter?.report(
      "Failed to read some dependencies source; compiling everything", input)
    return TransitivelyInvalidatedSwiftSourceFileSet(skippedCompileJobs.keys.swiftSourceFiles)
  }

  /// Find the jobs that now must be run that were not originally known to be needed.
  fileprivate mutating func getUnbatchedJobs(
    for invalidatedInputs: Set<SwiftSourceFile>
  ) throws -> [Job] {
    mutationSafetyPrecondition()
    return invalidatedInputs.compactMap { input -> Job? in
      if let job = skippedCompileJobs.removeValue(forKey: input.typedFile) {
        let primaryInputs = job.primarySwiftSourceFiles
        assert(primaryInputs.count == 1)
        assert(primaryInputs[0] == input)
        self.reporter?.report("Scheduling invalidated", input)
        return job
      }
      else {
        self.reporter?.report("Tried to schedule invalidated input again", input)
        return nil
      }
    }
  }
}


// MARK: - After the build
extension IncrementalCompilationState.ProtectedState {
  var skippedCompilationInputs: Set<TypedVirtualPath> {
    accessSafetyPrecondition()
    return Set(skippedCompileJobs.keys)
  }
  public var skippedJobs: [Job] {
    accessSafetyPrecondition()
    return skippedCompileJobs.values
      .sorted {$0.primaryInputs[0].file.name < $1.primaryInputs[0].file.name}
  }

  func writeGraph(to path: VirtualPath,
                  on fs: FileSystem,
                  buildRecord: BuildRecord,
                  mockSerializedGraphVersion: Version? = nil
  ) throws {
    accessSafetyPrecondition()
    try moduleDependencyGraph.write(to: path, on: fs,
                                    buildRecord: buildRecord,
                                    mockSerializedGraphVersion: mockSerializedGraphVersion)
  }
}
// MARK: - Testing - (must be here to access graph safely)
extension IncrementalCompilationState.ProtectedState {
  /// Expose the protected ``ModuleDependencyGraph`` for testing
  @_spi(Testing) public mutating func testWithModuleDependencyGraph(
    _ fn: (ModuleDependencyGraph) throws -> Void
  ) rethrows {
    mutationSafetyPrecondition()
    try fn(moduleDependencyGraph)
  }
}
