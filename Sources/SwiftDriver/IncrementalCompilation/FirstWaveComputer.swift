//===--------------- FirstWaveComputer.swift - Incremental --------------===//
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

import Foundation
import TSCBasic

extension IncrementalCompilationState {

  struct FirstWaveComputer {
    let moduleDependencyGraph: ModuleDependencyGraph
    let jobsInPhases: JobsInPhases
    let inputsInvalidatedByExternals: TransitivelyInvalidatedSwiftSourceFileSet
    let inputFiles: [TypedVirtualPath]
    let sourceFiles: SourceFiles
    let buildRecordInfo: BuildRecordInfo
    let maybeBuildRecord: BuildRecord?
    let fileSystem: FileSystem
    let showJobLifecycle: Bool
    let alwaysRebuildDependents: Bool
    /// If non-null outputs information for `-driver-show-incremental` for input path
    private let reporter: Reporter?

    @_spi(Testing) public init(
      initialState: IncrementalCompilationState.InitialStateForPlanning,
      jobsInPhases: JobsInPhases,
      driver: Driver,
      reporter: Reporter?
    ) {
      self.moduleDependencyGraph = initialState.graph
      self.jobsInPhases = jobsInPhases
      self.inputsInvalidatedByExternals = initialState.inputsInvalidatedByExternals
      self.inputFiles = driver.inputFiles
      self.sourceFiles = SourceFiles(
        inputFiles: inputFiles,
        buildRecord: initialState.maybeBuildRecord)
      self.buildRecordInfo = initialState.buildRecordInfo
      self.maybeBuildRecord = initialState.maybeBuildRecord
      self.fileSystem = driver.fileSystem
      self.showJobLifecycle = driver.showJobLifecycle
      self.alwaysRebuildDependents = initialState.incrementalOptions.contains(
        .alwaysRebuildDependents)
      self.reporter = reporter
    }

    public func compute(batchJobFormer: inout Driver) throws -> FirstWave {
      return try blockingConcurrentAccessOrMutation {
        let (initiallySkippedCompileGroups, mandatoryJobsInOrder) =
        try computeInputsAndGroups(batchJobFormer: &batchJobFormer)
        return FirstWave(
          initiallySkippedCompileGroups: initiallySkippedCompileGroups,
          mandatoryJobsInOrder: mandatoryJobsInOrder)
      }
    }
  }
}

extension IncrementalCompilationState.FirstWaveComputer: IncrementalCompilationSynchronizer {
  var incrementalCompilationQueue: DispatchQueue {
    moduleDependencyGraph.incrementalCompilationQueue
  }

}

