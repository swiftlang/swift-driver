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

import TSCBasic
import Foundation
import SwiftOptions

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
    let maybeBuildRecord =
      buildRecordInfo.populateOutOfDateBuildRecord(
        inputFiles: driver.inputFiles,
        reporter: reporter)

    guard
      let initialState =
        try IncrementalCompilationState
        .IncrementalDependencyAndInputSetup(
          options, outputFileMap,
          buildRecordInfo, maybeBuildRecord,
          reporter, driver.inputFiles,
          driver.fileSystem,
          driver.diagnosticEngine
        ).computeInitialStateForPlanning()
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
    if driver.parsedOptions.hasFlag(positive: .enableIncrementalImports,
                                  negative: .disableIncrementalImports,
                                  default: true) {
      options.formUnion(.enableCrossModuleIncrementalBuild)
      options.formUnion(.readPriorsFromModuleDependencyGraph)
    }
    return options
  }
}

/// Builds the `InitialState`
/// Also bundles up an bunch of configuration info
extension IncrementalCompilationState {

  /// A collection of immutable state that is handy to access.
  /// Make it a class so that anything that needs it can just keep a pointer around.
  public struct IncrementalDependencyAndInputSetup: IncrementalCompilationSynchronizer {
    @_spi(Testing) public let outputFileMap: OutputFileMap
    @_spi(Testing) public let buildRecordInfo: BuildRecordInfo
    @_spi(Testing) public let maybeBuildRecord: BuildRecord?
    @_spi(Testing) public let reporter: IncrementalCompilationState.Reporter?
    @_spi(Testing) public let options: IncrementalCompilationState.Options
    @_spi(Testing) public let inputFiles: [TypedVirtualPath]
    @_spi(Testing) public let fileSystem: FileSystem
    @_spi(Testing) public let sourceFiles: SourceFiles
    
    /// The state managing incremental compilation gets mutated every time a compilation job completes.
    /// This queue ensures that the access and mutation of that state is thread-safe.
    @_spi(Testing) public let incrementalCompilationQueue: DispatchQueue
    
    @_spi(Testing) public let diagnosticEngine: DiagnosticsEngine

    /// Options, someday
    @_spi(Testing) public let dependencyDotFilesIncludeExternals: Bool = true
    @_spi(Testing) public let dependencyDotFilesIncludeAPINotes: Bool = false

    @_spi(Testing) public let buildStartTime: Date
    @_spi(Testing) public let buildEndTime: Date

    // Do not try to reuse a graph from a different compilation, so check
    // the build record.
    @_spi(Testing) public var readPriorsFromModuleDependencyGraph: Bool {
      maybeBuildRecord != nil && options.contains(.readPriorsFromModuleDependencyGraph)
    }
    @_spi(Testing) public var alwaysRebuildDependents: Bool {
      options.contains(.alwaysRebuildDependents)
    }
    @_spi(Testing) public var isCrossModuleIncrementalBuildEnabled: Bool {
      options.contains(.enableCrossModuleIncrementalBuild)
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
      _ buildRecord: BuildRecord?,
      _ reporter: IncrementalCompilationState.Reporter?,
      _ inputFiles: [TypedVirtualPath],
      _ fileSystem: FileSystem,
      _ diagnosticEngine: DiagnosticsEngine
    ) {
      self.outputFileMap = outputFileMap
      self.buildRecordInfo = buildRecordInfo
      self.maybeBuildRecord = buildRecord
      self.reporter = reporter
      self.options = options
      self.inputFiles = inputFiles
      self.fileSystem = fileSystem
      assert(outputFileMap.onlySourceFilesHaveSwiftDeps())
      self.sourceFiles = SourceFiles(
        inputFiles: inputFiles,
        buildRecord: buildRecord)
      self.diagnosticEngine = diagnosticEngine
      self.buildStartTime = maybeBuildRecord?.buildStartTime ?? .distantPast
      self.buildEndTime = maybeBuildRecord?.buildEndTime ?? .distantFuture
      
      self.incrementalCompilationQueue = DispatchQueue(
        label: "com.apple.swift-driver.incremental-compilation-state",
        qos: .userInteractive,
        attributes: .concurrent)
    }

    func computeInitialStateForPlanning() throws -> InitialStateForPlanning? {
      guard sourceFiles.disappeared.isEmpty else {
        // Would have to cleanse nodes of disappeared inputs from graph
        // and would have to schedule files depending on defs from disappeared nodes
        if let reporter = reporter {
          reporter.report(
            "Incremental compilation has been disabled, "
            + "because the following inputs were used in the previous compilation but not in this one: "
            + sourceFiles.disappeared.map { $0.typedFile.file.basename }.joined(separator: ", "))
        }
        return nil
      }

      guard
        let (graph, inputsInvalidatedByExternals) =
          computeGraphAndInputsInvalidatedByExternals()
      else {
        return nil
      }

      return InitialStateForPlanning(
        graph: graph, buildRecordInfo: buildRecordInfo,
        maybeBuildRecord: maybeBuildRecord,
        inputsInvalidatedByExternals: inputsInvalidatedByExternals,
        incrementalOptions: options, buildStartTime: buildStartTime,
        buildEndTime: buildEndTime)
    }
    
