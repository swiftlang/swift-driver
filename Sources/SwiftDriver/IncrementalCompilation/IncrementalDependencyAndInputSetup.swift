//===----- IncrementalDependencyAndInputSetup.swift - Incremental --------===//
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

import SwiftOptions
import class Dispatch.DispatchQueue

import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.FileSystem

// Initial incremental state computation
extension IncrementalCompilationState {
  static func computeIncrementalStateForPlanning(driver: inout Driver)
    throws -> IncrementalCompilationState.InitialStateForPlanning?
  {
    guard driver.shouldAttemptIncrementalCompilation else { return nil }

    let options = computeIncrementalOptions(driver: &driver)

    guard let outputFileMap = driver.outputFileMap else {
      driver.diagnosticEngine.emit(.warning_incremental_requires_output_file_map)
      return nil
    }

    let reporter: IncrementalCompilationState.Reporter?
    if options.contains(.showIncremental) {
      reporter = IncrementalCompilationState.Reporter(
        diagnosticEngine: driver.diagnosticEngine,
        outputFileMap: outputFileMap)
    } else {
      reporter = nil
    }

    guard let buildRecordInfo = driver.buildRecordInfo else {
      reporter?.reportDisablingIncrementalBuild("no build record path")
      return nil
    }

    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard
      let initialState =
        try IncrementalCompilationState
        .IncrementalDependencyAndInputSetup(
          options, outputFileMap,
          buildRecordInfo,
          reporter, driver.inputFiles,
          driver.fileSystem,
          driver.diagnosticEngine
        ).computeInitialStateForPlanning(driver: &driver)
    else {
      Self.removeDependencyGraphFile(driver)
      return nil
    }

    return initialState
  }

  // Extract options relevant to incremental builds
  static func computeIncrementalOptions(driver: inout Driver) -> IncrementalCompilationState.Options {
    var options: IncrementalCompilationState.Options = []
    if driver.parsedOptions.contains(.driverAlwaysRebuildDependents) {
      options.formUnion(.alwaysRebuildDependents)
    }
    if driver.parsedOptions.contains(.driverShowIncremental) || driver.showJobLifecycle {
      options.formUnion(.showIncremental)
    }
    let emitOpt = Option.driverEmitFineGrainedDependencyDotFileAfterEveryImport
    if driver.parsedOptions.contains(emitOpt) {
      options.formUnion(.emitDependencyDotFileAfterEveryImport)
    }
    let veriOpt = Option.driverVerifyFineGrainedDependencyGraphAfterEveryImport
    if driver.parsedOptions.contains(veriOpt) {
      options.formUnion(.verifyDependencyGraphAfterEveryImport)
    }
    if !driver.parsedOptions.hasFlag(positive: .enableIncrementalImports,
                                     negative: .disableIncrementalImports,
                                     default: true) {
        driver.diagnosticEngine.emit(.warning("ignoring obseleted option -disable-incremental-imports"))
    }
    if driver.parsedOptions.contains(.driverExplicitModuleBuild) {
      options.formUnion(.explicitModuleBuild)
    }
    return options
  }
}

/// Builds the `InitialState`
/// Also bundles up an bunch of configuration info
extension IncrementalCompilationState {

  /// A collection of immutable state that is handy to access.
  public struct IncrementalDependencyAndInputSetup: IncrementalCompilationSynchronizer {
    @_spi(Testing) public let outputFileMap: OutputFileMap
    @_spi(Testing) public let buildRecordInfo: BuildRecordInfo
    @_spi(Testing) public let reporter: IncrementalCompilationState.Reporter?
    @_spi(Testing) public let options: IncrementalCompilationState.Options
    @_spi(Testing) public let inputFiles: [TypedVirtualPath]
    @_spi(Testing) public let fileSystem: FileSystem

