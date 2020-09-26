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

@_spi(Testing) public class IncrementalCompilationState {
  public let showIncrementalBuildDecisions: Bool
  public let enableIncrementalBuild: Bool
  public let buildRecordPath: VirtualPath?
  public let outputBuildRecordForModuleOnlyBuild: Bool
  public let argsHash: String
  public let lastBuildTime: Date
  public let outOfDateMap: InputInfoMap?
  public let diagnosticEngine: DiagnosticsEngine

  public var jobsWhichHaveRun = Set<Job>()

  private init(
    showIncrementalBuildDecisions: Bool,
    enableIncrementalBuild: Bool,
    buildRecordPath: VirtualPath?,
    outputBuildRecordForModuleOnlyBuild: Bool,
    argsHash: String,
    lastBuildTime: Date,
    outOfDateMap: InputInfoMap?,
    diagnosticEngine: DiagnosticsEngine
  ) {
    self.showIncrementalBuildDecisions = showIncrementalBuildDecisions
    self.enableIncrementalBuild = enableIncrementalBuild
    self.buildRecordPath = buildRecordPath
    self.outputBuildRecordForModuleOnlyBuild = outputBuildRecordForModuleOnlyBuild
    self.argsHash = argsHash
    self.lastBuildTime = lastBuildTime
    self.outOfDateMap = outOfDateMap
    self.diagnosticEngine = diagnosticEngine
  }


  public convenience init(_ parsedOptions: inout ParsedOptions,
              compilerMode: CompilerMode,
              outputFileMap: OutputFileMap?,
              compilerOutputType: FileType?,
              moduleOutput: ModuleOutputInfo.ModuleOutput?,
              fileSystem: FileSystem,
              inputFiles: [TypedVirtualPath],
              actualSwiftVersion: String?,
              diagnosticEngine: DiagnosticsEngine
  ) {
    let showIncrementalBuildDecisions = Self.getShowIncrementalBuildDecisions(&parsedOptions)

    let enableIncrementalBuild = Self.computeAndExplainShouldCompileIncrementally(
      &parsedOptions,
      showIncrementalBuildDecisions: showIncrementalBuildDecisions,
      compilerMode: compilerMode,
      diagnosticEngine: diagnosticEngine)

    let buildRecordPath = Self.computeBuildRecordPath(
      outputFileMap: outputFileMap,
      compilerOutputType: compilerOutputType,
      diagnosticEngine: enableIncrementalBuild ? diagnosticEngine : nil)

    // If we emit module along with full compilation, emit build record
    // file for '-emit-module' only mode as well.
    let outputBuildRecordForModuleOnlyBuild = buildRecordPath != nil &&
      moduleOutput?.isTopLevel ?? false

    let argsHash = Self.computeArgsHash(parsedOptions)
    let lastBuildTime = Date()
    let outOfDateMap = Self.computeOutOfDateMap(
      buildRecordPath,
      enableIncrementalBuild: enableIncrementalBuild,
      fileSystem: fileSystem,
      inputFiles: inputFiles,
      diagnosticEngine: diagnosticEngine,
      showIncrementalBuildDecisions: showIncrementalBuildDecisions,
      argsHash: argsHash,
      lastBuildTime: lastBuildTime,
      actualSwiftVersion: actualSwiftVersion)

    self.init(
      showIncrementalBuildDecisions: showIncrementalBuildDecisions,
      enableIncrementalBuild: enableIncrementalBuild,
      buildRecordPath: buildRecordPath,
      outputBuildRecordForModuleOnlyBuild: outputBuildRecordForModuleOnlyBuild,
      argsHash: argsHash,
      lastBuildTime: lastBuildTime,
      outOfDateMap: outOfDateMap,
      diagnosticEngine: diagnosticEngine
    )
  }

  private static func getShowIncrementalBuildDecisions(_ parsedOptions: inout ParsedOptions)
    -> Bool {
    parsedOptions.hasArgument(.driverShowIncremental)
  }

