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
import TSCBasic
import Foundation
import SwiftOptions
public class IncrementalCompilationState {

  /// The oracle for deciding what depends on what. Applies to this whole module.
  private let moduleDependencyGraph: ModuleDependencyGraph

  /// If non-null outputs information for `-driver-show-incremental` for input path
  public let reportIncrementalDecision: ((String, TypedVirtualPath?) -> Void)?

  /// All of the pre-compile or compilation job (groups) known to be required, preserving planning order
  public private (set) var mandatoryPreOrCompileJobsInOrder = [Job]()

  /// All the  pre- or compilation job (groups) known to be required, which have not finished yet.
  /// (Changes as jobs complete.)
  private var unfinishedMandatoryJobs = Set<Job>()

  /// Inputs that must be compiled, and swiftDeps processed.
  /// When empty, the compile phase is done.
  private var pendingInputs = Set<TypedVirtualPath>()

  /// Input files that were skipped.
  /// May shrink if one of these moves into pendingInputs. In that case, it will be an input to a
  /// "newly-discovered" job.
  private(set) var skippedCompilationInputs: Set<TypedVirtualPath>

  /// Job groups that were skipped.
  /// Need groups rather than jobs because a compile that emits bitcode and its backend job must be
  /// treated as a unit.
  private var skippedCompileGroups = [TypedVirtualPath: [Job]]()

  /// Jobs to run *after* the last compile, for instance, link-editing.
  public private(set) var postCompileJobs = [Job]()

  /// A check for reentrancy.
  private var amHandlingJobCompletion = false

// MARK: - Creating IncrementalCompilationState if possible
  /// Return nil if not compiling incrementally
  init?(
    buildRecordInfo: BuildRecordInfo?,
    compilerMode: CompilerMode,
    diagnosticEngine: DiagnosticsEngine,
    fileSystem: FileSystem,
    inputFiles: [TypedVirtualPath],
    outputFileMap: OutputFileMap?,
    parsedOptions: inout ParsedOptions,
    showJobLifecycle: Bool
  ) {
    guard Self.shouldAttemptIncrementalCompilation(
            parsedOptions: &parsedOptions,
            compilerMode: compilerMode,
            diagnosticEngine: diagnosticEngine)
    else {
      return nil
    }

    guard let outputFileMap = outputFileMap,
          let buildRecordInfo = buildRecordInfo
    else {
      diagnosticEngine.emit(.warning_incremental_requires_output_file_map)
      return nil
    }

    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard let outOfDateBuildRecord = buildRecordInfo.populateOutOfDateBuildRecord(
            inputFiles: inputFiles,
            failed: {
              diagnosticEngine.emit(
                .remark_incremental_compilation_disabled(because: $0))
            })
    else {
      return nil
    }

    let reportIncrementalDecision =
      parsedOptions.hasArgument(.driverShowIncremental) || showJobLifecycle
      ? { Self.reportIncrementalDecisionFn($0, $1, outputFileMap, diagnosticEngine) }
      : nil

    guard let (moduleDependencyGraph, inputsWithUnreadableSwiftDeps) =
            ModuleDependencyGraph.buildInitialGraph(
              diagnosticEngine: diagnosticEngine,
              inputs: buildRecordInfo.compilationInputModificationDates.keys,
              previousInputs: outOfDateBuildRecord.allInputs,
              outputFileMap: outputFileMap,
              parsedOptions: &parsedOptions,
              remarkDisabled: Diagnostic.Message.remark_incremental_compilation_disabled,
              reportIncrementalDecision: reportIncrementalDecision)
    else {
      return nil
    }
    // preserve legacy behavior
    if let badSwiftDeps = inputsWithUnreadableSwiftDeps.first?.1 {
      diagnosticEngine.emit(
        .remark_incremental_compilation_disabled(
          because: "malformed swift dependencies file '\(badSwiftDeps)'")
      )
      return nil
    }

    // But someday, just ensure inputsWithUnreadableSwiftDeps are compiled
    self.skippedCompilationInputs = Self.computeSkippedCompilationInputs(
      inputFiles: inputFiles,
      inputsWithUnreadableSwiftDeps: inputsWithUnreadableSwiftDeps.map {$0.0},
      buildRecordInfo: buildRecordInfo,
      moduleDependencyGraph: moduleDependencyGraph,
      outOfDateBuildRecord: outOfDateBuildRecord,
      alwaysRebuildDependents: parsedOptions.contains(.driverAlwaysRebuildDependents),
      reportIncrementalDecision: reportIncrementalDecision)

    self.moduleDependencyGraph = moduleDependencyGraph
    self.reportIncrementalDecision = reportIncrementalDecision
  }

