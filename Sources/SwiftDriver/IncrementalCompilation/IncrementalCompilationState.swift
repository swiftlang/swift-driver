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
  /// Whether cross-module incrementality is enabled
  private let isCrossModuleIncrementalBuildEnabled: Bool

  /// The oracle for deciding what depends on what. Applies to this whole module.
  private let moduleDependencyGraph: ModuleDependencyGraph

  /// If non-null outputs information for `-driver-show-incremental` for input path
  private let reporter: Reporter?

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

  private let confinementQueue = DispatchQueue(label: "com.apple.swift-driver.IncrementalCompilationState")

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

    if driver.parsedOptions.hasArgument(.driverShowIncremental) || driver.showJobLifecycle {
      self.reporter = Reporter(diagnosticEngine: driver.diagnosticEngine,
                               outputFileMap: driver.outputFileMap)
    } else {
      self.reporter = nil
    }

    self.isCrossModuleIncrementalBuildEnabled =
      driver.parsedOptions.contains(.enableExperimentalCrossModuleIncrementalBuild)
    reporter?.report(
      "\(self.isCrossModuleIncrementalBuildEnabled ? "Enabling" : "Disabling") incremental cross-module building")


    guard let (outputFileMap, buildRecordInfo, outOfDateBuildRecord)
            = try driver.getBuildInfo(self.reporter)
    else {
      return nil
    }

    guard let (
      moduleDependencyGraph,
      inputsHavingMalformedDependencySources: inputsHavingMalformedDependencySources
    ) = Self.computeModuleDependencyGraph(
      buildRecordInfo,
      outOfDateBuildRecord,
      outputFileMap,
      &driver,
      self.reporter,
      isCrossModuleIncrementalBuildEnabled: isCrossModuleIncrementalBuildEnabled)
    else {
      return nil
    }

    (skippedCompileGroups: self.skippedCompileGroups,
     mandatoryJobsInOrder: self.mandatoryJobsInOrder) = try Self.computeInputsAndGroups(
      jobsInPhases,
      &driver,
      buildRecordInfo,
      outOfDateBuildRecord,
      inputsHavingMalformedDependencySources: inputsHavingMalformedDependencySources,
      moduleDependencyGraph,
      self.reporter)

    self.unfinishedJobs = Set(self.mandatoryJobsInOrder)
    self.jobsAfterCompiles = jobsInPhases.afterCompiles
    self.moduleDependencyGraph = moduleDependencyGraph
    self.driver = driver
  }


  private static func computeModuleDependencyGraph(
    _ buildRecordInfo: BuildRecordInfo,
    _ outOfDateBuildRecord: BuildRecord,
    _ outputFileMap: OutputFileMap,
    _ driver: inout Driver,
    _ reporter: Reporter?,
    isCrossModuleIncrementalBuildEnabled: Bool
  )
  -> (ModuleDependencyGraph,
      inputsHavingMalformedDependencySources: [TypedVirtualPath])?
  {
    let diagnosticEngine = driver.diagnosticEngine
    guard let (
      moduleDependencyGraph,
      inputsAndMalformedSwiftDeps: inputsAndMalformedSwiftDeps
    ) =
    ModuleDependencyGraph.buildInitialGraph(
      diagnosticEngine: diagnosticEngine,
      inputs: buildRecordInfo.compilationInputModificationDates.keys,
      previousInputs: outOfDateBuildRecord.allInputs,
      outputFileMap: outputFileMap,
      parsedOptions: &driver.parsedOptions,
      remarkDisabled: Diagnostic.Message.remark_incremental_compilation_has_been_disabled,
      reporter: reporter,
      fileSystem: driver.fileSystem,
      isCrossModuleIncrementalBuildEnabled: isCrossModuleIncrementalBuildEnabled
      )
    else {
      return nil
    }
    // Preserve legacy behavior,
    // but someday, just ensure inputsAndMalformedDependencySources are compiled
    if let badSwiftDeps = inputsAndMalformedSwiftDeps.first?.1 {
      diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "malformed dependencies file '\(badSwiftDeps)'")
      )
      return nil
    }
    let inputsHavingMalformedDependencySources = inputsAndMalformedSwiftDeps.map {$0.0}
    return (moduleDependencyGraph,
            inputsHavingMalformedDependencySources: inputsHavingMalformedDependencySources)
  }

  private static func computeInputsAndGroups(
    _ jobsInPhases: JobsInPhases,
    _ driver: inout Driver,
    _ buildRecordInfo: BuildRecordInfo,
    _ outOfDateBuildRecord: BuildRecord,
    inputsHavingMalformedDependencySources: [TypedVirtualPath],
    _ moduleDependencyGraph: ModuleDependencyGraph,
    _ reporter: Reporter?
  ) throws -> (skippedCompileGroups: [TypedVirtualPath: CompileJobGroup],
               mandatoryJobsInOrder: [Job])
  {
    let compileGroups =
      Dictionary(uniqueKeysWithValues:
                    jobsInPhases.compileGroups.map {($0.primaryInput, $0)} )

     let skippedInputs = Self.computeSkippedCompilationInputs(
      allGroups: jobsInPhases.compileGroups,
      fileSystem: driver.fileSystem,
      buildRecordInfo: buildRecordInfo,
      inputsHavingMalformedDependencySources: inputsHavingMalformedDependencySources,
      moduleDependencyGraph: moduleDependencyGraph,
      outOfDateBuildRecord: outOfDateBuildRecord,
      alwaysRebuildDependents: driver.parsedOptions.contains(.driverAlwaysRebuildDependents),
      reporter: reporter)

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

  /// Decide if an incremental compilation is possible, and return needed values if so.
  func getBuildInfo(
    _ reporter: IncrementalCompilationState.Reporter?
  ) throws -> (OutputFileMap, BuildRecordInfo, BuildRecord)? {
    guard let outputFileMap = outputFileMap
    else {
      diagnosticEngine.emit(.warning_incremental_requires_output_file_map)
      return nil
    }
    guard let buildRecordInfo = buildRecordInfo else {
      reporter?.reportDisablingIncrementalBuild("no build record path")
      return nil
    }
    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard let outOfDateBuildRecord = buildRecordInfo.populateOutOfDateBuildRecord(
            inputFiles: inputFiles, reporter: reporter)
    else {
      return nil
    }
    if let reporter = reporter {
      let missingInputs = Set(outOfDateBuildRecord.inputInfos.keys).subtracting(inputFiles.map {$0.file})
      guard missingInputs.isEmpty else {
        reporter.report(
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
    inputsHavingMalformedDependencySources: [TypedVirtualPath],
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    alwaysRebuildDependents: Bool,
    reporter: IncrementalCompilationState.Reporter?
  ) -> Set<TypedVirtualPath> {
    // Input == source file
    let changedInputs = Self.computeChangedInputs(
        groups: allGroups,
        buildRecordInfo: buildRecordInfo,
        moduleDependencyGraph: moduleDependencyGraph,
        outOfDateBuildRecord: outOfDateBuildRecord,
        fileSystem: fileSystem,
        reporter: reporter)

    let externallyChangedInputs = computeExternallyChangedInputs(
      forIncrementalExternalDependencies: false,
      buildTime: outOfDateBuildRecord.buildTime,
      fileSystem: fileSystem,
      moduleDependencyGraph: moduleDependencyGraph,
      reporter: moduleDependencyGraph.reporter)

    let incrementallyExternallyChangedInputs = computeExternallyChangedInputs(
      forIncrementalExternalDependencies: true,
      buildTime: outOfDateBuildRecord.buildTime,
      fileSystem: fileSystem,
      moduleDependencyGraph: moduleDependencyGraph,
      reporter: moduleDependencyGraph.reporter)

    let inputsMissingOutputs = allGroups.compactMap {
      $0.outputs.contains {(try? !fileSystem.exists($0.file)) ?? true}
        ? $0.primaryInput
        : nil
    }

    // Combine to obtain the inputs that definitely must be recompiled.
    let definitelyRequiredInputs =
      Set(changedInputs.map({ $0.filePath }) +
            externallyChangedInputs + incrementallyExternallyChangedInputs +
            inputsHavingMalformedDependencySources
            + inputsMissingOutputs)
    if let reporter = reporter {
      for scheduledInput in definitelyRequiredInputs.sorted(by: {$0.file.name < $1.file.name}) {
        reporter.report("Queuing (initial):", scheduledInput)
      }
    }

    // Sometimes, inputs run in the first wave that depend on the changed inputs for the
    // first wave, even though they may not require compilation.
    // Any such inputs missed, will be found by the rereading of swiftDeps
    // as each first wave job finished.
    let speculativeInputs = computeSpeculativeInputs(
      changedInputs: changedInputs,
      externalDependents: externallyChangedInputs,
      inputsMissingOutputs: Set(inputsMissingOutputs),
      moduleDependencyGraph: moduleDependencyGraph,
      alwaysRebuildDependents: alwaysRebuildDependents,
      reporter: reporter)
      .subtracting(definitelyRequiredInputs)

    if let reporter = reporter {
      for dependent in speculativeInputs.sorted(by: {$0.file.name < $1.file.name}) {
        reporter.report("Queuing because of the initial set:", dependent)
      }
    }
    let immediatelyCompiledInputs = definitelyRequiredInputs.union(speculativeInputs)

    let skippedInputs = Set(buildRecordInfo.compilationInputModificationDates.keys)
      .subtracting(immediatelyCompiledInputs)
    if let reporter = reporter {
      for skippedInput in skippedInputs.sorted(by: {$0.file.name < $1.file.name})  {
        reporter.report("Skipping input:", skippedInput)
      }
    }
    return skippedInputs
  }
}

extension IncrementalCompilationState {
  /// Encapsulates information about an input the driver has determined has
  /// changed in a way that requires an incremental rebuild.
  struct ChangedInput {
    /// The path to the input file.
    let filePath: TypedVirtualPath
    /// The status of the input file.
    let status: InputInfo.Status
    /// If `true`, the modification time of this input matches the modification
    /// time recorded from the prior build in the build record.
    let datesMatch: Bool
  }

  /// Find the inputs that have changed since last compilation, or were marked as needed a build
  private static func computeChangedInputs(
    groups: [CompileJobGroup],
    buildRecordInfo: BuildRecordInfo,
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    fileSystem: FileSystem,
    reporter: IncrementalCompilationState.Reporter?
  ) -> [ChangedInput] {
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
        reporter?.report("May skip current input:", input)
        return nil

      case .upToDate:
        reporter?.report("Scheduing changed input", input)
      case .newlyAdded:
        reporter?.report("Scheduling new", input)
      case .needsCascadingBuild:
        reporter?.report("Scheduling cascading build", input)
      case .needsNonCascadingBuild:
        reporter?.report("Scheduling noncascading build", input)
      }
      return ChangedInput(filePath: input,
                          status: previousCompilationStatus,
                          datesMatch: datesMatch)
    }
  }

  /// Any files dependent on modified files from other modules must be compiled, too.
  private static func computeExternallyChangedInputs(
    forIncrementalExternalDependencies: Bool,
    buildTime: Date,
    fileSystem: FileSystem,
    moduleDependencyGraph: ModuleDependencyGraph,
    reporter: IncrementalCompilationState.Reporter?
 ) -> [TypedVirtualPath] {
    var externalDependencySources = Set<ModuleDependencyGraph.DependencySource>()
    let extDeps = forIncrementalExternalDependencies
      ? moduleDependencyGraph.incrementalExternalDependencies
      : moduleDependencyGraph.externalDependencies
    for extDep in extDeps {
      let extModTime = extDep.file.flatMap {try? fileSystem.getFileInfo($0).modTime}
        ?? Date.distantFuture
      if extModTime >= buildTime {
        for dependent in moduleDependencyGraph.untracedDependents(of: extDep, isIncremental: forIncrementalExternalDependencies) {
          guard let dependencySource = dependent.dependencySource else {
            fatalError("Dependent \(dependent) does not have dependencies file!")
          }
          reporter?.report(
            "Queuing because of \(forIncrementalExternalDependencies ? "incremental " : "")external dependency on newer \(extDep.file?.basename ?? "extDep?")",
            dependencySource.typedFile)
          externalDependencySources.insert(dependencySource)
        }
      }
    }
    return externalDependencySources.compactMap {
      moduleDependencyGraph.inputDependencySourceMap[$0]
    }
  }

  /// Returns the cascaded files to compile in the first wave, even though it may not be need.
  /// The needs[Non}CascadingBuild stuff was cargo-culted from the legacy driver.
  /// TODO: something better, e.g. return nothing here, but process changed dependencySource
  /// before the whole frontend job finished.
  private static func computeSpeculativeInputs(
    changedInputs: [ChangedInput],
    externalDependents: [TypedVirtualPath],
    inputsMissingOutputs: Set<TypedVirtualPath>,
    moduleDependencyGraph: ModuleDependencyGraph,
    alwaysRebuildDependents: Bool,
    reporter: IncrementalCompilationState.Reporter?
  ) -> Set<TypedVirtualPath> {
    let cascadingChangedInputs = Self.computeCascadingChangedInputs(
      from: changedInputs,
      inputsMissingOutputs: inputsMissingOutputs,
      alwaysRebuildDependents: alwaysRebuildDependents,
      reporter: reporter)
    let cascadingExternalDependents = alwaysRebuildDependents ? externalDependents : []
    // Collect the dependent files to speculatively schedule
    var dependentFiles = Set<TypedVirtualPath>()
    let cascadingFileSet = Set(cascadingChangedInputs).union(cascadingExternalDependents)
    for cascadingFile in cascadingFileSet {
       let dependentsOfOneFile = moduleDependencyGraph
        .findDependentSourceFiles(of: cascadingFile)
      for dep in dependentsOfOneFile where !cascadingFileSet.contains(dep) {
        if dependentFiles.insert(dep).0 {
          reporter?.report(
            "Immediately scheduling dependent on \(cascadingFile.file.basename)", dep)
        }
      }
    }
    return dependentFiles
  }

  // Collect the files that will be compiled whose dependents should be schedule
  private static func computeCascadingChangedInputs(
    from changedInputs: [ChangedInput],
    inputsMissingOutputs: Set<TypedVirtualPath>,
    alwaysRebuildDependents: Bool,
    reporter: IncrementalCompilationState.Reporter?
  ) -> [TypedVirtualPath] {
    changedInputs.compactMap { changedInput in
      let inputIsUpToDate =
        changedInput.datesMatch && !inputsMissingOutputs.contains(changedInput.filePath)
      let basename = changedInput.filePath.file.basename

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
          return changedInput.filePath
        }
      }

      switch changedInput.status {
      case .needsCascadingBuild:
        reporter?.report(
          "scheduling dependents of \(basename); needed cascading build")
        return changedInput.filePath
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

// MARK: - Scheduling
extension IncrementalCompilationState {
  /// Remember a job (group) that is before a compile or a compile itself.
  /// `job` just finished. Update state, and return the skipped compile job (groups) that are now known to be needed.
  /// If no more compiles are needed, return nil.
  /// Careful: job may not be primary.

  public func getJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job, result: ProcessResult
   ) throws -> [Job]? {
    return try confinementQueue.sync {
      unfinishedJobs.remove(finishedJob)

      guard case .terminated = result.exitStatus else {
        return []
      }

      // Find and deal with inputs that how need to be compiled
      let discoveredInputs = collectInputsDiscovered(from: finishedJob)
      assert(Set(discoveredInputs).isDisjoint(with: finishedJob.primaryInputs),
             "Primaries should not overlap secondaries.")

      if let reporter = self.reporter {
        for input in discoveredInputs {
          reporter.report(
            "Queuing because of dependencies discovered later:", input)
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
          if let found = moduleDependencyGraph.findSourcesToCompileAfterCompiling(input, on: self.driver.fileSystem) {
            return found
          }
          self.reporter?.report(
            "Failed to read some dependencies source; compiling everything", input)
          return Array(skippedCompileGroups.keys)
        }
      )
      .subtracting(job.primaryInputs) // have already compiled these
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
        self.reporter?.report("Scheduling discovered", input)
        return group.allJobs()
      }
      else {
        self.reporter?.report("Tried to schedule discovered input again", input)
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
  public var skippedJobs: [Job] {
    skippedCompileGroups.values
      .sorted {$0.primaryInput.file.name < $1.primaryInput.file.name}
      .flatMap {$0.allJobs()}
  }
}

// MARK: - Remarks

extension IncrementalCompilationState {
  /// A type that manages the reporting of remarks about the state of the
  /// incremental build.
  public struct Reporter {
    let diagnosticEngine: DiagnosticsEngine
    let outputFileMap: OutputFileMap?

    /// Report a remark with the given message.
    ///
    /// The `path` parameter is used specifically for reporting the state of
    /// compile jobs that are transiting through the incremental build pipeline.
    /// If provided, and valid entries in the output file map are provided,
    /// the reporter will format a message of the form
    ///
    /// ```
    /// <message> {compile: <output> <= <input>}
    /// ```
    ///
    /// Which mirrors the behavior of the legacy driver.
    ///
    /// - Parameters:
    ///   - message: The message to emit in the remark.
    ///   - path: If non-nil, the path of some file. If the output for an incremental job, will print out the
    ///           source and object files.
    func report(_ message: String, _ pathIfGiven: TypedVirtualPath?) {
       guard let path = pathIfGiven,
            let outputFileMap = outputFileMap,
            let input = path.type == .swift ? path.file : outputFileMap.getInput(outputFile: path.file)
      else {
        report(message, pathIfGiven?.file)
        return
      }
      let output = outputFileMap.getOutput(inputFile: path.file, outputType: .object)
      let compiling = " {compile: \(output.basename) <= \(input.basename)}"
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(message) \(compiling)"))
    }

    /// Entry point for a simple path, won't print the compile job, path could be anything.
    func report(_ message: String, _ path: VirtualPath?) {
      guard let path = path
      else {
        report(message)
        diagnosticEngine.emit(.remark_incremental_compilation(because: message))
        return
      }
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(message) '\(path.name)'"))
    }

    /// Entry point if no path.
    func report(_ message: String) {
      diagnosticEngine.emit(.remark_incremental_compilation(because: message))
    }


    // Emits a remark indicating incremental compilation has been disabled.
    func reportDisablingIncrementalBuild(_ why: String) {
      report("Disabling incremental build: \(why)")
    }

    // Emits a remark indicating incremental compilation has been disabled.
    //
    // FIXME: This entrypoint exists for compatiblity with the legacy driver.
    // This message is not necessary, and we should migrate the tests.
    func reportIncrementalCompilationHasBeenDisabled(_ why: String) {
      report("Incremental compilation has been disabled, \(why)")
    }
  }
}