    /// The state managing incremental compilation gets mutated every time a compilation job completes.
    /// This queue ensures that the access and mutation of that state is thread-safe.
    @_spi(Testing) public let incrementalCompilationQueue: DispatchQueue

    @_spi(Testing) public let diagnosticEngine: DiagnosticsEngine

    /// Options, someday
    @_spi(Testing) public let dependencyDotFilesIncludeExternals: Bool = true
    @_spi(Testing) public let dependencyDotFilesIncludeAPINotes: Bool = false

    @_spi(Testing) public var explicitModuleBuild: Bool {
      options.contains(.explicitModuleBuild)
    }
    @_spi(Testing) public var alwaysRebuildDependents: Bool {
      options.contains(.alwaysRebuildDependents)
    }
    @_spi(Testing) public var verifyDependencyGraphAfterEveryImport: Bool {
      options.contains(.verifyDependencyGraphAfterEveryImport)
    }
    @_spi(Testing) public var emitDependencyDotFileAfterEveryImport: Bool {
      options.contains(.emitDependencyDotFileAfterEveryImport)
    }

    @_spi(Testing) public init(
      _ options: Options,
      _ outputFileMap: OutputFileMap,
      _ buildRecordInfo: BuildRecordInfo,
      _ reporter: IncrementalCompilationState.Reporter?,
      _ inputFiles: [TypedVirtualPath],
      _ fileSystem: FileSystem,
      _ diagnosticEngine: DiagnosticsEngine
    ) {
      self.outputFileMap = outputFileMap
      self.buildRecordInfo = buildRecordInfo
      self.reporter = reporter
      self.options = options
      self.inputFiles = inputFiles
      self.fileSystem = fileSystem
      assert(outputFileMap.onlySourceFilesHaveSwiftDeps())
      self.diagnosticEngine = diagnosticEngine
      self.incrementalCompilationQueue = DispatchQueue(
        label: "com.apple.swift-driver.incremental-compilation-state",
        qos: .userInteractive,
        attributes: .concurrent)
    }

    func computeInitialStateForPlanning(driver: inout Driver) throws -> InitialStateForPlanning? {
      guard let priors = computeGraphAndInputsInvalidatedByExternals() else {
        return nil
      }

      return InitialStateForPlanning(
        graph: priors.graph, buildRecordInfo: buildRecordInfo,
        inputsInvalidatedByExternals: priors.fileSet,
        incrementalOptions: options)
    }

    /// Is this source file part of this build?
    ///
    /// - Parameter sourceFile: the Swift source-code file in question
    /// - Returns: true iff this file was in the command-line invocation of the driver
    func isPartOfBuild(_ sourceFile: SwiftSourceFile) -> Bool {
      return self.inputFiles.contains(sourceFile.typedFile)
    }
  }
}


// MARK: - building/reading the ModuleDependencyGraph & scheduling externals for 1st wave
extension IncrementalCompilationState.IncrementalDependencyAndInputSetup {
  struct PriorState {
    var graph: ModuleDependencyGraph
    var fileSet: TransitivelyInvalidatedSwiftSourceFileSet
  }

  /// Builds or reads the graph
  /// Returns nil if some input (i.e. .swift file) has no corresponding swiftdeps file.
  /// Does not cope with disappeared inputs -- would be left in graph
  /// For inputs with swiftDeps in OFM, but no readable file, puts input in graph map, but no nodes in graph:
  ///   caller must ensure scheduling of those
  private func computeGraphAndInputsInvalidatedByExternals() -> PriorState? {
    return blockingConcurrentAccessOrMutation {
      return readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals()
    }
  }