// MARK: - Preparing the first wave
extension IncrementalCompilationState.FirstWaveComputer {
  /// At this stage the graph will have all external dependencies found in the swiftDeps or in the priors
  /// listed in fingerprintExternalDependencies.
  private func computeInputsAndGroups(batchJobFormer: inout Driver)
  throws -> (initiallySkippedCompileGroups: [TypedVirtualPath: CompileJobGroup],
             mandatoryJobsInOrder: [Job])
  {
    precondition(sourceFiles.disappeared.isEmpty, "unimplemented")

    let compileGroups =
      Dictionary(uniqueKeysWithValues:
                  jobsInPhases.compileGroups.map { ($0.primaryInput, $0) })
    guard let buildRecord = maybeBuildRecord else {
      func everythingIsMandatory()
        throws -> (initiallySkippedCompileGroups: [TypedVirtualPath: CompileJobGroup],
                   mandatoryJobsInOrder: [Job])
      {
        let mandatoryCompileGroupsInOrder = sourceFiles.currentInOrder.compactMap {
          input -> CompileJobGroup? in
          compileGroups[input.typedFile]
        }

        let mandatoryJobsInOrder = try
        jobsInPhases.beforeCompiles +
        batchJobFormer.formBatchedJobs(
          mandatoryCompileGroupsInOrder.flatMap {$0.allJobs()},
          showJobLifecycle: showJobLifecycle)

        moduleDependencyGraph.setPhase(to: .buildingAfterEachCompilation)
        return (initiallySkippedCompileGroups: [:],
                mandatoryJobsInOrder: mandatoryJobsInOrder)
      }
      return try everythingIsMandatory()
    }
    moduleDependencyGraph.setPhase(to: .updatingAfterCompilation)

    let initiallySkippedInputs = computeInitiallySkippedCompilationInputs(
      inputsInvalidatedByExternals: inputsInvalidatedByExternals,
      moduleDependencyGraph,
      buildRecord)

    let initiallySkippedCompileGroups = compileGroups.filter { initiallySkippedInputs.contains($0.key) }

    let mandatoryCompileGroupsInOrder = inputFiles.compactMap {
      input -> CompileJobGroup? in
      initiallySkippedInputs.contains(input)
        ? nil
        : compileGroups[input]
    }

    let batchedCompilationJobs = try batchJobFormer.formBatchedJobs(
      mandatoryCompileGroupsInOrder.flatMap {$0.allJobs()},
      showJobLifecycle: showJobLifecycle)

    // In the case where there are no compilation jobs to run on this build (no source-files were changed),
    // we can skip running `beforeCompiles` jobs if we also ensure that none of the `afterCompiles` jobs
    // have any dependencies on them.
    let skipAllJobs = batchedCompilationJobs.isEmpty ? !nonVerifyAfterCompileJobsDependOnBeforeCompileJobs() : false
    let mandatoryJobsInOrder = skipAllJobs ? [] : jobsInPhases.beforeCompiles + batchedCompilationJobs
    return (initiallySkippedCompileGroups: initiallySkippedCompileGroups,
            mandatoryJobsInOrder: mandatoryJobsInOrder)
  }

  /// Determine if any of the jobs in the `afterCompiles` group depend on outputs produced by jobs in
  /// `beforeCompiles` group, which are not also verification jobs.
  private func nonVerifyAfterCompileJobsDependOnBeforeCompileJobs() -> Bool {
    let beforeCompileJobOutputs = jobsInPhases.beforeCompiles.reduce(into: Set<TypedVirtualPath>(),
                                                                     { (pathSet, job) in pathSet.formUnion(job.outputs) })
    let afterCompilesDependnigJobs = jobsInPhases.afterCompiles.filter {postCompileJob in postCompileJob.inputs.contains(where: beforeCompileJobOutputs.contains)}
    if afterCompilesDependnigJobs.isEmpty || afterCompilesDependnigJobs.allSatisfy({ $0.kind == .verifyModuleInterface }) {
      return false
    } else {
      return true
    }
  }

