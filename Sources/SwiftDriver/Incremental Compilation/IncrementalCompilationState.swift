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

  /// All of the pre-compile or compilation job (groups) known to be required (i.e. in 1st wave).
  /// Already batched, and in order of input files.
  public let mandatoryJobsInOrder: [Job]

  /// Sadly, has to be `var` for formBatchedJobs
  private var driver: Driver

  /// Track required jobs that haven't finished so the build record can record the corresponding
  /// input statuses.
  private var unfinishedJobs: Set<Job>

  /// Keyed by primary input. As required compilations are discovered after the first wave, these shrink.
  private var skippedCompileGroups = [TypedVirtualPath: CompileJobGroup]()

  /// Jobs to run *after* the last compile, for instance, link-editing.
  public let jobsAfterCompiles: [Job]

  /// A check for reentrancy.
  private var amHandlingJobCompletion = false

// MARK: - Creating IncrementalCompilationState if possible
  /// Return nil if not compiling incrementally
  init?(
    driver: inout Driver,
    jobsInPhases: JobsInPhases
  ) throws {
    guard driver.shouldAttemptIncrementalCompilation()
    else {
      return nil
    }

    let reportIncrementalDecision = driver.computeReportIncrementalDecision()

    guard let (outputFileMap, buildRecordInfo, outOfDateBuildRecord)
            = try driver.getBuildInfo(
              reportIncrementalDecision.map {
                report in {report($0, nil)}
              }
            )
    else {
      return nil
    }

    guard let (moduleDependencyGraph,
               inputsHavingMalformedSwiftDeps: inputsHavingMalformedSwiftDeps) =
            Self.computeModuleDependencyGraph(
              buildRecordInfo,
              outOfDateBuildRecord,
              outputFileMap,
              &driver,
              reportIncrementalDecision)
    else {
      return nil
    }

    (skippedCompileGroups: self.skippedCompileGroups,
     mandatoryJobsInOrder: self.mandatoryJobsInOrder) = try Self.computeInputsAndGroups(
      jobsInPhases,
      &driver,
      buildRecordInfo,
      outOfDateBuildRecord,
      inputsHavingMalformedSwiftDeps: inputsHavingMalformedSwiftDeps,
      moduleDependencyGraph,
      reportIncrementalDecision)

    self.unfinishedJobs = Set(self.mandatoryJobsInOrder)
    self.jobsAfterCompiles = jobsInPhases.afterCompiles
    self.moduleDependencyGraph = moduleDependencyGraph
    self.reportIncrementalDecision = reportIncrementalDecision
    self.driver = driver
  }


  private static func computeModuleDependencyGraph(
    _ buildRecordInfo: BuildRecordInfo,
    _ outOfDateBuildRecord: BuildRecord,
    _ outputFileMap: OutputFileMap,
    _ driver: inout Driver,
    _ reportIncrementalDecision: ( (String, TypedVirtualPath?) -> Void )?
  )
  -> (ModuleDependencyGraph, inputsHavingMalformedSwiftDeps: [TypedVirtualPath])?
  {
    let diagnosticEngine = driver.diagnosticEngine
    guard let (moduleDependencyGraph, inputsWithMalformedSwiftDeps: inputsWithMalformedSwiftDeps) =
            ModuleDependencyGraph.buildInitialGraph(
              diagnosticEngine: diagnosticEngine,
              inputs: buildRecordInfo.compilationInputModificationDates.keys,
              previousInputs: outOfDateBuildRecord.allInputs,
              outputFileMap: outputFileMap,
              parsedOptions: &driver.parsedOptions,
              remarkDisabled: Diagnostic.Message.remark_incremental_compilation_has_been_disabled,
              reportIncrementalDecision: reportIncrementalDecision)
    else {
      return nil
    }
    // Preserve legacy behavior,
    // but someday, just ensure inputsWithUnreadableSwiftDeps are compiled
    if let badSwiftDeps = inputsWithMalformedSwiftDeps.first?.1 {
      diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "malformed swift dependencies file '\(badSwiftDeps)'")
      )
      return nil
    }
    let inputsHavingMalformedSwiftDeps = inputsWithMalformedSwiftDeps.map {$0.0}
    return (moduleDependencyGraph,
            inputsHavingMalformedSwiftDeps: inputsHavingMalformedSwiftDeps)
  }

  private static func computeInputsAndGroups(
    _ jobsInPhases: JobsInPhases,
    _ driver: inout Driver,
    _ buildRecordInfo: BuildRecordInfo,
    _ outOfDateBuildRecord: BuildRecord,
    inputsHavingMalformedSwiftDeps: [TypedVirtualPath],
    _ moduleDependencyGraph: ModuleDependencyGraph,
    _ reportIncrementalDecision: ( (String, TypedVirtualPath?) -> Void )?
  )
  throws -> (skippedCompileGroups: [TypedVirtualPath: CompileJobGroup],
      mandatoryJobsInOrder: [Job]
      )
  {
    let compileGroups =
      Dictionary( uniqueKeysWithValues:
                    jobsInPhases.compileGroups.map {($0.primaryInput, $0)} )

     let skippedInputs = Self.computeSkippedCompilationInputs(
      allGroups: jobsInPhases.compileGroups,
      fileSystem: driver.fileSystem,
      buildRecordInfo: buildRecordInfo,
      inputsHavingMalformedSwiftDeps: inputsHavingMalformedSwiftDeps,
      moduleDependencyGraph: moduleDependencyGraph,
      outOfDateBuildRecord: outOfDateBuildRecord,
      alwaysRebuildDependents: driver.parsedOptions.contains(.driverAlwaysRebuildDependents),
      reportIncrementalDecision: reportIncrementalDecision)

    let skippedCompileGroups = compileGroups.filter {skippedInputs.contains($0.key)}

    let mandatoryCompileGroupsInOrder = driver.inputFiles.compactMap {
      input -> CompileJobGroup? in
      skippedInputs.contains(input)
        ? nil
        : compileGroups[input]
    }

    let mandatoryJobsInOrder = try
      jobsInPhases.beforeCompiles +
      driver.formBatchedJobs(
        mandatoryCompileGroupsInOrder.flatMap {$0.allJobs()},
        showJobLifecycle: driver.showJobLifecycle)

    return (skippedCompileGroups: skippedCompileGroups,
            mandatoryJobsInOrder: mandatoryJobsInOrder)
  }
}