  private func readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals() -> PriorState? {
    let dependencyGraphPath = buildRecordInfo.dependencyGraphPath
    let graphIfPresent: ModuleDependencyGraph?
    do {
      graphIfPresent = try ModuleDependencyGraph.read(from: dependencyGraphPath, info: self)
    }
    catch let ModuleDependencyGraph.ReadError.mismatchedSerializedGraphVersion(expected, read) {
      reporter?.report("Will not do cross-module incremental builds, wrong version of priors; expected \(expected) but read \(read) at '\(dependencyGraphPath)'")
      graphIfPresent = nil
    }
    catch {
      diagnosticEngine.emit(.warning("Could not read priors, will not do cross-module incremental builds: \(error.localizedDescription), at \(dependencyGraphPath)"),
                            location: nil)
      graphIfPresent = nil
    }
    guard let graph = graphIfPresent, self.validateBuildRecord(graph.buildRecord) != nil else {
      // Do not fall back to `buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals`
      // because it would be unsound to read a `swiftmodule` file with only a partial set of integrated `swiftdeps`.
      // A fingerprint change in such a `swiftmodule` would not be able to propagate and invalidate a use
      // in a as-yet-unread swiftdeps file.
      //
      // Instead, just compile everything. It's OK to be unsound then because every file will be compiled anyway.
      return buildEmptyGraphAndCompileEverything()
    }

    let sourceFiles = SourceFiles(
      inputFiles: inputFiles,
      buildRecord: graph.buildRecord)

    if !sourceFiles.disappeared.isEmpty {
      // Would have to cleanse nodes of disappeared inputs from graph
      // and would have to schedule files depending on defs from disappeared nodes
      if let reporter = reporter {
        reporter.report(
          "Incremental compilation has been disabled, "
          + "because the following inputs were used in the previous compilation but not in this one: "
          + sourceFiles.disappeared.map { $0.typedFile.file.basename }.joined(separator: ", "))
      }
      return buildEmptyGraphAndCompileEverything()
    }

    graph.dotFileWriter?.write(graph)

    // Any externals not already in graph must be additions which should trigger
    // recompilation. Thus, `ChangedOrAdded`.
    let nodesDirectlyInvalidatedByExternals =
      graph.collectNodesInvalidatedByChangedOrAddedExternals()
    // Wait till the last minute to do the transitive closure as an optimization.
    guard let inputsInvalidatedByExternals = graph.collectInputsInBuildUsingInvalidated(
      nodes: nodesDirectlyInvalidatedByExternals)
    else {
      return nil
    }
    return PriorState(graph: graph, fileSet: inputsInvalidatedByExternals)
  }

  private func buildEmptyGraphAndCompileEverything() -> PriorState {
    let buildRecord = BuildRecord(
      argsHash: self.buildRecordInfo.currentArgsHash,
      swiftVersion: self.buildRecordInfo.actualSwiftVersion,
      buildStartTime: .distantPast,
      buildEndTime: .distantFuture,
      inputInfos: [:])
    let graph = ModuleDependencyGraph.createForBuildingAfterEachCompilation(buildRecord, self)
    return PriorState(graph: graph, fileSet: TransitivelyInvalidatedSwiftSourceFileSet())
  }

  private func validateBuildRecord(
    _ outOfDateBuildRecord: BuildRecord
  ) -> BuildRecord? {
    let actualSwiftVersion = self.buildRecordInfo.actualSwiftVersion
    guard actualSwiftVersion == outOfDateBuildRecord.swiftVersion else {
      let why = "compiler version mismatch. Compiling with: \(actualSwiftVersion). Previously compiled with: \(outOfDateBuildRecord.swiftVersion)"
      // mimic legacy
      reporter?.reportIncrementalCompilationHasBeenDisabled("due to a " + why)
      reporter?.reportDisablingIncrementalBuild(why)
      return nil
    }
    guard outOfDateBuildRecord.argsHash == self.buildRecordInfo.currentArgsHash else {
      let why = "different arguments were passed to the compiler"
      // mimic legacy
      reporter?.reportIncrementalCompilationHasBeenDisabled("because " + why)
      reporter?.reportDisablingIncrementalBuild(why)
      return nil
    }
    return outOfDateBuildRecord
  }
}