  /// Check various arguments to rule out incremental compilation if need be.
  private static func shouldAttemptIncrementalCompilation(
    parsedOptions: inout ParsedOptions,
    compilerMode: CompilerMode,
    diagnosticEngine: DiagnosticsEngine
  ) -> Bool {
    guard parsedOptions.hasArgument(.incremental) else {
      return false
    }
    guard compilerMode.supportsIncrementalCompilation else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_disabled(
          because: "it is not compatible with \(compilerMode)"))
      return false
    }
    guard !parsedOptions.hasArgument(.embedBitcode) else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_disabled(
          because: "is not currently compatible with embedding LLVM IR bitcode"))
      return false
    }
    return true
  }
}

fileprivate extension CompilerMode {
  var supportsIncrementalCompilation: Bool {
    switch self {
    case .standardCompile, .immediate, .repl, .batchCompile: return true
    case .singleCompile, .compilePCM: return false
    }
  }
}

// MARK: - Outputting debugging info
fileprivate extension IncrementalCompilationState {
  private static func reportIncrementalDecisionFn(
    _ s: String,
    _ path: TypedVirtualPath?,
    _ outputFileMap: OutputFileMap,
    _ diagnosticEngine: DiagnosticsEngine
  ) {
    let IO = path.flatMap {
      $0.type == .swift ? $0.file : outputFileMap.getInput(outputFile: $0.file)
    }
    .map {($0.basename,
           outputFileMap.getOutput(inputFile: $0, outputType: .object).basename
    )}
    let pathPart = IO.map { " {compile: \($0.1) <= \($0.0)}" }
    let message = "\(s)\(pathPart ?? "")"
    diagnosticEngine.emit(.remark_incremental_compilation(because: message))
  }
}

extension Diagnostic.Message {
  fileprivate static var warning_incremental_requires_output_file_map: Diagnostic.Message {
    .warning("ignoring -incremental (currently requires an output file map)")
  }
  static var warning_incremental_requires_build_record_entry: Diagnostic.Message {
    .warning(
      "ignoring -incremental; " +
        "output file map has no master dependencies entry (\"\(FileType.swiftDeps)\" under \"\")"
    )
  }
  fileprivate static func remark_incremental_compilation_disabled(because why: String) -> Diagnostic.Message {
    .remark("Disabling incremental build: \(why)")
  }
  fileprivate static func remark_incremental_compilation(because why: String) -> Diagnostic.Message {
    .remark("Incremental compilation: \(why)")
  }
}


// MARK: - Scheduling the first wave, i.e. the mandatory pre- and compile jobs

extension IncrementalCompilationState {

