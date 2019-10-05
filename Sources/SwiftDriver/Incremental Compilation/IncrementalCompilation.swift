import TSCBasic
import TSCUtility
import Foundation

// FIXME: rename to something like IncrementalCompilationInitialState
public struct IncrementalCompilation {
  public let showIncrementalBuildDecisions: Bool
  public let shouldCompileIncrementally: Bool
  public let buildRecordPath: VirtualPath?
  public let outputBuildRecordForModuleOnlyBuild: Bool
  public let argsHash: String
  public let lastBuildTime: Date
  public let outOfDateMap: InputInfoMap?
  public let rebuildEverything: Bool

  public init(_ parsedOptions: inout ParsedOptions,
       compilerMode: CompilerMode,
       outputFileMap: OutputFileMap?,
       compilerOutputType: FileType?,
       moduleOutput: ModuleOutput?,
       inputFiles: [TypedVirtualPath],
       diagnosticEngine: DiagnosticsEngine
  ) {
    let showIncrementalBuildDecisions = Self.getShowIncrementalBuildDecisions(&parsedOptions)
    self.showIncrementalBuildDecisions = showIncrementalBuildDecisions

    let shouldCompileIncrementally = Self.computeAndExplainShouldCompileIncrementally(
      &parsedOptions,
      showIncrementalBuildDecisions: showIncrementalBuildDecisions,
      compilerMode: compilerMode)

    self.shouldCompileIncrementally = shouldCompileIncrementally

    self.buildRecordPath = Self.computeBuildRecordPath(
      outputFileMap: outputFileMap,
      compilerOutputType: compilerOutputType,
      diagnosticEngine: shouldCompileIncrementally ? diagnosticEngine : nil)

    // If we emit module along with full compilation, emit build record
    // file for '-emit-module' only mode as well.
    self.outputBuildRecordForModuleOnlyBuild = self.buildRecordPath != nil &&
      moduleOutput?.isTopLevel ?? false

    let argsHash = Self.computeArgsHash(parsedOptions)
    self.argsHash = argsHash
    let lastBuildTime = Date.init()
    self.lastBuildTime = lastBuildTime

    if let buRP = buildRecordPath, shouldCompileIncrementally {
      self.outOfDateMap = InputInfoMap.populateOutOfDateMap(
        argsHash: argsHash,
        lastBuildTime: lastBuildTime,
        inputFiles: inputFiles,
        buildRecordPath: buRP,
        showIncrementalBuildDecisions: showIncrementalBuildDecisions)
    }
    else {
      self.outOfDateMap = nil
    }
    // FIXME: Distinguish errors from "file removed", which is benign.
    self.rebuildEverything = outOfDateMap == nil
  }

  private static func getShowIncrementalBuildDecisions(_ parsedOptions: inout ParsedOptions)
    -> Bool {
    parsedOptions.hasArgument(.driverShowIncremental)
  }

  private static func computeAndExplainShouldCompileIncrementally(
    _ parsedOptions: inout ParsedOptions,
    showIncrementalBuildDecisions: Bool,
    compilerMode: CompilerMode
  )
    -> Bool
  {
    func explain(disabledBecause why: String) {
      stdoutStream <<< "Incremental compilation has been disabled, because it \(why).\n"
      stdoutStream.flush()
    }
    guard parsedOptions.hasArgument(.incremental) else {
      return false
    }
    guard compilerMode.supportsIncrementalCompilation else {
      explain(disabledBecause: "is not compatible with \(compilerMode)")
      return false
    }
    guard !parsedOptions.hasArgument(.embedBitcode) else {
      explain(disabledBecause: "is not currently compatible with embedding LLVM IR bitcode")
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
    return try! compilerOutputType == .swiftModule
      ? VirtualPath(path: partialBuildRecordPath.name + "~moduleonly")
      : partialBuildRecordPath
  }

  static private func computeArgsHash(_ parsedOptionsArg: ParsedOptions) -> String {
    var parsedOptions = parsedOptionsArg
    let hashInput = parsedOptions
      .filter { $0.option.affectsIncrementalBuild && $0.option.kind != .input}
      .map {$0.option.spelling}
      .sorted()
      .joined()
    return SHA256(hashInput).digestString()
  }
}


fileprivate extension CompilerMode {
  var supportsIncrementalCompilation: Bool {
    switch self {
    case .standardCompile, .immediate, .repl: return true
    case .singleCompile: return false
    }
  }
}

public extension Diagnostic.Message {
  static var warning_incremental_requires_output_file_map: Diagnostic.Message {
    .warning("ignoring -incremental (currently requires an output file map)")
  }
  static var warning_incremental_requires_build_record_entry: Diagnostic.Message {
    .warning(
      "ignoring -incremental; " +
      "output file map has no master dependencies entry under \(FileType.swiftDeps)"
    )
  }
}
