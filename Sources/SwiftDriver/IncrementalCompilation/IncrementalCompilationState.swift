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

/// An instance of `IncrementalCompilationState` encapsulates the data necessary
/// to make incremental build scheduling decisions.
///
/// The primary form of interaction with the incremental compilation state is
/// using it as an oracle to discover the jobs to execute as the incremental
/// build progresses. After a job completes, call
/// `IncrementalCompilationState.collectJobsDiscoveredToBeNeededAfterFinishing(job:)`
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

  /// The oracle for deciding what depends on what. Applies to this whole module.
  @_spi(Testing) public let moduleDependencyGraph: ModuleDependencyGraph

  /// If non-null outputs information for `-driver-show-incremental` for input path
  public let reporter: Reporter?

  /// All of the pre-compile or compilation job (groups) known to be required (i.e. in 1st wave).
  /// Already batched, and in order of input files.
  public let mandatoryJobsInOrder: [Job]

  /// Jobs to run *after* the last compile, for instance, link-editing.
  public let jobsAfterCompiles: [Job]

  /// Can compare input mod times against this.
  private let buildStartTime: Date

  /// In order to decide while postCompile jobs to run, need to compare their outputs against the build time
  private let buildEndTime: Date

  private let fileSystem: FileSystem

  /// A  high-priority confinement queue that must be used to protect the incremental compilation state.
  private let confinementQueue: DispatchQueue = DispatchQueue(label: "com.apple.swift-driver.incremental-compilation-state", qos: .userInteractive)

  /// Sadly, has to be `var` for formBatchedJobs
  ///
  /// After initialization, mutating accesses to the driver must be protected by
  /// the confinement queue.
  private var driver: Driver

  /// Keyed by primary input. As required compilations are discovered after the first wave, these shrink.
  ///
  /// This state is modified during the incremental build. All accesses must
  /// be protected by the confinement queue.
  private var skippedCompileGroups = [TypedVirtualPath: CompileJobGroup]()

  // MARK: - Creating IncrementalCompilationState
  /// Return nil if not compiling incrementally
  internal init(
    driver: inout Driver,
    jobsInPhases: JobsInPhases,
    initialState: InitialStateForPlanning
  ) throws {
    if initialState.incrementalOptions.contains(.showIncremental) {
      self.reporter = Reporter(diagnosticEngine: driver.diagnosticEngine,
                               outputFileMap: driver.outputFileMap)
    } else {
      self.reporter = nil
    }

    let enablingOrDisabling =
      initialState.incrementalOptions.contains(.enableCrossModuleIncrementalBuild)
      ? "Enabling"
      : "Disabling"
    reporter?.report(
      "\(enablingOrDisabling) incremental cross-module building")

    let firstWave =
      try FirstWaveComputer(initialState: initialState, jobsInPhases: jobsInPhases,
                            driver: driver, reporter: reporter).compute(batchJobFormer: &driver)

    self.skippedCompileGroups = firstWave.skippedCompileGroups
    self.mandatoryJobsInOrder = firstWave.mandatoryJobsInOrder
    self.jobsAfterCompiles = jobsInPhases.afterCompiles
    self.moduleDependencyGraph = initialState.graph
    self.buildStartTime = initialState.buildStartTime
    self.buildEndTime = initialState.buildEndTime
    self.fileSystem = driver.fileSystem
    self.driver = driver
  }
}

// MARK: - Initial State
extension IncrementalCompilationState {
  /// The initial state of an incremental compilation plan that consists of the module dependency graph
  /// and computes which inputs were invalidated by external changes.
  /// This set of incremental information is used during planning - job-generation, and is computed early.
  @_spi(Testing) public struct InitialStateForPlanning {
    /// The dependency graph.
    ///
    /// In a status quo build, the dependency graph is derived from the state
    /// of the build record, which points to all files built in the prior build.
    /// When this information is combined with the output file map, swiftdeps
    /// files can be located and loaded into the graph.
    ///
    /// In a cross-module build, the dependency graph is derived from prior
    /// state that is serialized alongside the build record.
    let graph: ModuleDependencyGraph
    /// Information about the last known compilation, incl. the location of build artifacts such as the dependency graph.
    let buildRecordInfo: BuildRecordInfo
    /// Record about existence and time of the last compile.
    let maybeBuildRecord: BuildRecord?
    /// A set of inputs invalidated by external chagnes.
    let inputsInvalidatedByExternals: TransitivelyInvalidatedInputSet
    /// Compiler options related to incremental builds.
    let incrementalOptions: IncrementalCompilationState.Options
    /// The last time this compilation was started. Used to compare against e.g. input file mod dates.
    let buildStartTime: Date
    /// The last time this compilation finished. Used to compare against output file mod dates
    let buildEndTime: Date
  }
}

