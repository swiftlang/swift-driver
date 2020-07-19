//===--------------- FrontendJobHelpers.swift - Swift Frontend Job Common -===//
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

/// Whether we should produce color diagnostics by default.
fileprivate func shouldColorDiagnostics() -> Bool {
  guard let stderrStream = stderrStream.stream as? LocalFileOutputByteStream else {
    return false
  }

  return TerminalController.isTTY(stderrStream)
}

extension Driver {
  /// How the bridging header should be handled.
  enum BridgingHeaderHandling {
    /// Ignore the bridging header entirely.
    case ignored

    /// Parse the bridging header, even if other jobs will use a precompiled
    /// bridging header.
    ///
    /// This is typically used only when precompiling the bridging header.
    case parsed

    /// Use the precompiled bridging header.
    case precompiled
  }
  /// Whether the driver has already constructed a module dependency graph or is in the process
  /// of doing so
  enum ModuleDependencyGraphUse {
    /// Even though the driver may be in ExplicitModuleBuild mode, the dependency graph has not yet
    /// been constructed, omit processing module dependencies
    case dependencyScan
    /// If the driver is in Explicit Module Build mode, the dependency graph has been computed
    case computed
  }
  /// Add frontend options that are common to different frontend invocations.
  mutating func addCommonFrontendOptions(
    commandLine: inout [Job.ArgTemplate],
    inputs: inout [TypedVirtualPath],
    bridgingHeaderHandling: BridgingHeaderHandling = .precompiled,
    moduleDependencyGraphUse: ModuleDependencyGraphUse = .computed
  ) throws {
    // Only pass -target to the REPL or immediate modes if it was explicitly
    // specified on the command line.
    switch compilerMode {
    case .standardCompile, .singleCompile, .batchCompile, .compilePCM:
      commandLine.appendFlag(.target)
      commandLine.appendFlag(targetTriple.triple)

    case .repl, .immediate:
      if parsedOptions.hasArgument(.target) {
        commandLine.appendFlag(.target)
        commandLine.appendFlag(targetTriple.triple)
      }
    }

    // If in ExplicitModuleBuild mode and the dependency graph has been computed, add module
    // dependencies.
    // May also be used for generation of the dependency graph itself in ExplicitModuleBuild mode.
    if (parsedOptions.contains(.driverExplicitModuleBuild) &&
          moduleDependencyGraphUse == .computed) {
      try addExplicitModuleBuildArguments(inputs: &inputs, commandLine: &commandLine)
    }

    if let variant = parsedOptions.getLastArgument(.targetVariant)?.asSingle {
      commandLine.appendFlag(.targetVariant)
      commandLine.appendFlag(Triple(variant, normalizing: true).triple)
    }

    // Enable address top-byte ignored in the ARM64 backend.
    if targetTriple.arch == .aarch64 {
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
    try commandLine.appendAll(.vfsoverlay, from: &parsedOptions)

    try commandLine.appendLast(.AssertConfig, from: &parsedOptions)
    try commandLine.appendLast(.autolinkForceLoad, from: &parsedOptions)

    if let colorOption = parsedOptions.last(for: .colorDiagnostics, .noColorDiagnostics) {
      commandLine.appendFlag(colorOption.option)
    } else if shouldColorDiagnostics() {
      commandLine.appendFlag(.colorDiagnostics)
    }
    try commandLine.appendLast(.fixitAll, from: &parsedOptions)
    try commandLine.appendLast(.warnSwift3ObjcInferenceMinimal, .warnSwift3ObjcInferenceComplete, from: &parsedOptions)
    try commandLine.appendLast(.warnImplicitOverrides, from: &parsedOptions)
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
    try commandLine.appendLast(.warningsAsErrors, .noWarningsAsErrors, from: &parsedOptions)
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
    try commandLine.appendLast(.packageDescriptionVersion, from: &parsedOptions)
    try commandLine.appendLast(.serializeDiagnosticsPath, from: &parsedOptions)
    try commandLine.appendLast(.debugDiagnosticNames, from: &parsedOptions)
    try commandLine.appendLast(.enableAstscopeLookup, from: &parsedOptions)
    try commandLine.appendLast(.disableAstscopeLookup, from: &parsedOptions)
    try commandLine.appendLast(.disableParserLookup, from: &parsedOptions)
    try commandLine.appendLast(.sanitizeRecoverEQ, from: &parsedOptions)
    try commandLine.appendLast(.scanDependencies, from: &parsedOptions)
    try commandLine.appendLast(.fineGrainedDependencyIncludeIntrafile, from: &parsedOptions)
    try commandLine.appendLast(.enableExperimentalConcisePoundFile, from: &parsedOptions)
    try commandLine.appendLast(.printEducationalNotes, from: &parsedOptions)
    try commandLine.appendLast(.diagnosticStyle, from: &parsedOptions)
    try commandLine.appendLast(.enableDirectIntramoduleDependencies, .disableDirectIntramoduleDependencies, from: &parsedOptions)
    try commandLine.appendLast(.locale, from: &parsedOptions)
    try commandLine.appendLast(.localizationPath, from: &parsedOptions)
    try commandLine.appendAll(.D, from: &parsedOptions)
    try commandLine.appendAll(.sanitizeEQ, from: &parsedOptions)
    try commandLine.appendAll(.debugPrefixMap, from: &parsedOptions)
    try commandLine.appendAllArguments(.Xfrontend, from: &parsedOptions)
    try commandLine.appendAll(.coveragePrefixMap, from: &parsedOptions)

    if let workingDirectory = workingDirectory {
      // Add -Xcc -working-directory before any other -Xcc options to ensure it is
      // overridden by an explicit -Xcc -working-directory, although having a
      // different working directory is probably incorrect.
      commandLine.appendFlag(.Xcc)
      commandLine.appendFlag(.workingDirectory)
      commandLine.appendFlag(.Xcc)
      commandLine.appendPath(.absolute(workingDirectory))
    }

    // Resource directory.
    commandLine.appendFlag(.resourceDir)
    commandLine.appendPath(
      try AbsolutePath(validating: frontendTargetInfo.paths.runtimeResourcePath))

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

    if let importedObjCHeader = importedObjCHeader,
        bridgingHeaderHandling != .ignored {
      commandLine.appendFlag(.importObjcHeader)
      if bridgingHeaderHandling == .precompiled,
          let pch = bridgingPrecompiledHeader {
        if parsedOptions.contains(.pchOutputDir) {
          commandLine.appendPath(importedObjCHeader)
          try commandLine.appendLast(.pchOutputDir, from: &parsedOptions)
          if !compilerMode.isSingleCompilation {
            commandLine.appendFlag(.pchDisableValidation)
          }
        } else {
          commandLine.appendPath(pch)
        }
      } else {
        commandLine.appendPath(importedObjCHeader)
      }
    }

    // Repl Jobs shouldn't include -module-name.
    if compilerMode != .repl {
      commandLine.appendFlags("-module-name", moduleOutputInfo.name)
    }
  }

  mutating func addFrontendSupplementaryOutputArguments(commandLine: inout [Job.ArgTemplate], primaryInputs: [TypedVirtualPath]) throws -> [TypedVirtualPath] {
    var outputs: [TypedVirtualPath] = []

    /// Add output of a particular type, if needed.
    func addOutputOfType(
        outputType: FileType, finalOutputPath: VirtualPath?,
        input: VirtualPath?, flag: String
    ) {
      // If there is no final output, there's nothing to do.
      guard let finalOutputPath = finalOutputPath else { return }

      // If the whole of the compiler output is this type, there's nothing to
      // do.
      if outputType == compilerOutputType { return }

      // Add the appropriate flag.
      commandLine.appendFlag(flag)

      // Compute the output path based on the input path (if there is one), or
      // use the final output.
      let outputPath: VirtualPath
      if let input = input {
        outputPath = (outputFileMap ?? OutputFileMap())
          .getOutput(inputFile: input, outputType: outputType)
      } else {
        outputPath = finalOutputPath
      }

      commandLine.append(.path(outputPath))
      outputs.append(TypedVirtualPath(file: outputPath, type: outputType))
    }

    /// Add all of the outputs needed for a given input.
    func addAllOutputsFor(input: VirtualPath?) {
      if !forceEmitModuleInSingleInvocation {
        addOutputOfType(
            outputType: .swiftModule,
            finalOutputPath: moduleOutputInfo.output?.outputPath,
            input: input,
            flag: "-emit-module-path")
        addOutputOfType(
            outputType: .swiftDocumentation,
            finalOutputPath: moduleDocOutputPath,
            input: input,
            flag: "-emit-module-doc-path")
        addOutputOfType(
            outputType: .swiftSourceInfoFile,
            finalOutputPath: moduleSourceInfoPath,
            input: input,
            flag: "-emit-module-source-info-path")
        addOutputOfType(
            outputType: .dependencies,
            finalOutputPath: dependenciesFilePath,
            input: input,
            flag: "-emit-dependencies-path")
      }

      addOutputOfType(
          outputType: .yamlOptimizationRecord,
          finalOutputPath: optimizationRecordPath,
          input: input,
          flag: "-save-optimization-record-path")

      addOutputOfType(
          outputType: .diagnostics,
          finalOutputPath: serializedDiagnosticsFilePath,
          input: input,
          flag: "-serialize-diagnostics-path")

      #if false
      // FIXME: handle -update-code
      addOutputOfType(outputType: .remap, input: input.file, flag: "-emit-remap-file-path")
      #endif
    }

    if compilerMode.usesPrimaryFileInputs {
      for input in primaryInputs {
        addAllOutputsFor(input: input.file)
      }
    } else {
      addAllOutputsFor(input: nil)

      // Outputs that only make sense when the whole module is processed
      // together.
      addOutputOfType(
          outputType: .objcHeader,
          finalOutputPath: objcGeneratedHeaderPath,
          input: nil,
          flag: "-emit-objc-header-path")

      addOutputOfType(
          outputType: .swiftInterface,
          finalOutputPath: swiftInterfacePath,
          input: nil,
          flag: "-emit-module-interface-path")

      addOutputOfType(
          outputType: .tbd,
          finalOutputPath: tbdPath,
          input: nil,
          flag: "-emit-tbd-path")
    }

    return outputs
  }

  /// Adds all dependecies required for an explicit module build
  /// to inputs and comman line arguments of a compile job.
  func addExplicitModuleBuildArguments(inputs: inout [TypedVirtualPath],
                                       commandLine: inout [Job.ArgTemplate]) throws {
    guard var handler = explicitModuleBuildHandler else {
      fatalError("No handler in Explicit Module Build mode.")
    }
    try handler.resolveMainModuleDependencies(inputs: &inputs, commandLine: &commandLine)
  }

  /// In Explicit Module Build mode, distinguish between main module jobs and intermediate dependency build jobs,
  /// such as Swift modules built from .swiftmodule files and Clang PCMs.
  public func isExplicitMainModuleJob(job: Job) -> Bool {
    guard let handler = explicitModuleBuildHandler else {
      fatalError("No handler in Explicit Module Build mode.")
    }
    return job.moduleName == handler.dependencyGraph.mainModuleName
  }
}