fileprivate extension Driver {
  /// Check various arguments to rule out incremental compilation if need be.
  mutating func shouldAttemptIncrementalCompilation() -> Bool {
    guard parsedOptions.hasArgument(.incremental) else {
      return false
    }
    guard compilerMode.supportsIncrementalCompilation else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "it is not compatible with \(compilerMode)"))
      return false
    }
    guard !parsedOptions.hasArgument(.embedBitcode) else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "is not currently compatible with embedding LLVM IR bitcode"))
      return false
    }
    return true
  }


  mutating func computeReportIncrementalDecision(
  ) -> ( (String, TypedVirtualPath?) -> Void )?
  {
    guard parsedOptions.hasArgument(.driverShowIncremental) || showJobLifecycle
    else {
      return nil
    }
     return {  [diagnosticEngine, outputFileMap] (s: String, path: TypedVirtualPath?) in
      guard let outputFileMap = outputFileMap,
            let path = path,
            let input = path.type == .swift ? path.file : outputFileMap.getInput(outputFile: path.file)
      else {
        diagnosticEngine.emit(.remark_incremental_compilation(because: s))
        return
      }
      let output = outputFileMap.getOutput(inputFile: path.file, outputType: .object)
      let compiling = " {compile: \(output.basename) <= \(input.basename)}"
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(s) \(compiling)"))
    }
  }


  /// Decide if an incremental compilation is possible, and return needed values if so.
  func getBuildInfo(
    _ reportIncrementalDecision: ( (String) -> Void)? )
  throws -> ( OutputFileMap, BuildRecordInfo, BuildRecord )?
  {
    guard let outputFileMap = outputFileMap
    else {
      diagnosticEngine.emit(.warning_incremental_requires_output_file_map)
      return nil
    }
    func reportDisablingIncrementalBuild(_ why: String) {
      guard let report = reportIncrementalDecision else { return }
      report("Disabling incremental build: \(why)")
    }
    func reportIncrementalCompilationHasBeenDisabled(_ why: String) {
      guard let report = reportIncrementalDecision else { return }
      report("Incremental compilation has been disabled, \(why)")
    }
    guard let buildRecordInfo = buildRecordInfo else {
      reportDisablingIncrementalBuild("no build record path")
      return nil
    }
    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard  let outOfDateBuildRecord = buildRecordInfo.populateOutOfDateBuildRecord(
      inputFiles: inputFiles,
      reportIncrementalDecision: reportIncrementalDecision ?? {_ in },
      reportDisablingIncrementalBuild: reportDisablingIncrementalBuild,
      reportIncrementalCompilationHasBeenDisabled: reportIncrementalCompilationHasBeenDisabled
    )
    else {
      return nil
    }
    if let report = reportIncrementalDecision {
      let missingInputs = Set(outOfDateBuildRecord.inputInfos.keys).subtracting(inputFiles.map {$0.file})
      guard missingInputs.isEmpty else {
        report(
          "Incremental compilation has been disabled, " +
          " because  the following inputs were used in the previous compilation but not in this one: "
            + missingInputs.map {$0.basename} .joined(separator: ", "))
        return nil
      }
    }
    return (outputFileMap, buildRecordInfo, outOfDateBuildRecord)
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
  fileprivate static func remark_disabling_incremental_build(because why: String) -> Diagnostic.Message {
    return .remark("Disabling incremental build: \(why)")
  }
  fileprivate static func remark_incremental_compilation_has_been_disabled(because why: String) -> Diagnostic.Message {
    return .remark("Incremental compilation has been disabled: \(why)")
  }

  fileprivate static func remark_incremental_compilation(because why: String) -> Diagnostic.Message {
    .remark("Incremental compilation: \(why)")
  }
}


