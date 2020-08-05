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

public struct IncrementalCompilationState {
  public let showIncrementalBuildDecisions: Bool
  public let enableIncrementalBuild: Bool
  public let buildRecordPath: VirtualPath?
  public let outputBuildRecordForModuleOnlyBuild: Bool
  public let argsHash: String
  public let lastBuildTime: Date
  public let outOfDateMap: InputInfoMap?
  public var rebuildEverything: Bool { return outOfDateMap == nil }

  public init(_ parsedOptions: inout ParsedOptions,
       compilerMode: CompilerMode,
       outputFileMap: OutputFileMap?,
       compilerOutputType: FileType?,
       moduleOutput: ModuleOutputInfo.ModuleOutput?,
       fileSystem: FileSystem,
       inputFiles: [TypedVirtualPath],
       diagnosticEngine: DiagnosticsEngine,
       actualSwiftVersion: String?
  ) {
    let showIncrementalBuildDecisions = Self.getShowIncrementalBuildDecisions(&parsedOptions)
    self.showIncrementalBuildDecisions = showIncrementalBuildDecisions

    let enableIncrementalBuild = Self.computeAndExplainShouldCompileIncrementally(
      &parsedOptions,
      showIncrementalBuildDecisions: showIncrementalBuildDecisions,
      compilerMode: compilerMode,
      diagnosticEngine: diagnosticEngine)

    self.enableIncrementalBuild = enableIncrementalBuild

    self.buildRecordPath = Self.computeBuildRecordPath(
      outputFileMap: outputFileMap,
      compilerOutputType: compilerOutputType,
      diagnosticEngine: enableIncrementalBuild ? diagnosticEngine : nil)

    // If we emit module along with full compilation, emit build record
    // file for '-emit-module' only mode as well.
    self.outputBuildRecordForModuleOnlyBuild = self.buildRecordPath != nil &&
      moduleOutput?.isTopLevel ?? false

    let argsHash = Self.computeArgsHash(parsedOptions)
    self.argsHash = argsHash
    let lastBuildTime = Date()
    self.lastBuildTime = lastBuildTime

    if let buRP = buildRecordPath, enableIncrementalBuild {
      let outOfDateMap = InputInfoMap.populateOutOfDateMap(
        argsHash: argsHash,
        lastBuildTime: lastBuildTime,
        fileSystem: fileSystem,
        inputFiles: inputFiles,
        buildRecordPath: buRP,
        showIncrementalBuildDecisions: showIncrementalBuildDecisions,
        diagnosticEngine: diagnosticEngine)
      if let mismatchReason = outOfDateMap?.matches(
        argsHash: argsHash,
        inputFiles: inputFiles,
        actualSwiftVersion: actualSwiftVersion
      ) {
        diagnosticEngine.emit(.remark_incremental_compilation_disabled(because: mismatchReason))
        self.outOfDateMap = nil
      }
      else {
        self.outOfDateMap = outOfDateMap
      }
    }
    else {
      self.outOfDateMap = nil
    }
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