  /// Figure out which compilation inputs are *not* mandatory
  private static func computeSkippedCompilationInputs(
    inputFiles: [TypedVirtualPath],
    inputsWithUnreadableSwiftDeps: [TypedVirtualPath],
    buildRecordInfo: BuildRecordInfo,
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    alwaysRebuildDependents: Bool,
    reportIncrementalDecision: ((String, TypedVirtualPath?) -> Void)?
  ) -> Set<TypedVirtualPath> {

    let changedInputs: [(TypedVirtualPath, InputInfo.Status)] = computeChangedInputs(
      inputFiles: inputFiles,
      buildRecordInfo: buildRecordInfo,
      moduleDependencyGraph: moduleDependencyGraph,
      outOfDateBuildRecord: outOfDateBuildRecord,
      reportIncrementalDecision: reportIncrementalDecision)
    let externalDependents = computeExternallyDependentInputs(
      buildTime: outOfDateBuildRecord.buildTime,
      fileSystem: buildRecordInfo.fileSystem,
      moduleDependencyGraph: moduleDependencyGraph,
      reportIncrementalDecision: reportIncrementalDecision)

    // Combine to obtain the inputs that definitely must be recompiled.
    let definitelyRequiredInputs = Set(changedInputs.map {$0.0} + externalDependents + inputsWithUnreadableSwiftDeps)
    if let report = reportIncrementalDecision {
      for scheduledInput in definitelyRequiredInputs.sorted(by: {$0.file.name < $1.file.name}) {
        report("Queuing (initial):", scheduledInput)
      }
    }

    // Sometimes, inputs run in the first wave that depend on the changed inputs for the
    // first wave, even though they may not require compilation.
    // Any such inputs missed, will be found by the rereading of swiftDeps
    // as each first wave job finished.
    let speculativeInputs = computeSpeculativeInputs(
      changedInputs: changedInputs,
      moduleDependencyGraph: moduleDependencyGraph,
      alwaysRebuildDependents: alwaysRebuildDependents,
      reportIncrementalDecision: reportIncrementalDecision)
      .subtracting(definitelyRequiredInputs)

    if let report = reportIncrementalDecision {
      for dependent in speculativeInputs.sorted(by: {$0.file.name < $1.file.name}) {
        report("Queuing (dependent):", dependent)
      }
    }
    let immediatelyCompiledInputs = definitelyRequiredInputs.union(speculativeInputs)

    let skippedInputs = Set(buildRecordInfo.compilationInputModificationDates.keys)
      .subtracting(immediatelyCompiledInputs)
    if let report = reportIncrementalDecision {
      for skippedInput in skippedInputs.sorted(by: {$0.file.name < $1.file.name})  {
        report("Skipping input:", skippedInput)
      }
    }
    return skippedInputs
  }

