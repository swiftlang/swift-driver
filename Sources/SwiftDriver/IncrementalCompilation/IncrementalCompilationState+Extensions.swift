//===----------------------------------------------------------------------===//
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

import SwiftOptions
import protocol Foundation.LocalizedError
import class Foundation.JSONEncoder
import class Foundation.JSONSerialization

import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.FileSystem
import struct TSCBasic.Diagnostic
import struct TSCBasic.ProcessResult
import struct TSCBasic.ByteString

/// In a separate file to ensure that ``IncrementalCompilationState/protectedState``
/// can only be accessed via ``IncrementalCompilationState/blockingConcurrentMutation(_:)`` and
/// ``IncrementalCompilationState/blockingConcurrentAccessOrMutation(_:)``.

// MARK: - shorthand
extension IncrementalCompilationState {
  var fileSystem: FileSystem {info.fileSystem}
  /// If non-null outputs information for `-driver-show-incremental` for input path
  public var reporter: Reporter? { info.reporter }
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
    /// A set of inputs invalidated by external changes.
    let inputsInvalidatedByExternals: TransitivelyInvalidatedSwiftSourceFileSet
    /// Compiler options related to incremental builds.
    let incrementalOptions: IncrementalCompilationState.Options
  }
}

// MARK: - First Wave
extension IncrementalCompilationState {
  /// The first set of mandatory jobs for inputs which *must* be built
  struct FirstWave {
    /// The set of compile jobs we can definitely skip given the state of the
    /// incremental dependency graph and the status of the input files for this
    /// incremental build.
    let initiallySkippedCompileJobs: [TypedVirtualPath: Job]
    /// The non-compile jobs that can be skipped given the state of the
    /// incremental build.
    let skippedNonCompileJobs: [Job]
    /// All of the pre-compile or compilation job (groups) known to be required
    /// for the first wave to execute.
    /// The primaries could be other than .swift files, i.e. .sib
    let mandatoryJobsInOrder: [Job]
    /// The job after compilation that needs to run.
    let jobsAfterCompiles: [Job]
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
    return true
  }
}