// MARK: - Scheduling the first wave, i.e. the mandatory pre- and compile jobs

extension IncrementalCompilationState {

  /// Figure out which compilation inputs are *not* mandatory
  private static func computeSkippedCompilationInputs(
    allGroups: [CompileJobGroup],
    fileSystem: FileSystem,
    buildRecordInfo: BuildRecordInfo,
    inputsHavingMalformedSwiftDeps: [TypedVirtualPath],
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    alwaysRebuildDependents: Bool,
    reportIncrementalDecision: ((String, TypedVirtualPath?) -> Void)?
  ) -> Set<TypedVirtualPath> {
    let changedInputs: [(TypedVirtualPath, InputInfo.Status)] =
      computeChangedInputs(
        groups: allGroups,
        buildRecordInfo: buildRecordInfo,
        moduleDependencyGraph: moduleDependencyGraph,
        outOfDateBuildRecord: outOfDateBuildRecord,
        fileSystem: fileSystem,
        reportIncrementalDecision: reportIncrementalDecision)

    let externalDependents = computeExternallyDependentInputs(
      buildTime: outOfDateBuildRecord.buildTime,
      fileSystem: fileSystem,
      moduleDependencyGraph: moduleDependencyGraph,
      reportIncrementalDecision: reportIncrementalDecision)

    let inputsMissingOutputs = allGroups.compactMap {
      $0.outputs.contains {(try? !fileSystem.exists($0.file)) ?? true}
        ? $0.primaryInput
        : nil
    }

    // Combine to obtain the inputs that definitely must be recompiled.
    let definitelyRequiredInputs =
      Set(changedInputs.map {$0.0} + externalDependents +
            inputsHavingMalformedSwiftDeps
            + inputsMissingOutputs)
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
        report("Queuing because of the initial set:", dependent)
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
    groups: [CompileJobGroup],
    buildRecordInfo: BuildRecordInfo,
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    fileSystem: FileSystem,
    reportIncrementalDecision: ((String, TypedVirtualPath?) -> Void)?
   ) -> [(TypedVirtualPath, InputInfo.Status)] {
    groups.compactMap { group in
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
  /// `job` just finished. Update state, and return the skipped compile job (groups) that are now known to be needed.
  /// If no more compiles are needed, return nil.
  /// Careful: job may not be primary.
  public func getJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job, result: ProcessResult
   ) throws -> [Job]? {
    defer {
      amHandlingJobCompletion = false
    }
    assert(!amHandlingJobCompletion, "was reentered, need to synchronize")
    amHandlingJobCompletion = true

    unfinishedJobs.remove(finishedJob)

    guard case .terminated = result.exitStatus else {
      return []
    }

    // Find and deal with inputs that how need to be compiled
    let discoveredInputs = collectInputsDiscovered(from: finishedJob)
    assert(Set(discoveredInputs).isDisjoint(with: finishedJob.primaryInputs),
           "Primaries should not overlap secondaries.")

    if let report = reportIncrementalDecision {
      for input in discoveredInputs {
        report("Queuing because of dependencies discovered later:", input)
      }
    }
    let newJobs = try getJobsFor(discoveredCompilationInputs: discoveredInputs)
    unfinishedJobs.formUnion(newJobs)
    if unfinishedJobs.isEmpty {
      // no more compilations are possible
      return nil
    }
    return newJobs
 }

  /// After `job` finished find out which inputs must compiled that were not known to need compilation before
  private func collectInputsDiscovered(from job: Job)  -> [TypedVirtualPath] {
    guard job.kind == .compile else {
      return []
    }
    return Array(
      Set(
        job.primaryInputs.flatMap {
          input -> [TypedVirtualPath] in
          if let found = moduleDependencyGraph.findSourcesToCompileAfterCompiling(input) {
            return found
          }
          reportIncrementalDecision?("Failed to read some swiftdeps; compiling everything", input)
          return Array(skippedCompileGroups.keys)
        }
      )
    )
    .sorted {$0.file.name < $1.file.name}
  }

  /// Find the jobs that now must be run that were not originally known to be needed.
  private func getJobsFor(
    discoveredCompilationInputs inputs: [TypedVirtualPath]
  ) throws -> [Job] {
    let unbatched = inputs.flatMap { input -> [Job] in
      if let group = skippedCompileGroups.removeValue(forKey: input) {
        let primaryInputs = group.compileJob.primaryInputs
        assert(primaryInputs.count == 1)
        assert(primaryInputs[0] == input)
        reportIncrementalDecision?("Scheduling discovered", input)
        return group.allJobs()
      }
      else {
        reportIncrementalDecision?("Tried to schedule discovered input again", input)
        return []
      }
    }
    return try driver.formBatchedJobs(unbatched, showJobLifecycle: driver.showJobLifecycle)
  }
}

// MARK: - After the build
extension IncrementalCompilationState {
  var skippedCompilationInputs: Set<TypedVirtualPath> {
    Set(skippedCompileGroups.keys)
  }
}

