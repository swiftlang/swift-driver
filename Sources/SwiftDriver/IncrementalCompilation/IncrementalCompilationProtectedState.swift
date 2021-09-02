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
import TSCBasic
import TSCUtility
import Foundation
import SwiftOptions

/// An instance of `IncrementalCompilationState.Actor` encapsulates the data necessary
/// to make incremental build scheduling decisions and protects it from concurrent access.

extension IncrementalCompilationState {
  // MARK: - IncrementalCompilationStateActor
  public struct ProtectedState {
    /// Keyed by primary input. As required compilations are discovered after the first wave, these shrink.
    ///
    /// This state is modified during the incremental build. All accesses must
    /// be protected by the confinement queue.
    fileprivate var skippedCompileGroups: [TypedVirtualPath: CompileJobGroup]
    
    /// Sadly, has to be `var` for formBatchedJobs
    ///
    /// After initialization, mutating accesses to the driver must be protected by
    /// the confinement queue.
    private var driver: Driver

    /// The oracle for deciding what depends on what. Applies to this whole module.
    /// fileprivate in order to control concurrency.
    fileprivate let moduleDependencyGraph: ModuleDependencyGraph
    
    fileprivate let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
    
    /// Used to double-check thread-safety
    fileprivate let confinmentQueue: DispatchQueue
    
    init(skippedCompileGroups: [TypedVirtualPath: CompileJobGroup],
         _ moduleDependencyGraph: ModuleDependencyGraph,
         _ driver: inout Driver,
         _ confinmentQueue: DispatchQueue) {
      self.skippedCompileGroups = skippedCompileGroups
      self.moduleDependencyGraph = moduleDependencyGraph
      self.info = moduleDependencyGraph.info
      self.driver = driver
      self.confinmentQueue = confinmentQueue
    }
  }
}

// MARK: - shorthands
extension IncrementalCompilationState.ProtectedState {
  
  fileprivate var reporter: IncrementalCompilationState.Reporter? {
    info.reporter
  }
  
  fileprivate func checkMutation() {
    dispatchPrecondition(condition: .onQueueAsBarrier(confinmentQueue))
  }
  fileprivate func checkAccess() {
    dispatchPrecondition(condition: .onQueue(confinmentQueue))
  }
  fileprivate func checkJustTesting() {
    dispatchPrecondition(condition: .notOnQueue(confinmentQueue))
  }
}

// MARK: - 2nd wave
extension IncrementalCompilationState.ProtectedState {
  mutating func collectBatchedJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job
  ) throws -> [Job]? {
    checkMutation()
    // batch in here to protect the Driver from concurrent access
    return try collectUnbatchedJobsDiscoveredToBeNeededAfterFinishing(job: finishedJob)
      .map {try driver.formBatchedJobs($0, showJobLifecycle: driver.showJobLifecycle)}
  }
  
  /// Remember a job (group) that is before a compile or a compile itself.
  /// `job` just finished. Update state, and return the skipped compile job (groups) that are now known to be needed.
  /// If no more compiles are needed, return nil.
  /// Careful: job may not be primary.
  fileprivate mutating func collectUnbatchedJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job) throws -> [Job]? {
      checkMutation()
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
    checkMutation()
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
    checkMutation()
    if let found = moduleDependencyGraph.collectInputsRequiringCompilation(byCompiling: input) {
      return found
    }
    self.reporter?.report(
      "Failed to read some dependencies source; compiling everything", input)
    return TransitivelyInvalidatedSwiftSourceFileSet(skippedCompileGroups.keys.swiftSourceFiles)
  }
  
  /// Find the jobs that now must be run that were not originally known to be needed.
  fileprivate mutating func getUnbatchedJobs(
    for invalidatedInputs: Set<SwiftSourceFile>
  ) throws -> [Job] {
    checkMutation()
    return invalidatedInputs.flatMap { input -> [Job] in
      if let group = skippedCompileGroups.removeValue(forKey: input.typedFile) {
        let primaryInputs = group.compileJob.primarySwiftSourceFiles
        assert(primaryInputs.count == 1)
        assert(primaryInputs[0] == input)
        self.reporter?.report("Scheduling invalidated", input)
        return group.allJobs()
      }
      else {
        self.reporter?.report("Tried to schedule invalidated input again", input)
        return []
      }
    }
  }
}
  

// MARK: - After the build
extension IncrementalCompilationState.ProtectedState {
  var skippedCompilationInputs: Set<TypedVirtualPath> {
    checkAccess()
    return Set(skippedCompileGroups.keys)
  }
  public var skippedJobs: [Job] {
    checkAccess()
    return skippedCompileGroups.values
      .sorted {$0.primaryInput.file.name < $1.primaryInput.file.name}
      .flatMap {$0.allJobs()}
  }

  @_spi(Testing) public func writeGraph(to path: VirtualPath,
                  on fs: FileSystem,
                  compilerVersion: String,
                  mockSerializedGraphVersion: Version? = nil
  ) throws {
    checkAccess()
    try moduleDependencyGraph.write(to: path, on: fs,
                                    compilerVersion: compilerVersion,
                                    mockSerializedGraphVersion: mockSerializedGraphVersion)
  }
}
// MARK: - Testing - (must be here to access graph safely)
extension IncrementalCompilationState.ProtectedState {
  @_spi(Testing) public mutating func withModuleDependencyGraph(_ fn: (ModuleDependencyGraph) -> Void ) {
    checkJustTesting()
    fn(moduleDependencyGraph)
  }
}