fileprivate extension CompilerMode {
  var supportsIncrementalCompilation: Bool {
    switch self {
    case .standardCompile, .immediate, .repl, .batchCompile: return true
    case .singleCompile, .compilePCM, .dumpPCM, .intro: return false
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

  /// Needed for API compatibility, `result` may be ignored
  public func collectJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job
  ) throws -> [Job]? {
    try blockingConcurrentAccessOrMutationToProtectedState {
      try $0.collectBatchedJobsDiscoveredToBeNeededAfterFinishing(job: finishedJob)
    }
  }

  public func collectJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job, result: ProcessResult
  ) throws -> [Job]? {
    try collectJobsDiscoveredToBeNeededAfterFinishing(job: finishedJob)
  }

  public var skippedJobs: [Job] {
    blockingConcurrentMutationToProtectedState {
      $0.skippedJobs
    }
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
    guard .distantPast < oldestOutputModTime else {
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

  private func findOldestOutputForSkipping(postCompileJob: Job) -> (TypedVirtualPath, TimePoint)? {
    var oldestOutputAndModTime: (TypedVirtualPath, TimePoint)? = nil
    for output in postCompileJob.outputs {
      guard let outputModTime = try? self.fileSystem.lastModificationTime(for: output.file) else {
        return (output, .distantPast)
      }

      if let candidate = oldestOutputAndModTime {
        oldestOutputAndModTime = candidate.1 < outputModTime ? candidate : (output, outputModTime)
      } else {
        oldestOutputAndModTime = (output, outputModTime)
      }
    }
    return oldestOutputAndModTime
  }
  private func findAnInputOf( postCompileJob: Job, newerThan outputModTime: TimePoint) -> TypedVirtualPath? {
    postCompileJob.inputs.first { input in
      guard let modTime = try? self.fileSystem.lastModificationTime(for: input.file) else {
        return false
      }
      return outputModTime < modTime
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
      guard let output = try? outputFileMap.getOutput(inputFile: path.fileHandle, outputType: .object) else {
        report(message, pathIfGiven?.file)
        return
      }
      let compiling = " {compile: \(VirtualPath.lookup(output).basename) <= \(input.basename)}"
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(message) \(compiling)"))
    }

    public func report(_ message: String, _ ifh: SwiftSourceFile) {
      report(message, ifh.typedFile)
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

    /// Entry point for ``ExternalIntegrand``
    func report(_ message: String, _ integrand: ModuleDependencyGraph.ExternalIntegrand) {
      report(message, integrand.externalDependency)
    }

    func report(_ message: String, _ fed: FingerprintedExternalDependency) {
      report(message, fed.externalDependency)
    }

    func report(_ message: String, _ externalDependency: ExternalDependency) {
      report("\(message): \(externalDependency.shortDescription)")
    }

    func reportExplicitDependencyOutOfDate(_ moduleName: String,
                                           inputPath: String) {
      report("Dependency module \(moduleName) is older than input file \(inputPath)")
    }

    func reportExplicitDependencyWillBeReBuilt(_ moduleOutputPath: String,
                                               reason: String) {
      report("Dependency module '\(moduleOutputPath)' will be re-built: \(reason)")
    }

    func reportPriorExplicitDependencyStale(_ moduleOutputPath: String,
                                               reason: String) {
      report("Dependency module '\(moduleOutputPath)' info is stale: \(reason)")
    }

    func reportExplicitDependencyReBuildSet(_ modules: [ModuleDependencyId]) {
      report("Following explicit module dependencies will be re-built: [\(modules.map { $0.moduleNameForDiagnostic }.sorted().joined(separator: ", "))]")
    }

    func reportExplicitDependencyMissingFromCAS(_ moduleName: String) {
      report("Dependency module \(moduleName) is missing from CAS")
    }

    // Emits a remark indicating incremental compilation has been disabled.
    func reportDisablingIncrementalBuild(_ why: String) {
      report("Disabling incremental build: \(why)")
    }

    // Emits a remark indicating incremental compilation has been disabled.
    //
    // FIXME: This entrypoint exists for compatibility with the legacy driver.
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
    /// Enables additional handling of explicit module build artifacts:
    /// Additional reading and writing of the inter-module dependency graph.
    public static let explicitModuleBuild                    = Options(rawValue: 1 << 6)
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

  func writeDependencyGraph(
    to path: VirtualPath,
    _ buildRecord: BuildRecord
  ) throws {
    try blockingConcurrentAccessOrMutationToProtectedState {
      try $0.writeGraph(
        to: path,
        on: info.fileSystem,
        buildRecord: buildRecord)
    }
  }

  @_spi(Testing) public static func removeDependencyGraphFile(_ driver: Driver) {
    if let path = driver.buildRecordInfo?.dependencyGraphPath {
      try? driver.fileSystem.removeFileTree(path)
    }
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

/// Handy information about the source files in the current invocation
///
/// Usages of this structure are deprecated and should be removed on sight. For
/// large driver jobs, it is extremely expensive both in terms of memory and
/// compilation latency to instantiate as it rematerializes the entire input set
/// multiple times.
struct SourceFiles {
  /// The current (.swift) files in same order as the invocation
  let currentInOrder: [SwiftSourceFile]

  /// The set of current files (actually the handles)
  let currentSet: Set<SwiftSourceFile>

  /// Handles of the input files in the previous invocation
  private let previousSet: Set<SwiftSourceFile>

  /// The files that were in the previous but not in the current invocation
  let disappeared: [SwiftSourceFile]

  init(inputFiles: [TypedVirtualPath], buildRecord: BuildRecord) {
    self.currentInOrder = inputFiles.swiftSourceFiles
    self.currentSet = Set(currentInOrder)
    guard !buildRecord.inputInfos.isEmpty else {
      self.previousSet = Set()
      self.disappeared = []
      return
    }
    var previous = Set<SwiftSourceFile>()
    var disappeared = [SwiftSourceFile]()
    for prevPath in buildRecord.inputInfos.keys {
      let handle = SwiftSourceFile(prevPath)
      previous.insert(handle)
      if !currentSet.contains(handle) {
        disappeared.append(handle)
      }
    }
    self.previousSet = previous
    self.disappeared = disappeared.sorted {
      VirtualPath.lookup($0.fileHandle).name < VirtualPath.lookup($1.fileHandle).name}
  }

  func isANewInput(_ file: SwiftSourceFile) -> Bool {
    !previousSet.contains(file)
  }
}