  /// Find the inputs that have changed since last compilation, or were marked as needed a build
  private static func computeChangedInputs(
    inputFiles: [TypedVirtualPath],
    buildRecordInfo: BuildRecordInfo,
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    reportIncrementalDecision: ((String, TypedVirtualPath?) -> Void)?
   ) -> [(TypedVirtualPath, InputInfo.Status)] {
    inputFiles.compactMap { input in
      guard input.type.isPartOfSwiftCompilation else {
        return nil
      }
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
        reportIncrementalDecision?("May skip current input:", input)
        return nil

      case .upToDate:
        reportIncrementalDecision?("Scheduing changed input", input)
      case .newlyAdded:
        reportIncrementalDecision?("Scheduling new", input)
      case .needsCascadingBuild:
        reportIncrementalDecision?("Scheduling cascading build", input)
      case .needsNonCascadingBuild:
        reportIncrementalDecision?("Scheduling noncascading build", input)
      }
      return (input, previousCompilationStatus)
    }
  }


  /// Any files dependent on modified files from other modules must be compiled, too.
  private static func computeExternallyDependentInputs(
    buildTime: Date,
    fileSystem: FileSystem,
    moduleDependencyGraph: ModuleDependencyGraph,
    reportIncrementalDecision: ((String, TypedVirtualPath?) -> Void)?
 ) -> [TypedVirtualPath] {
    var externallyDependentSwiftDeps = Set<ModuleDependencyGraph.SwiftDeps>()
    for extDep in moduleDependencyGraph.externalDependencies {
      let extModTime = extDep.file.flatMap {
        try? fileSystem.getFileInfo($0).modTime}
        ?? Date.distantFuture
      if extModTime >= buildTime {
        moduleDependencyGraph.forEachUntracedSwiftDepsDirectlyDependent(on: extDep) {
          reportIncrementalDecision?(
            "Scheduling externally-dependent on newer  \(extDep.file?.basename ?? "extDep?")",
            TypedVirtualPath(file: $0.file, type: .swiftDeps))
          externallyDependentSwiftDeps.insert($0)
        }
      }
    }
    return externallyDependentSwiftDeps.compactMap {
      moduleDependencyGraph.sourceSwiftDepsMap[$0]
    }
  }

  /// Returns the cascaded files to compile in the first wave, even though it may not be need.
  /// The needs[Non}CascadingBuild stuff was cargo-culted from the legacy driver.
  /// TODO: something better, e.g. return nothing here, but process changed swiftDeps
  /// before the whole frontend job finished.
  private static func computeSpeculativeInputs(
    changedInputs: [(TypedVirtualPath, InputInfo.Status)],
    moduleDependencyGraph: ModuleDependencyGraph,
    alwaysRebuildDependents: Bool,
    reportIncrementalDecision: ((String, TypedVirtualPath?) -> Void)?
    ) -> Set<TypedVirtualPath> {
    // Collect the files that will be compiled whose dependents should be schedule
    let cascadingFiles: [TypedVirtualPath] = changedInputs.compactMap { input, status in
      let basename = input.file.basename
      switch (status, alwaysRebuildDependents) {

       case (_, true):
        reportIncrementalDecision?(
          "scheduling dependents of \(basename); -driver-always-rebuild-dependents", nil)
        return input
      case (.needsCascadingBuild, false):
        reportIncrementalDecision?(
          "scheduling dependents of \(basename); needed cascading build", nil)
        return input

      case (.upToDate, false): // was up to date, but changed
        reportIncrementalDecision?(
          "not scheduling dependents of \(basename); unknown changes", nil)
        return nil
       case (.newlyAdded, false):
        reportIncrementalDecision?(
          "not scheduling dependents of \(basename): no entry in build record or dependency graph", nil)
        return nil
      case (.needsNonCascadingBuild, false):
        reportIncrementalDecision?(
          "not scheduling dependents of \(basename): does not need cascading build", nil)
        return nil
      }
    }
    // Collect the dependent files to speculatively schedule
    var dependentFiles = Set<TypedVirtualPath>()
    let cascadingFileSet = Set(cascadingFiles)
    for cascadingFile in cascadingFiles {
       let dependentsOfOneFile = moduleDependencyGraph
        .findDependentSourceFiles(of: cascadingFile, reportIncrementalDecision)
      for dep in dependentsOfOneFile where !cascadingFileSet.contains(dep) {
        if dependentFiles.insert(dep).0 {
          reportIncrementalDecision?(
            "Immediately scheduling dependent on \(cascadingFile.file.basename)", dep)
        }
      }
    }
    return dependentFiles
  }
}

// MARK: - Scheduling
extension IncrementalCompilationState {
  /// Remember a job (group) that is before a compile or a compile itself.
  /// (A group also includes the "backend" jobs for bitcode.)
  /// Decide if  a job can be skipped, and register accordingly
  func addPreOrCompileJobGroups(_ groups: [[Job]],
                                formBatchedJobs: ([Job]) throws -> [Job]
  ) throws {
    let mandatoryPreOrCompileJobs = groups.flatMap { group -> [Job] in
      if let firstJob = group.first, isSkipped(firstJob) {
        recordSkippedGroup(group)
        return []
      }
      return group
    }
    let batchedMandatoryPreOrCompileJobs = try formBatchedJobs(mandatoryPreOrCompileJobs)
    scheduleMandatoryPreOrCompile(jobs: batchedMandatoryPreOrCompileJobs)
  }

  /// Remember that `group` (a compilation and possibly bitcode generation)
  /// must definitely be executed.
  private func scheduleMandatoryPreOrCompile(jobs: [Job]) {
    if let report = reportIncrementalDecision {
      for job in jobs {
        report("Queuing \(job.descriptionForLifecycle)", nil)
      }
    }
    mandatoryPreOrCompileJobsInOrder.append(contentsOf: jobs)
    unfinishedMandatoryJobs.formUnion(jobs)
    let mandatoryCompilationInputs = jobs
      .flatMap {$0.kind == .compile ? $0.primaryInputs : []}
    pendingInputs.formUnion(mandatoryCompilationInputs)
  }

