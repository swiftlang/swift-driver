import TSCBasic

/// Whether we should produce color diagnostics by default.
fileprivate func shouldColorDiagnostics() -> Bool {
  guard let stderrStream = stderrStream.stream as? LocalFileOutputByteStream else {
    return false
  }

  return TerminalController.isTTY(stderrStream)
}

extension Driver {
  /// Add frontend options that are common to different frontend invocations.
  mutating func addCommonFrontendOptions(commandLine: inout [Job.ArgTemplate]) throws {
    // Only pass -target to the REPL or immediate modes if it was explicitly
    // specified on the command line.
    switch compilerMode {
    case .standardCompile, .singleCompile:
      commandLine.appendFlag(.target)
      commandLine.appendFlag(targetTriple.triple)

    case .repl, .immediate:
      if parsedOptions.hasArgument(.target) {
        commandLine.appendFlag(.target)
        commandLine.appendFlag(targetTriple.triple)
      }
    }

    // Enable address top-byte ignored in the ARM64 backend.
    if (targetTriple.arch == .aarch64) {
      commandLine.appendFlag(.Xllvm)
      commandLine.appendFlag("-aarch64-use-tbi")
    }

    // Enable or disable ObjC interop appropriately for the platform
    if targetTriple.isDarwin {
      commandLine.appendFlag(.enableObjcInterop)
    } else {
      commandLine.appendFlag(.disableObjcInterop)
    }

    // Handle the CPU and its preferences.
    try commandLine.appendLast(.targetCpu, from: &parsedOptions)

    if let sdkPath = sdkPath {
      commandLine.appendFlag(.sdk)
      commandLine.append(.path(try .init(path: sdkPath)))
    }

    try commandLine.appendAll(.I, from: &parsedOptions)
    try commandLine.appendAll(.F, .Fsystem, from: &parsedOptions)

    try commandLine.appendLast(.AssertConfig, from: &parsedOptions)
    try commandLine.appendLast(.autolinkForceLoad, from: &parsedOptions)

    if let colorOption = parsedOptions.last(where: { $0.option == .colorDiagnostics || $0.option == .noColorDiagnostics }) {
      commandLine.appendFlag(colorOption.option)
    } else if shouldColorDiagnostics() {
      commandLine.appendFlag(.colorDiagnostics)
    }
    try commandLine.appendLast(.fixitAll, from: &parsedOptions)
    try commandLine.appendLast(.warnSwift3ObjcInferenceMinimal, .warnSwift3ObjcInferenceComplete, from: &parsedOptions)
    try commandLine.appendLast(.warnImplicitOverrides, from: &parsedOptions)
    try commandLine.appendLast(.typoCorrectionLimit, from: &parsedOptions)
    try commandLine.appendLast(.typoCorrectionLimit, from: &parsedOptions)
    try commandLine.appendLast(.enableAppExtension, from: &parsedOptions)
    try commandLine.appendLast(.enableLibraryEvolution, from: &parsedOptions)
    try commandLine.appendLast(.enableTesting, from: &parsedOptions)
    try commandLine.appendLast(.enablePrivateImports, from: &parsedOptions)
    try commandLine.appendLast(.enableCxxInterop, from: &parsedOptions)
    try commandLine.appendLast(in: .g, from: &parsedOptions)
    try commandLine.appendLast(.debugInfoFormat, from: &parsedOptions)
    try commandLine.appendLast(.importUnderlyingModule, from: &parsedOptions)
    try commandLine.appendLast(.moduleCachePath, from: &parsedOptions)
    try commandLine.appendLast(.moduleLinkName, from: &parsedOptions)
    try commandLine.appendLast(.nostdimport, from: &parsedOptions)
    try commandLine.appendLast(.parseStdlib, from: &parsedOptions)
    try commandLine.appendLast(.resourceDir, from: &parsedOptions)
    try commandLine.appendLast(.solverMemoryThreshold, from: &parsedOptions)
    try commandLine.appendLast(.valueRecursionThreshold, from: &parsedOptions)
    try commandLine.appendLast(.warnSwift3ObjcInference, from: &parsedOptions)
    try commandLine.appendLast(.RpassEQ, from: &parsedOptions)
    try commandLine.appendLast(.RpassMissedEQ, from: &parsedOptions)
    try commandLine.appendLast(.suppressWarnings, from: &parsedOptions)
    try commandLine.appendLast(.profileGenerate, from: &parsedOptions)
    try commandLine.appendLast(.profileUse, from: &parsedOptions)
    try commandLine.appendLast(.profileCoverageMapping, from: &parsedOptions)
    try commandLine.appendLast(.warningsAsErrors, from: &parsedOptions)
    try commandLine.appendLast(.sanitizeEQ, from: &parsedOptions)
    try commandLine.appendLast(.sanitizeCoverageEQ, from: &parsedOptions)
    try commandLine.appendLast(.static, from: &parsedOptions)
    try commandLine.appendLast(.swiftVersion, from: &parsedOptions)
    try commandLine.appendLast(.enforceExclusivityEQ, from: &parsedOptions)
    try commandLine.appendLast(.statsOutputDir, from: &parsedOptions)
    try commandLine.appendLast(.traceStatsEvents, from: &parsedOptions)
    try commandLine.appendLast(.profileStatsEvents, from: &parsedOptions)
    try commandLine.appendLast(.profileStatsEntities, from: &parsedOptions)
    try commandLine.appendLast(.solverShrinkUnsolvedThreshold, from: &parsedOptions)
    try commandLine.appendLast(in: .O, from: &parsedOptions)
    try commandLine.appendLast(.RemoveRuntimeAsserts, from: &parsedOptions)
    try commandLine.appendLast(.AssumeSingleThreaded, from: &parsedOptions)
    try commandLine.appendLast(.enableExperimentalDependencies, from: &parsedOptions)
    try commandLine.appendLast(.experimentalDependencyIncludeIntrafile, from: &parsedOptions)
    try commandLine.appendLast(.packageDescriptionVersion, from: &parsedOptions)
    try commandLine.appendLast(.serializeDiagnosticsPath, from: &parsedOptions)
    try commandLine.appendLast(.debugDiagnosticNames, from: &parsedOptions)
    try commandLine.appendLast(.enableAstscopeLookup, from: &parsedOptions)
    try commandLine.appendLast(.disableAstscopeLookup, from: &parsedOptions)
    try commandLine.appendLast(.disableParserLookup, from: &parsedOptions)
    try commandLine.appendAll(.D, from: &parsedOptions)
    try commandLine.appendAllArguments(.debugPrefixMap, from: &parsedOptions)
    try commandLine.appendAllArguments(.Xfrontend, from: &parsedOptions)

    if let workingDirectory = workingDirectory {
      // Add -Xcc -working-directory before any other -Xcc options to ensure it is
      // overridden by an explicit -Xcc -working-directory, although having a
      // different working directory is probably incorrect.
      commandLine.appendFlag(.Xcc)
      commandLine.appendFlag(.workingDirectory)
      commandLine.appendFlag(.Xcc)
      commandLine.appendPath(.absolute(workingDirectory))
    }

    // -g implies -enable-anonymous-context-mangled-names, because the extra
    // metadata aids debugging.
    if parsedOptions.getLast(in: .g) != nil {
      // But don't add the option in optimized builds: it would prevent dead code
      // stripping of unused metadata.
      let shouldSupportAnonymousContextMangledNames: Bool
      if let opt = parsedOptions.getLast(in: .O), opt.option != .Onone {
        shouldSupportAnonymousContextMangledNames = false
      } else {
        shouldSupportAnonymousContextMangledNames = true
      }

      if shouldSupportAnonymousContextMangledNames {
        commandLine.appendFlag(.enableAnonymousContextMangledNames)
      }
    }

    // Pass through any subsystem flags.
    try commandLine.appendAll(.Xllvm, from: &parsedOptions)
    try commandLine.appendAll(.Xcc, from: &parsedOptions)

    if let importedObjCHeader = importedObjCHeader {
      commandLine.appendFlag(.importObjcHeader)
      commandLine.appendPath(importedObjCHeader)
    }

    commandLine.appendFlags("-module-name", moduleName)
  }