  /// Figure out which compilation inputs are *not* mandatory at the start
  private func computeInitiallySkippedCompilationInputs(
    inputsInvalidatedByExternals: TransitivelyInvalidatedSwiftSourceFileSet,
    _ moduleDependencyGraph: ModuleDependencyGraph,
    _ buildRecord: BuildRecord
  ) -> Set<TypedVirtualPath> {
    let allGroups = jobsInPhases.compileGroups
    // Input == source file
    let changedInputs = computeChangedInputs(moduleDependencyGraph, buildRecord)

    if let reporter = reporter {
      for input in inputsInvalidatedByExternals {
        reporter.report("Invalidated externally; will queue", input)
      }
    }

    let inputsMissingFromGraph = sourceFiles.currentInOrder.filter { sourceFile in
      !moduleDependencyGraph.containsNodes(forSourceFile: sourceFile)
    }

    if let reporter = reporter,
       moduleDependencyGraph.phase == .buildingFromSwiftDeps {
      for input in inputsMissingFromGraph {
        reporter.report("Has malformed dependency source; will queue", input)
      }
    }
    let inputsMissingOutputs = allGroups.compactMap {
      $0.outputs.contains { (try? !fileSystem.exists($0.file)) ?? true }
        ? $0.primaryInput
        : nil
    }
    if let reporter = reporter {
      for input in inputsMissingOutputs {
        reporter.report("Missing an output; will queue", input)
      }
    }

    // Combine to obtain the inputs that definitely must be recompiled.
    var definitelyRequiredInputs = Set(changedInputs.lazy.map {$0.typedFile})
    definitelyRequiredInputs.formUnion(inputsInvalidatedByExternals.lazy.map {$0.typedFile})
    definitelyRequiredInputs.formUnion(inputsMissingFromGraph.lazy.map {$0.typedFile})
    definitelyRequiredInputs.formUnion(inputsMissingOutputs)

    if let reporter = reporter {
      for scheduledInput in sortByCommandLineOrder(definitelyRequiredInputs) {
        reporter.report("Queuing (initial):", scheduledInput)
      }
    }

    // Sometimes, inputs run in the first wave that depend on the changed inputs for the
    // first wave, even though they may not require compilation.
    // Any such inputs missed, will be found by the rereading of swiftDeps
    // as each first wave job finished.
    let speculativeInputs = collectInputsToBeSpeculativelyRecompiled(
      changedInputs: changedInputs,
      externalDependents: inputsInvalidatedByExternals,
      inputsMissingOutputs: Set(inputsMissingOutputs),
      moduleDependencyGraph)
      .subtracting(definitelyRequiredInputs.swiftSourceFiles)


    if let reporter = reporter {
      for dependent in sortByCommandLineOrder(speculativeInputs) {
        reporter.report("Queuing because of the initial set:", dependent)
      }
    }
    let immediatelyCompiledInputs = definitelyRequiredInputs.union(speculativeInputs.lazy.map {$0.typedFile})

    let initiallySkippedInputs = Set(buildRecordInfo.compilationInputModificationDates.keys)
      .subtracting(immediatelyCompiledInputs)
    if let reporter = reporter {
      for skippedInput in sortByCommandLineOrder(initiallySkippedInputs) {
        reporter.report("Skipping input:", skippedInput)
      }
    }
    return initiallySkippedInputs
  }

  private func sortByCommandLineOrder(
    _ inputs: Set<TypedVirtualPath>
  ) -> LazyFilterSequence<[TypedVirtualPath]> {
      inputFiles.lazy.filter(inputs.contains)
  }

  private func sortByCommandLineOrder(
    _ inputs: Set<SwiftSourceFile>
  ) -> LazyFilterSequence<[TypedVirtualPath]> {
    inputFiles.lazy.filter {inputs.contains(SwiftSourceFile($0))}
  }

  /// Encapsulates information about an input the driver has determined has
  /// changed in a way that requires an incremental rebuild.
  struct ChangedInput {
    /// The path to the input file.
    let typedFile: TypedVirtualPath
    /// The status of the input file.
    let status: InputInfo.Status
    /// If `true`, the modification time of this input matches the modification
    /// time recorded from the prior build in the build record.
    let datesMatch: Bool
  }

  // Find the inputs that have changed since last compilation, or were marked as needed a build
  private func computeChangedInputs(
    _ moduleDependencyGraph: ModuleDependencyGraph,
    _ outOfDateBuildRecord: BuildRecord
  ) -> [ChangedInput] {
    jobsInPhases.compileGroups.compactMap { group in
      let input = group.primaryInput
      let modDate = buildRecordInfo.compilationInputModificationDates[input]
        ?? Date.distantFuture
      let inputInfo = outOfDateBuildRecord.inputInfos[input.file]
      let previousCompilationStatus = inputInfo?.status ?? .newlyAdded
      let previousModTime = inputInfo?.previousModTime

      // Because legacy driver reads/writes dates wrt 1970,
      // and because converting time intervals to/from Dates from 1970
      // exceeds Double precision, must not compare dates directly
      var datesMatch: Bool {
        modDate.timeIntervalSince1970 == previousModTime?.timeIntervalSince1970
      }

      switch previousCompilationStatus {
      case .upToDate where datesMatch:
        reporter?.report("May skip current input:", input)
        return nil

      case .upToDate:
        reporter?.report("Scheduling changed input", input)
      case .newlyAdded:
        reporter?.report("Scheduling new", input)
      case .needsCascadingBuild:
        reporter?.report("Scheduling cascading build", input)
      case .needsNonCascadingBuild:
        reporter?.report("Scheduling noncascading build", input)
      }
      return ChangedInput(typedFile: input,
                          status: previousCompilationStatus,
                          datesMatch: datesMatch)
    }
  }