// MARK: - First Wave
extension IncrementalCompilationState {
  /// The first set of mandatory jobs for inputs which *must* be built
  struct FirstWave {
    /// The set of compile jobs we can definitely skip given the state of the
    /// incremental dependency graph and the status of the input files for this
    /// incremental build.
    let skippedCompileGroups: [TypedVirtualPath: CompileJobGroup]
    /// All of the pre-compile or compilation job (groups) known to be required
    /// for the first wave to execute.
    let mandatoryJobsInOrder: [Job]
  }
}

extension Driver {
  /// Check various arguments to rule out incremental compilation if need be.
  static func shouldAttemptIncrementalCompilation(
    _ parsedOptions: inout ParsedOptions,
    diagnosticEngine: DiagnosticsEngine,
    compilerMode: CompilerMode
  ) -> Bool {
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
  static var warning_incremental_requires_output_file_map: Diagnostic.Message {
    .warning("ignoring -incremental (currently requires an output file map)")
  }
  static var warning_incremental_requires_build_record_entry: Diagnostic.Message {
    .warning(
      "ignoring -incremental; " +
        "output file map has no master dependencies entry (\"\(FileType.swiftDeps)\" under \"\")"
    )
  }

  static let remarkDisabled = Diagnostic.Message.remark_incremental_compilation_has_been_disabled

  static func remark_incremental_compilation_has_been_disabled(because why: String) -> Diagnostic.Message {
    return .remark("Incremental compilation has been disabled: \(why)")
  }

  static func remark_incremental_compilation(because why: String) -> Diagnostic.Message {
    .remark("Incremental compilation: \(why)")
  }
}

// MARK: - Scheduling the 2nd wave
extension IncrementalCompilationState {
  /// Remember a job (group) that is before a compile or a compile itself.
  /// `job` just finished. Update state, and return the skipped compile job (groups) that are now known to be needed.
  /// If no more compiles are needed, return nil.
  /// Careful: job may not be primary.
  public func collectJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job) throws -> [Job]? {
    return try self.confinementQueue.sync {
      // Find and deal with inputs that now need to be compiled
      let invalidatedInputs = collectInputsInvalidatedByRunning(finishedJob)
      assert(Set(invalidatedInputs).isDisjoint(with: finishedJob.primaryInputs),
             "Primaries should not overlap secondaries.")

      if let reporter = self.reporter {
        for input in invalidatedInputs {
          reporter.report(
            "Queuing because of dependencies discovered later:", input)
        }
      }
      return try getJobs(for: invalidatedInputs)
    }
  }