  /// Decide if this job does not need to run, unless some yet-to-be-discovered dependency changes.
  private func isSkipped(_ job: Job) -> Bool {
    guard job.kind == .compile else {
      return false
    }
    assert(job.primaryInputs.count <= 1, "Jobs should not be batched here.")
    return job.primaryInputs.first.map(skippedCompilationInputs.contains) ?? false
  }

  /// Remember that this job-group will be skipped (but may be needed later)
  private func recordSkippedGroup(_ group: [Job]) {
    let job = group.first!
    for input in job.primaryInputs {
      if let _ = skippedCompileGroups.updateValue(group, forKey: input) {
        fatalError("should not have two skipped jobs for same skipped input")
      }
    }
  }

  /// Remember a job that runs after all compile jobs, e.g., ld
  func addPostCompileJobs(_ jobs: [Job]) {
    self.postCompileJobs = jobs
    for job in jobs {
      if let report = reportIncrementalDecision {
        for input in job.primaryInputs {
          report("Delaying pending discovering delayed dependencies", input)
        }
      }
    }
  }

  /// `job` just finished. Update state, and return the skipped compile job (groups) that are now known to be needed.
  /// If no more compiles are needed, return nil.
  /// Careful: job may not be primary.
  public func getJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job, result: ProcessResult)
  -> [Job]? {
    defer {
      amHandlingJobCompletion = false
    }
    assert(!amHandlingJobCompletion, "was reentered, need to synchronize")
    amHandlingJobCompletion = true

    unfinishedMandatoryJobs.remove(finishedJob)
    if finishedJob.kind == .compile {
      finishedJob.primaryInputs.forEach {
        if pendingInputs.remove($0) == nil {
          fatalError("\($0) input to newly-finished \(finishedJob) should have been pending")
        }
      }
    }

    // Find and deal with inputs that how need to be compiled
    let discoveredInputs = collectInputsDiscovered(from: finishedJob)
    assert(Set(discoveredInputs).isDisjoint(with: finishedJob.primaryInputs),
           "Primaries should not overlap secondaries.")
    skippedCompilationInputs.subtract(discoveredInputs)
    pendingInputs.formUnion(discoveredInputs)

    if let report = reportIncrementalDecision {
      for input in discoveredInputs {
        report("Queuing because of dependencies discovered later:", input)
      }
    }
    if pendingInputs.isEmpty && unfinishedMandatoryJobs.isEmpty {
      // no more compilations are possible
      return nil
    }
    return getJobsFor(discoveredCompilationInputs: discoveredInputs)
 }

  /// After `job` finished find out which inputs must compiled that were not known to need compilation before
  private func collectInputsDiscovered(from job: Job)  -> [TypedVirtualPath] {
    Array(
      Set(
        job.primaryInputs.flatMap {
          input -> [TypedVirtualPath] in
          if let found = moduleDependencyGraph.findSourcesToCompileAfterCompiling(input) {
            return found
          }
          reportIncrementalDecision?("Failed to read some swiftdeps; compiling everything", input)
          return Array(skippedCompilationInputs)
        }
      )
    )
    .sorted {$0.file.name < $1.file.name}
  }

  /// Find the jobs that now must be run that were not originally known to be needed.
  private func getJobsFor(
    discoveredCompilationInputs inputs: [TypedVirtualPath]
  ) -> [Job] {
    inputs.flatMap { input -> [Job] in
      if let group = skippedCompileGroups.removeValue(forKey: input) {
        let primaryInputs = group.first!.primaryInputs
        assert(primaryInputs.count == 1)
        assert(primaryInputs[0] == input)
        reportIncrementalDecision?("Scheduling discovered", input)
        return group
      }
      else {
        reportIncrementalDecision?("Tried to schedule discovered input again", input)
        return []
      }
    }
  }
}