  // Returns the cascaded files to compile in the first wave, even though it may not be need.
  // The needs[Non}CascadingBuild stuff was cargo-culted from the legacy driver.
  // TODO: something better, e.g. return nothing here, but process changed dependencySource
  // before the whole frontend job finished.
  private func collectInputsToBeSpeculativelyRecompiled(
    changedInputs: [ChangedInput],
    externalDependents: TransitivelyInvalidatedSwiftSourceFileSet,
    inputsMissingOutputs: Set<TypedVirtualPath>,
    _ moduleDependencyGraph: ModuleDependencyGraph
  ) -> Set<SwiftSourceFile> {
    let cascadingChangedInputs = computeCascadingChangedInputs(
      from: changedInputs,
      inputsMissingOutputs: inputsMissingOutputs)

    var inputsToBeCertainlyRecompiled = Set(cascadingChangedInputs)
    if alwaysRebuildDependents {
      inputsToBeCertainlyRecompiled.formUnion(externalDependents.lazy.map {$0.typedFile})
    }

    return inputsToBeCertainlyRecompiled.reduce(into: Set()) {
      speculativelyRecompiledInputs, certainlyRecompiledInput in
      guard let certainlyRecompiledSwiftSourceFile = SwiftSourceFile(ifSource: certainlyRecompiledInput)
      else {
        return
      }
      let speculativeDependents = moduleDependencyGraph.collectInputsInvalidatedBy(changedInput: certainlyRecompiledSwiftSourceFile)

      for speculativeDependent in speculativeDependents
      where !inputsToBeCertainlyRecompiled.contains(speculativeDependent.typedFile) {
        if speculativelyRecompiledInputs.insert(speculativeDependent).inserted {
          reporter?.report(
            "Immediately scheduling dependent on \(certainlyRecompiledInput.file.basename)",
            speculativeDependent)
        }
      }
    }
  }

  //Collect the files that will be compiled whose dependents should be schedule
  private func computeCascadingChangedInputs(
    from changedInputs: [ChangedInput],
    inputsMissingOutputs: Set<TypedVirtualPath>
  ) -> [TypedVirtualPath] {
    changedInputs.compactMap { changedInput in
      let inputIsUpToDate =
        changedInput.datesMatch && !inputsMissingOutputs.contains(changedInput.typedFile)
      let basename = changedInput.typedFile.file.basename

      // If we're asked to always rebuild dependents, all we need to do is
      // return inputs whose modification times have changed.
      guard !alwaysRebuildDependents else {
        if inputIsUpToDate {
          reporter?.report(
            "not scheduling dependents of \(basename) despite -driver-always-rebuild-dependents because is up to date")
          return nil
        } else {
          reporter?.report(
            "scheduling dependents of \(basename); -driver-always-rebuild-dependents")
          return changedInput.typedFile
        }
      }

      switch changedInput.status {
      case .needsCascadingBuild:
        reporter?.report(
          "scheduling dependents of \(basename); needed cascading build")
        return changedInput.typedFile
      case .upToDate:
        reporter?.report(
          "not scheduling dependents of \(basename); unknown changes")
        return nil
      case .newlyAdded:
        reporter?.report(
          "not scheduling dependents of \(basename): no entry in build record or dependency graph")
        return nil
      case .needsNonCascadingBuild:
        reporter?.report(
          "not scheduling dependents of \(basename): does not need cascading build")
        return nil
      }
    }
  }
}