  mutating func addFrontendSupplementaryOutputArguments(commandLine: inout [Job.ArgTemplate], primaryInputs: [TypedVirtualPath]) throws -> [TypedVirtualPath] {
    var outputs: [TypedVirtualPath] = []

    func addOutputsOfType(outputType: FileType, input: VirtualPath, flag: String) {
      if outputType == compilerOutputType { return }

      commandLine.appendFlag(flag)

      let path = (outputFileMap ?? OutputFileMap())
        .getOutput(inputFile: input, outputType: outputType)
      commandLine.append(.path(path))
      outputs.append(TypedVirtualPath(file: path, type: outputType))
    }

    for input in primaryInputs {
      if moduleOutput != nil && !forceEmitModuleInSingleInvocation {
        addOutputsOfType(outputType: .swiftModule, input: input.file, flag: "-emit-module-path")
      }

      if moduleDocOutputPath != nil && !forceEmitModuleInSingleInvocation {
        addOutputsOfType(outputType: .swiftDocumentation, input: input.file, flag: "-emit-module-doc-path")
      }

      if dependenciesFilePath != nil && !forceEmitModuleInSingleInvocation {
        addOutputsOfType(outputType: .dependencies, input: input.file, flag: "-emit-dependencies-path")
      }

      if optimizationRecordPath != nil {
        addOutputsOfType(outputType: .optimizationRecord, input: input.file, flag: "-save-optimization-record-path")
      }

      #if false
      // FIXME: handle -update-code
      addOutputsOfType(outputType: .remap, input: input.file, flag: "-emit-remap-file-path")
      #endif
    }

    return outputs
  }
}