  private static func computeAndExplainShouldCompileIncrementally(
    _ parsedOptions: inout ParsedOptions,
    showIncrementalBuildDecisions: Bool,
    compilerMode: CompilerMode,
    diagnosticEngine: DiagnosticsEngine
  )
    -> Bool
  {
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

  private static func computeBuildRecordPath(
    outputFileMap: OutputFileMap?,
    compilerOutputType: FileType?,
    diagnosticEngine: DiagnosticsEngine?
  ) -> VirtualPath? {
    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard let ofm = outputFileMap else {
      diagnosticEngine.map { $0.emit(.warning_incremental_requires_output_file_map) }
      return nil
    }
    guard let partialBuildRecordPath = ofm.existingOutputForSingleInput(outputType: .swiftDeps)
      else {
        diagnosticEngine.map { $0.emit(.warning_incremental_requires_build_record_entry) }
        return nil
    }
    // In 'emit-module' only mode, use build-record filename suffixed with
    // '~moduleonly'. So that module-only mode doesn't mess up build-record
    // file for full compilation.
    return compilerOutputType == .swiftModule
      ? partialBuildRecordPath.appendingToBaseName("~moduleonly")
      : partialBuildRecordPath
  }

  static private func computeArgsHash(_ parsedOptionsArg: ParsedOptions) -> String {
    var parsedOptions = parsedOptionsArg
    let hashInput = parsedOptions
      .filter { $0.option.affectsIncrementalBuild && $0.option.kind != .input}
      .map {$0.option.spelling}
      .sorted()
      .joined()
    return SHA256().hash(hashInput).hexadecimalRepresentation
  }

  static private func computeOutOfDateMap(_ buildRecordPath: VirtualPath?,
                                          enableIncrementalBuild: Bool,
                                          fileSystem: FileSystem,
                                          inputFiles: [TypedVirtualPath],
                                          diagnosticEngine: DiagnosticsEngine,
                                          showIncrementalBuildDecisions: Bool,
                                          argsHash: String,
                                          lastBuildTime: Date,
                                          actualSwiftVersion: String?

  ) -> InputInfoMap? {
    guard let buildRecordPath = buildRecordPath, enableIncrementalBuild else { return nil }
    let maybeMatchingOutOfDateMap = InputInfoMap.populateOutOfDateMap(
      argsHash: argsHash,
      lastBuildTime: lastBuildTime,
      fileSystem: fileSystem,
      inputFiles: inputFiles,
      buildRecordPath: buildRecordPath,
      showIncrementalBuildDecisions: showIncrementalBuildDecisions,
      diagnosticEngine: diagnosticEngine)

    if let mismatchReason = maybeMatchingOutOfDateMap?.matches(
      argsHash: argsHash,
      inputFiles: inputFiles,
      actualSwiftVersion: actualSwiftVersion
    ) {
      diagnosticEngine.emit(.remark_incremental_compilation_disabled(because: mismatchReason))
      return nil
    }
    else {
      return maybeMatchingOutOfDateMap
    }
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
      "output file map has no master dependencies entry under \(FileType.swiftDeps)"
    )
  }
  static func remark_incremental_compilation_disabled(because why: String) -> Diagnostic.Message {
    .remark("Incremental compilation has been disabled, because \(why).\n")
  }
}

extension Driver {
  public var isIncremental: Bool {
    return incrementalCompilationState.enableIncrementalBuild
  }
}

extension IncrementalCompilationState {
  func areOutputsCurrent(from job: Job, dependencyGraph: ModuleDependencyGraph) -> Bool {
    guard enableIncrementalBuild else { return false }
    guard case .compile = job.kind else { return false }
    guard !hasAlreadyRun(job) else { return true }
    if isJobInFirstRound(job) { return false }
    return false // TODO: Incremental
    // 1st wave
    // 2nd wave
  }

  private func hasAlreadyRun(_ job: Job) -> Bool {
    jobsWhichHaveRun.contains(job)
  }
// TODO: incremental
  private func isJobInFirstRound(_ job: Job) -> Bool {
//    computeShouldInitiallyScheduleJobAndDependendents
//    collectCascadedJobsFromDependencyGraph
//    collectExternallyDependentJobsFromDependencyGraph
    return true // TODO incremental
  }


  func jobFinished( job: Job, result: ProcessResult, dependencyGraph: ModuleDependencyGraph ) {
    jobsWhichHaveRun.insert(job)
    let changes = dependencyGraph.integrate(job: job)
    // get diagnosticEngine from self, or store it in graph
//nodes to jobs excluding already run
//    var nextWave = Set<Job>()
//    for swiftDeps in job.swiftDepsOutputs {
//
//    }
//    dependencyGraph.integrate(job:
    // TODO: Incremental
  }

  func reloadSwiftDeps(of job: Job, result: ProcessResult) {
    // TODO: Incremental
  }
}
