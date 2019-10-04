import TSCBasic
import TSCUtility

public struct IncrementalCompilation {
  public let showIncrementalBuildDecisions: Bool
  public let shouldCompileIncrementally: Bool
  public let buildRecordPath: VirtualPath?
  public let outputBuildRecordForModuleOnlyBuild: Bool

  public init(_ parsedOptions: inout ParsedOptions,
       compilerMode: CompilerMode,
       outputFileMap: OutputFileMap?,
       compilerOutputType: FileType?,
       moduleOutput: ModuleOutput?,
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
  }

  private static func getShowIncrementalBuildDecisions(_ parsedOptions: inout ParsedOptions)  -> Bool {
    parsedOptions.hasArgument(.driver_show_incremental)
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
    guard !parsedOptions.hasArgument(.embed_bitcode) else {
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
