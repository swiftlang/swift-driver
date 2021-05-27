import Foundation
import SwiftOptions
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
        ).compute()
    else {
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

  public struct IncrementalDependencyAndInputSetup {
    @_spi(Testing) public let outputFileMap: OutputFileMap
    @_spi(Testing) public let buildRecordInfo: BuildRecordInfo
    @_spi(Testing) public let maybeBuildRecord: BuildRecord?
    @_spi(Testing) public let reporter: IncrementalCompilationState.Reporter?
    @_spi(Testing) public let options: IncrementalCompilationState.Options
    @_spi(Testing) public let inputFiles: [TypedVirtualPath]
    @_spi(Testing) public let fileSystem: FileSystem
    @_spi(Testing) public let sourceFiles: SourceFiles
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
    }

    func compute() throws -> InitialStateForPlanning? {
      guard sourceFiles.disappeared.isEmpty else {
        // Would have to cleanse nodes of disappeared inputs from graph
        // and would have to schedule files dependening on defs from disappeared nodes
        if let reporter = reporter {
          reporter.report(
            "Incremental compilation has been disabled, "
              + " because  the following inputs were used in the previous compilation but not in this one: "
              + sourceFiles.disappeared.map { $0.basename }.joined(separator: ", "))
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
    -> (ModuleDependencyGraph, TransitivelyInvalidatedInputSet)?
  {
    precondition(
      sourceFiles.disappeared.isEmpty,
      "Would have to remove nodes from the graph if reading prior")
    if readPriorsFromModuleDependencyGraph {
      return readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals()
    }
    // Every external is added, but don't want to compile an unchanged input that has an import
    // so just changed, not changedOrAdded
    return buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals()
  }

  private func readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals(
  ) -> (ModuleDependencyGraph, TransitivelyInvalidatedInputSet)?
  {
    let dependencyGraphPath = buildRecordInfo.dependencyGraphPath
    let graphIfPresent: ModuleDependencyGraph?
    do {
      graphIfPresent = try ModuleDependencyGraph.read( from: dependencyGraphPath, info: self)
    }
    catch {
      diagnosticEngine.emit(
        warning: "Could not read \(dependencyGraphPath), will not do cross-module incremental builds")
      graphIfPresent = nil
    }
    guard let graph = graphIfPresent
    else {
      return buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals()
    }
    guard graph.populateInputDependencySourceMap(for: .inputsAddedSincePriors) else {
      return nil
    }
    graph.dotFileWriter?.write(graph)

    // Any externals not already in graph must be additions which should trigger
    // recompilation. Thus, `ChangedOrAdded`.
    let nodesDirectlyInvalidatedByExternals =
      graph.collectNodesInvalidatedByChangedOrAddedExternals()
    // Wait till the last minute to do the transitive closure as an optimization.
    guard let inputsInvalidatedByExternals = graph.collectInputsUsingInvalidated(
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
  -> (ModuleDependencyGraph, TransitivelyInvalidatedInputSet)?
  {
    let graph = ModuleDependencyGraph(self, .buildingWithoutAPrior)
    assert(outputFileMap.onlySourceFilesHaveSwiftDeps())
    
    guard graph.populateInputDependencySourceMap(for: .buildingFromSwiftDeps) else {
      return nil
    }

    var inputsInvalidatedByChangedExternals = TransitivelyInvalidatedInputSet()
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
}