  /// Needed for API compatibility, `result` will be ignored
  public func collectJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job, result: ProcessResult
  ) throws -> [Job]? {
    try collectJobsDiscoveredToBeNeededAfterFinishing(job: finishedJob)
  }

  /// After `job` finished find out which inputs must compiled that were not known to need compilation before
  private func collectInputsInvalidatedByRunning(_ job: Job)-> Set<TypedVirtualPath> {
    dispatchPrecondition(condition: .onQueue(self.confinementQueue))
    guard job.kind == .compile else {
      return Set<TypedVirtualPath>()
    }
    return job.primaryInputs.reduce(into: Set()) { invalidatedInputs, primaryInput in
      invalidatedInputs.formUnion(collectInputsInvalidated(byCompiling: primaryInput))
    }
    .subtracting(job.primaryInputs) // have already compiled these
  }

  private func collectInputsInvalidated(
    byCompiling input: TypedVirtualPath
  ) -> TransitivelyInvalidatedInputSet {
    dispatchPrecondition(condition: .onQueue(self.confinementQueue))
    if let found = moduleDependencyGraph.collectInputsRequiringCompilation(byCompiling: input) {
      return found
    }
    self.reporter?.report(
      "Failed to read some dependencies source; compiling everything", input)
    return TransitivelyInvalidatedInputSet(skippedCompileGroups.keys)
  }

  /// Find the jobs that now must be run that were not originally known to be needed.
  private func getJobs(
    for invalidatedInputs: Set<TypedVirtualPath>
  ) throws -> [Job] {
    dispatchPrecondition(condition: .onQueue(self.confinementQueue))
    let unbatched = invalidatedInputs.flatMap { input -> [Job] in
      if let group = skippedCompileGroups.removeValue(forKey: input) {
        let primaryInputs = group.compileJob.primaryInputs
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
    return try driver.formBatchedJobs(unbatched, showJobLifecycle: driver.showJobLifecycle)
  }
}
// MARK: - Scheduling post-compile jobs
extension IncrementalCompilationState {
  /// Only used when no compilations have run; otherwise the caller assumes every post-compile
  /// job is needed, and saves the cost of the filesystem accesses by not calling this function.
  /// (For instance, if a build is cancelled in the merge-module phase, the compilations may be up-to-date
  /// but the postcompile-jobs (e.g. link-edit) may still need to be run.
  /// Since the use-case is rare, this function can afford to be expensive.
  /// Unlike the check in `IncrementalStateComputer.computeChangedInputs`,
  /// this function does not rely on build record information, which makes it more expensive but more robust.
  public func canSkip(postCompileJob: Job) -> Bool {
    func report(skipping: Bool, _ details: String, _ file: TypedVirtualPath? = nil) {
      reporter?.report(
        "\(skipping ? "S" : "Not s")kipping job: \(postCompileJob.descriptionForLifecycle); \(details)",
        file)
    }

    guard let (oldestOutput, oldestOutputModTime) =
            findOldestOutputForSkipping(postCompileJob: postCompileJob)
    else {
      report(skipping: false, "No outputs")
      return false
    }
    guard .distantPast < oldestOutputModTime
    else {
      report(skipping: false, "Missing output", oldestOutput)
      return false
    }
    if let newerInput = findAnInputOf(postCompileJob: postCompileJob,
                                      newerThan: oldestOutputModTime) {
      report(skipping: false, "Input \(newerInput.file.basename) is newer than output", oldestOutput)
      return false
    }
    report(skipping: true, "oldest output is current", oldestOutput)
    return true
  }

  private func findOldestOutputForSkipping(postCompileJob: Job) -> (TypedVirtualPath, Date)? {
    var oldestOutputAndModTime: (TypedVirtualPath, Date)? = nil
    for output in postCompileJob.outputs {
      guard let outputModTime = modTime(output)
      else {
        oldestOutputAndModTime = (output, .distantPast)
        break
      }
      oldestOutputAndModTime = oldestOutputAndModTime.map {
        $0.1 < outputModTime ? $0 : (output, outputModTime)
      }
      ?? (output, outputModTime)
    }
    return oldestOutputAndModTime
  }
  private func findAnInputOf( postCompileJob: Job, newerThan outputModTime: Date) -> TypedVirtualPath? {
    postCompileJob.inputs.first { input in
      outputModTime < (modTime(input) ?? .distantFuture)
    }
  }
  private func modTime(_ path: TypedVirtualPath) -> Date? {
    try? fileSystem.lastModificationTime(for: path.file)
  }
}

// MARK: - After the build
extension IncrementalCompilationState {
  var skippedCompilationInputs: Set<TypedVirtualPath> {
    return self.confinementQueue.sync {
      Set(skippedCompileGroups.keys)
    }
  }
  public var skippedJobs: [Job] {
    return self.confinementQueue.sync {
      skippedCompileGroups.values
        .sorted {$0.primaryInput.file.name < $1.primaryInput.file.name}
        .flatMap {$0.allJobs()}
    }
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
    public func report(_ message: String, _ pathIfGiven: TypedVirtualPath?) {
       guard let path = pathIfGiven,
            let outputFileMap = outputFileMap,
            let input = path.type == .swift ? path.file : outputFileMap.getInput(outputFile: path.file)
      else {
        report(message, pathIfGiven?.file)
        return
      }
      let output = outputFileMap.getOutput(inputFile: path.fileHandle, outputType: .object)
      let compiling = " {compile: \(VirtualPath.lookup(output).basename) <= \(input.basename)}"
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(message) \(compiling)"))
    }

    /// Entry point for a simple path, won't print the compile job, path could be anything.
    public func report(_ message: String, _ path: VirtualPath?) {
      guard let path = path
      else {
        report(message)
        diagnosticEngine.emit(.remark_incremental_compilation(because: message))
        return
      }
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(message) '\(path.name)'"))
    }

    /// Entry point if no path.
    public func report(_ message: String) {
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

    func reportInvalidated<Nodes: Sequence>(
      _ nodes: Nodes,
      by externalDependency: ExternalDependency,
      _ why: ExternalDependency.InvalidationReason
    )
    where Nodes.Element == ModuleDependencyGraph.Node
    {
      let whyString = why.description.capitalized
      let depString = externalDependency.shortDescription
      for node in nodes {
        report("\(whyString): \(depString) -> \(node)")
      }
    }
  }
}

// MARK: - Remarks

extension IncrementalCompilationState {
  /// Options that control the behavior of various aspects of the
  /// incremental build.
  public struct Options: OptionSet {
    public var rawValue: UInt8

    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    /// Be maximally conservative about rebuilding dependents of dirtied files
    /// during the incremental build. Dependent files are always scheduled to
    /// rebuild.
    public static let alwaysRebuildDependents                = Options(rawValue: 1 << 0)
    /// Print incremental build decisions as remarks.
    public static let showIncremental                        = Options(rawValue: 1 << 1)
    /// After integrating each source file dependency graph into the driver's
    /// module dependency graph, dump a dot file to the current working
    /// directory showing the state of the driver's dependency graph.
    ///
    /// FIXME: This option is not yet implemented.
    public static let emitDependencyDotFileAfterEveryImport  = Options(rawValue: 1 << 2)
    /// After integrating each source file dependency graph, verifies the
    /// integrity of the driver's dependency graph and aborts if any errors
    /// are detected.
    public static let verifyDependencyGraphAfterEveryImport  = Options(rawValue: 1 << 3)
    /// Enables the cross-module incremental build infrastructure.
    ///
    /// FIXME: This option is transitory. We intend to make this the
    /// default behavior. This option should flip to a "disable" bit after that.
    public static let enableCrossModuleIncrementalBuild      = Options(rawValue: 1 << 4)
    /// Enables an optimized form of start-up for the incremental build state
    /// that reads the dependency graph from a serialized format on disk instead
    /// of reading O(N) swiftdeps files.
    public static let readPriorsFromModuleDependencyGraph    = Options(rawValue: 1 << 5)
  }
}

// MARK: - Serialization

extension IncrementalCompilationState {
  enum WriteDependencyGraphError: LocalizedError {
    case noBuildRecordInfo,
         couldNotWrite(path: VirtualPath, error: Error)
    var errorDescription: String? {
      switch self {
      case .noBuildRecordInfo:
        return "No build record information"
      case let .couldNotWrite(path, error):
        return "Could not write to \(path), error: \(error.localizedDescription)"
      }
    }
  }
  @_spi(Testing) public func writeDependencyGraph() throws {
    // If the cross-module build is not enabled, the status quo dictates we
    // not emit this file.
    guard moduleDependencyGraph.info.isCrossModuleIncrementalBuildEnabled else {
      return
    }
    guard
      let recordInfo = self.driver.buildRecordInfo
    else {
      throw WriteDependencyGraphError.noBuildRecordInfo
    }
    try self.moduleDependencyGraph.write(to: recordInfo.dependencyGraphPath,
                                         on: self.driver.fileSystem,
                                         compilerVersion: recordInfo.actualSwiftVersion)
  }
}

// MARK: - OutputFileMap
extension OutputFileMap {
  func onlySourceFilesHaveSwiftDeps() -> Bool {
    let nonSourceFilesWithSwiftDeps = entries.compactMap { input, outputs in
      VirtualPath.lookup(input).extension != FileType.swift.rawValue &&
        input.description != "." &&
        outputs.keys.contains(.swiftDeps)
        ? input
        : nil
    }
    if let f = nonSourceFilesWithSwiftDeps.first {
      fatalError("nonSource \(f) has swiftDeps \(entries[f]![.swiftDeps]!)")
    }
    return nonSourceFilesWithSwiftDeps.isEmpty
  }
}

// MARK: SourceFiles
@_spi(Testing) public struct SourceFiles {
  let currentInOrder: [TypedVirtualPath]
  private let previous: Set<VirtualPath>
  let disappeared: [VirtualPath]

  init(inputFiles: [TypedVirtualPath], buildRecord: BuildRecord?) {
    self.currentInOrder = inputFiles.filter {$0.type == .swift}
    let currentSet = Set(currentInOrder.map {$0.file} )
    self.previous = buildRecord.map {
      Set($0.inputInfos.keys)
    } ?? Set()

    self.disappeared = previous.filter {!currentSet.contains($0)}
  }

  func isANewInput(_ file: VirtualPath) -> Bool {
    !previous.contains(file)
  }
}