    /// Is this source file part of this build?
    ///
    /// - Parameter sourceFile: the Swift source-code file in question
    /// - Returns: true iff this file was in the command-line invocation of the driver
    func isPartOfBuild(_ sourceFile: SwiftSourceFile) -> Bool {
      sourceFiles.currentSet.contains(sourceFile)
    }
  }
}
  

// MARK: - building/reading the ModuleDependencyGraph & scheduling externals for 1st wave
extension IncrementalCompilationState.IncrementalDependencyAndInputSetup {
  /// Builds or reads the graph
  /// Returns nil if some input (i.e. .swift file) has no corresponding swiftdeps file.
  /// Does not cope with disappeared inputs -- would be left in graph
  /// For inputs with swiftDeps in OFM, but no readable file, puts input in graph map, but no nodes in graph:
  ///   caller must ensure scheduling of those
  private func computeGraphAndInputsInvalidatedByExternals()
    -> (ModuleDependencyGraph, TransitivelyInvalidatedSwiftSourceFileSet)?
  {
    precondition(
      sourceFiles.disappeared.isEmpty,
      "Would have to remove nodes from the graph if reading prior")
    return blockingConcurrentAccessOrMutation {
      if readPriorsFromModuleDependencyGraph {
        return readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals()
      }
      // Every external is added, but don't want to compile an unchanged input that has an import
      // so just changed, not changedOrAdded.
      return buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals()
    }
  }

  private func readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals(
  ) -> (ModuleDependencyGraph, TransitivelyInvalidatedSwiftSourceFileSet)?
  {
    let dependencyGraphPath = buildRecordInfo.dependencyGraphPath
    let graphIfPresent: ModuleDependencyGraph?
    do {
      graphIfPresent = try ModuleDependencyGraph.read( from: dependencyGraphPath, info: self)
    }
    catch let ModuleDependencyGraph.ReadError.mismatchedSerializedGraphVersion(expected, read) {
      diagnosticEngine.emit(
        warning: "Will not do cross-module incremental builds, wrong version of priors; expected \(expected) but read \(read) at '\(dependencyGraphPath)'")
      graphIfPresent = nil
    }
    catch let ModuleDependencyGraph.ReadError.timeTravellingPriors(priorsModTime: priorsModTime,
                                                                   buildStartTime: buildStartTime,
                                                                   priorsTimeIntervalSinceStart: priorsTimeIntervalSinceStart) {
      diagnosticEngine.emit(
        warning: "Will not do cross-module incremental builds, priors saved at \(priorsModTime)), " +
        "but the previous build started at \(buildStartTime) [priorsTimeIntervalSinceStart: \(priorsTimeIntervalSinceStart)], at '\(dependencyGraphPath)'")
      graphIfPresent = nil
    }
    catch {
      diagnosticEngine.emit(
        warning: "Could not read priors, will not do cross-module incremental builds: \(error.localizedDescription), at \(dependencyGraphPath)")
      graphIfPresent = nil
    }
    guard let graph = graphIfPresent
    else {
      // Do not fall back to `buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals`
      // because it would be unsound to read a `swiftmodule` file with only a partial set of integrated `swiftdeps`.
      // A fingerprint change in such a `swiftmodule` would not be able to propagate and invalidate a use
      // in a as-yet-unread swiftdeps file.
      //
      // Instead, just compile everything. It's OK to be unsound then because every file will be compiled anyway.
      return bulidEmptyGraphAndCompileEverything()
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
    return (graph, inputsInvalidatedByExternals)
  }

  /// Builds a graph
  /// Returns nil if some input (i.e. .swift file) has no corresponding swiftdeps file.
  /// Does not cope with disappeared inputs
  /// For inputs with swiftDeps in OFM, but no readable file, puts input in graph map, but no nodes in graph:
  ///   caller must ensure scheduling of those
  /// For externalDependencies, puts then in graph.fingerprintedExternalDependencies, but otherwise
  /// does nothing special.
  private func buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals()
  -> (ModuleDependencyGraph, TransitivelyInvalidatedSwiftSourceFileSet)?
  {
    let graph = ModuleDependencyGraph.createForBuildingFromSwiftDeps(self)
    var inputsInvalidatedByChangedExternals = TransitivelyInvalidatedSwiftSourceFileSet()
    for input in sourceFiles.currentInOrder {
       guard let invalidatedInputs =
              graph.collectInputsRequiringCompilationFromExternalsFoundByCompiling(input: input)
      else {
        return nil
      }
      inputsInvalidatedByChangedExternals.formUnion(invalidatedInputs)
    }
    reporter?.report("Created dependency graph from swiftdeps files")
    return (graph, inputsInvalidatedByChangedExternals)
  }

  private func bulidEmptyGraphAndCompileEverything()
  -> (ModuleDependencyGraph, TransitivelyInvalidatedSwiftSourceFileSet) {
    let graph = ModuleDependencyGraph.createForBuildingAfterEachCompilation(self)
    return (graph, TransitivelyInvalidatedSwiftSourceFileSet())
  }
}
