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

import SwiftOptions

import class TSCBasic.LocalFileOutputByteStream
import class TSCBasic.TerminalController
import struct TSCBasic.RelativePath
import struct TSCBasic.AbsolutePath
import var TSCBasic.stderrStream

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

  /// If the given option is specified but the frontend doesn't support it, throw an error.
  func verifyFrontendSupportsOptionIfNecessary(_ option: Option) throws {
    if parsedOptions.hasArgument(option) && !isFrontendArgSupported(option) {
      diagnosticEngine.emit(.error_unsupported_opt_for_frontend(option: option))
      throw ErrorDiagnostics.emitted
    }
  }

  /// Add frontend options that are common to different frontend invocations.
  mutating func addCommonFrontendOptions(
    commandLine: inout [Job.ArgTemplate],
    inputs: inout [TypedVirtualPath],
    kind: Job.Kind,
    bridgingHeaderHandling: BridgingHeaderHandling = .precompiled,
    explicitModulePlanner: ExplicitDependencyBuildPlanner? = nil,
    forVariantEmitModule: Bool = false
  ) throws {
    // Only pass -target to the REPL or immediate modes if it was explicitly
    // specified on the command line.
    switch compilerMode {
    case .standardCompile, .singleCompile, .batchCompile, .compilePCM, .dumpPCM:
      commandLine.appendFlag(.target)
      if forVariantEmitModule,
         let variant = parsedOptions.getLastArgument(.targetVariant)?.asSingle {
        commandLine.appendFlag(Triple(variant, normalizing: true).triple)
      } else {
        commandLine.appendFlag(targetTriple.triple)
      }

    case .repl, .immediate:
      if parsedOptions.hasArgument(.target) {
        commandLine.appendFlag(.target)
        commandLine.appendFlag(targetTriple.triple)
      }
    case .intro:
      break
    }

    let isPlanJobForExplicitModule = parsedOptions.contains(.driverExplicitModuleBuild) && explicitModulePlanner != nil
    let jobNeedPathRemap: Bool
    // If in ExplicitModuleBuild mode and the dependency graph has been computed, add module
    // dependencies.
    // May also be used for generation of the dependency graph itself in ExplicitModuleBuild mode.
    if isPlanJobForExplicitModule,
       let explicitModulePlanner = explicitModulePlanner {
      switch kind {
      case .generatePCH:
        explicitModulePlanner.resolveBridgingHeaderDependencies(inputs: &inputs, commandLine: &commandLine)
        jobNeedPathRemap = true
      case .compile, .emitModule, .interpret, .verifyModuleInterface:
        explicitModulePlanner.resolveMainModuleDependencies(inputs: &inputs, commandLine: &commandLine)
        jobNeedPathRemap = true
      case .backend, .compileModuleFromInterface,
           .generatePCM, .dumpPCM, .repl, .printTargetInfo,
           .versionRequest, .autolinkExtract, .generateDSYM,
           .help, .link, .verifyDebugInfo, .scanDependencies,
           .emitSupportedFeatures, .moduleWrap,
           .generateAPIBaseline, .generateABIBaseline, .compareAPIBaseline,
           .compareABIBaseline, .printSupportedFeatures:
        jobNeedPathRemap = false
      }
    } else {
      jobNeedPathRemap = false
    }

    // Check if dependency scanner has put the job into direct clang cc1 mode.
    // If dependency scanner put us into direct cc1 mode, avoid adding `-Xcc` options, since
    // dependency scanner already adds needed flags and -Xcc options known by swift-driver are
    // clang driver flags but not it requires cc1 flags.
    let directModuleCC1Mode = commandLine.contains(Job.ArgTemplate.flag("-direct-clang-cc1-module-build"))
    func appendXccFlag(_ flag: String) {
      guard !directModuleCC1Mode else { return }
      commandLine.appendFlag(.Xcc)
      commandLine.appendFlag(flag)
    }

    if !forVariantEmitModule,
       let variant = parsedOptions.getLastArgument(.targetVariant)?.asSingle {
      commandLine.appendFlag(.targetVariant)
      commandLine.appendFlag(Triple(variant, normalizing: true).triple)
    }

    // Enable address top-byte ignored in the ARM64 backend.
    if targetTriple.arch == .aarch64 {
      commandLine.appendFlag(.Xllvm)
      commandLine.appendFlag("-aarch64-use-tbi")
    }

    let isEmbeddedEnabled = parsedOptions.isEmbeddedEnabled

    // Enable or disable ObjC interop appropriately for the platform
    if targetTriple.isDarwin && !isEmbeddedEnabled {
      commandLine.appendFlag(.enableObjcInterop)
    } else {
      commandLine.appendFlag(.disableObjcInterop)
    }

    // Add flags for C++ interop
    try commandLine.appendLast(.enableExperimentalCxxInterop, from: &parsedOptions)
    try commandLine.appendLast(.cxxInteroperabilityMode, from: &parsedOptions)

    if isEmbeddedEnabled && parsedOptions.hasArgument(.enableLibraryEvolution) {
      diagnosticEngine.emit(.error_no_library_evolution_embedded)
      throw ErrorDiagnostics.emitted
    }

    // Building embedded Swift requires WMO, unless we're not generating SIL. This allows modes like -index-file to work the same way they do when not using embedded Swift
    if isEmbeddedEnabled && compilerOutputType?.requiresSILGen == true &&
       (!parsedOptions.hasArgument(.wmo) || !parsedOptions.hasArgument(.wholeModuleOptimization)) {
      diagnosticEngine.emit(.error_need_wmo_embedded)
      throw ErrorDiagnostics.emitted
    }

    if isEmbeddedEnabled && parsedOptions.hasArgument(.enableObjcInterop) {
      diagnosticEngine.emit(.error_no_objc_interop_embedded)
      throw ErrorDiagnostics.emitted
    }

    try verifyFrontendSupportsOptionIfNecessary(.disableUpcomingFeature)
    try verifyFrontendSupportsOptionIfNecessary(.disableExperimentalFeature)

    // Handle the CPU and its preferences.
    try commandLine.appendLast(.targetCpu, from: &parsedOptions)

    if let sdkPath = frontendTargetInfo.sdkPath?.path {
      try addPathOption(option: .sdk, path: VirtualPath.lookup(sdkPath), to: &commandLine, remap: jobNeedPathRemap)
    }

    for args: (Option, Option) in [
          (.visualcToolsRoot, .visualcToolsVersion),
          (.windowsSdkRoot, .windowsSdkVersion)
        ] {
      let (rootOpt, versionOpt) = args
      if let rootArg = parsedOptions.last(for: rootOpt),
          isFrontendArgSupported(rootOpt) {
        try addPathOption(rootArg, to: &commandLine, remap: jobNeedPathRemap)
      }

      if let value = parsedOptions.getLastArgument(versionOpt)?.asSingle,
          isFrontendArgSupported(versionOpt) {
        commandLine.appendFlags(versionOpt.spelling, value)
      }
    }

    // TODO: Can we drop all search paths for compile jobs for explicit module build?
    try addAllArgumentsWithPath(.I, .Isystem, to: &commandLine, remap: jobNeedPathRemap)
    try addAllArgumentsWithPath(.F, .Fsystem, to: &commandLine, remap: jobNeedPathRemap)
    try addAllArgumentsWithPath(.vfsoverlay, to: &commandLine, remap: jobNeedPathRemap)

    if let gccToolchain = parsedOptions.getLastArgument(.gccToolchain) {
        appendXccFlag("--gcc-toolchain=\(gccToolchain.asSingle)")
    }

    try commandLine.appendLast(.AssertConfig, from: &parsedOptions)
    try commandLine.appendLast(.autolinkForceLoad, from: &parsedOptions)

    if parsedOptions.hasFlag(positive: .colorDiagnostics, negative: .noColorDiagnostics, default: shouldColorDiagnostics()) {
      commandLine.appendFlag(.colorDiagnostics)
      appendXccFlag("-fcolor-diagnostics")
    } else {
      commandLine.appendFlag(.noColorDiagnostics)
      appendXccFlag("-fno-color-diagnostics")
    }
    try commandLine.appendLast(.fixitAll, from: &parsedOptions)
    try commandLine.appendLast(.warnSwift3ObjcInferenceMinimal, .warnSwift3ObjcInferenceComplete, from: &parsedOptions)
    try commandLine.appendLast(.warnImplicitOverrides, from: &parsedOptions)
    try commandLine.appendLast(.warnSoftDeprecated, from: &parsedOptions)
    try commandLine.appendLast(.typoCorrectionLimit, from: &parsedOptions)
    try commandLine.appendLast(.enableAppExtension, from: &parsedOptions)
    try commandLine.appendLast(.enableLibraryEvolution, from: &parsedOptions)
    try commandLine.appendLast(.enableTesting, from: &parsedOptions)
    try commandLine.appendLast(.enablePrivateImports, from: &parsedOptions)
    try commandLine.appendLast(in: .g, from: &parsedOptions)
    if debugInfo.level != nil {
      commandLine.appendFlag("-debug-info-format=\(debugInfo.format.rawValue)")
      if isFrontendArgSupported(.dwarfVersion) {
        commandLine.appendFlag("-dwarf-version=\(debugInfo.dwarfVersion)")
      }
    }
    try commandLine.appendLast(.importUnderlyingModule, from: &parsedOptions)
    try commandLine.appendLast(.moduleCachePath, from: &parsedOptions)
    try commandLine.appendLast(.moduleLinkName, from: &parsedOptions)
    try commandLine.appendLast(.moduleAbiName, from: &parsedOptions)
    try commandLine.appendLast(.nostdimport, from: &parsedOptions)
    try commandLine.appendLast(.nostdlibimport, from: &parsedOptions)
    try commandLine.appendLast(.parseStdlib, from: &parsedOptions)
    try commandLine.appendLast(.solverMemoryThreshold, from: &parsedOptions)
    try commandLine.appendLast(.valueRecursionThreshold, from: &parsedOptions)
    try commandLine.appendLast(.warnSwift3ObjcInference, from: &parsedOptions)
    try commandLine.appendLast(.remarkLoadingModule, from: &parsedOptions)
    try commandLine.appendLast(.RpassEQ, from: &parsedOptions)
    try commandLine.appendLast(.RpassMissedEQ, from: &parsedOptions)
    try commandLine.appendLast(.suppressWarnings, from: &parsedOptions)
    try commandLine.appendLast(.profileGenerate, from: &parsedOptions)
    try commandLine.appendLast(.profileUse, from: &parsedOptions)
    try commandLine.appendLast(.profileCoverageMapping, from: &parsedOptions)
    try commandLine.appendLast(.debugInfoForProfiling, from: &parsedOptions)
    if parsedOptions.hasArgument(.profileSampleUse) {
        try commandLine.appendLast(.profileSampleUse, from: &parsedOptions)
        // Use LLVM's "profi" to infer missing sample data from the profile.
        commandLine.appendFlag(.Xllvm)
        commandLine.appendFlag("-sample-profile-use-profi")
    }
    try commandLine.appendAllExcept(
      includeList: [.warningTreating],
      excludeList: [],
      from: &parsedOptions
    )
    try commandLine.appendLast(.sanitizeEQ, from: &parsedOptions)
    try commandLine.appendLast(.sanitizeRecoverEQ, from: &parsedOptions)
    try commandLine.appendLast(.sanitizeAddressUseOdrIndicator, from: &parsedOptions)
    if isFrontendArgSupported(.sanitizeStableAbiEQ) {
      try commandLine.appendLast(.sanitizeStableAbiEQ, from: &parsedOptions)
    }
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
    try commandLine.appendLast(.printDiagnosticGroups, from: &parsedOptions)
    try commandLine.appendLast(.scanDependencies, from: &parsedOptions)
    try commandLine.appendLast(.enableExperimentalConcisePoundFile, from: &parsedOptions)
    try commandLine.appendLast(.experimentalPackageInterfaceLoad, from: &parsedOptions)
    try commandLine.appendLast(.printEducationalNotes, from: &parsedOptions)
    try commandLine.appendLast(.diagnosticStyle, from: &parsedOptions)
    try commandLine.appendLast(.locale, from: &parsedOptions)
    try commandLine.appendLast(.localizationPath, from: &parsedOptions)
    try commandLine.appendLast(.requireExplicitAvailability, from: &parsedOptions)
    try commandLine.appendLast(.requireExplicitAvailabilityTarget, from: &parsedOptions)
    try commandLine.appendLast(.libraryLevel, from: &parsedOptions)
    try commandLine.appendLast(.lto, from: &parsedOptions)
    try commandLine.appendLast(.accessNotesPath, from: &parsedOptions)
    try commandLine.appendLast(.enableActorDataRaceChecks, .disableActorDataRaceChecks, from: &parsedOptions)
    if isFrontendArgSupported(.dumpAstFormat) {
      try commandLine.appendLast(.dumpAstFormat, from: &parsedOptions)
    }
    try commandLine.appendAll(.D, from: &parsedOptions)
    try commandLine.appendAll(.debugPrefixMap, .coveragePrefixMap, .filePrefixMap, from: &parsedOptions)
    try commandLine.appendAllArguments(.Xfrontend, from: &parsedOptions)
    try commandLine.appendLast(.warnConcurrency, from: &parsedOptions)
    if isFrontendArgSupported(.noAllocations) {
      try commandLine.appendLast(.noAllocations, from: &parsedOptions)
    }
    if isFrontendArgSupported(.compilerAssertions) {
      try commandLine.appendLast(.compilerAssertions, from: &parsedOptions)
    }
    try commandLine.appendAll(.enableExperimentalFeature,
                              .disableExperimentalFeature,
                              .enableUpcomingFeature,
                              .disableUpcomingFeature,
                              from: &parsedOptions)
    try commandLine.appendLast(.strictMemorySafety, .strictMemorySafetyMigrate, from: &parsedOptions)
    try commandLine.appendAll(.moduleAlias, from: &parsedOptions)
    if isFrontendArgSupported(.enableBareSlashRegex) {
      try commandLine.appendLast(.enableBareSlashRegex, from: &parsedOptions)
    }
    if isFrontendArgSupported(.strictConcurrency) {
      try commandLine.appendLast(.strictConcurrency, from: &parsedOptions)
    }
    if isFrontendArgSupported(.defaultIsolation) {
      try commandLine.appendLast(.defaultIsolation, from: &parsedOptions)
    }
    if kind == .scanDependencies,
        isFrontendArgSupported(.experimentalClangImporterDirectCc1Scan) {
      try commandLine.appendAll(
        .experimentalClangImporterDirectCc1Scan, from: &parsedOptions)
    }

    // Expand the -experimental-hermetic-seal-at-link flag
    if parsedOptions.hasArgument(.experimentalHermeticSealAtLink) {
      commandLine.appendFlag("-enable-llvm-vfe")
      commandLine.appendFlag("-enable-llvm-wme")
      commandLine.appendFlag("-conditional-runtime-records")
      commandLine.appendFlag("-internalize-at-link")
    }

    // ABI descriptors are mostly for modules with -enable-library-evolution.
    // We should also be able to emit ABI descriptor for modules without evolution.
    // However, doing so leads us to deserialize more contents from binary modules,
    // exposing more deserialization issues as a result.
    if !parsedOptions.hasArgument(.enableLibraryEvolution) &&
        isFrontendArgSupported(.emptyAbiDescriptor) {
      commandLine.appendFlag(.emptyAbiDescriptor)
    }

    if isFrontendArgSupported(.emitMacroExpansionFiles) {
      try commandLine.appendLast(.emitMacroExpansionFiles, from: &parsedOptions)
    }

    // Emit user-provided plugin paths, in order.
    if !isPlanJobForExplicitModule {
      if isFrontendArgSupported(.externalPluginPath) {
        try commandLine.appendAll(.pluginPath, .externalPluginPath, .loadPluginLibrary, .loadPluginExecutable, from: &parsedOptions)
      } else if isFrontendArgSupported(.pluginPath) {
        try commandLine.appendAll(.pluginPath, .loadPluginLibrary, from: &parsedOptions)
      }
    }

    if isFrontendArgSupported(.blockListFile) {
      try findBlocklists().forEach {
        commandLine.appendFlag(.blockListFile)
        try addPathArgument(VirtualPath.absolute($0), to: &commandLine, remap: jobNeedPathRemap)
      }
    }

    // Pass down -user-module-version if we are working with a compiler that
    // supports it.
    if let ver = parsedOptions.getLastArgument(.userModuleVersion)?.asSingle,
       isFrontendArgSupported(.userModuleVersion) {
      commandLine.appendFlag(.userModuleVersion)
      commandLine.appendFlag(ver)
    }

    if isFrontendArgSupported(.publicModuleName) {
      try commandLine.appendLast(.publicModuleName, from: &parsedOptions)
    }

    // Pass down -validate-clang-modules-once if we are working with a compiler that
    // supports it.
    if isFrontendArgSupported(.validateClangModulesOnce),
       isFrontendArgSupported(.clangBuildSessionFile) {
      try commandLine.appendLast(.validateClangModulesOnce, from: &parsedOptions)
      try commandLine.appendLast(.clangBuildSessionFile, from: &parsedOptions)
    }

    if isFrontendArgSupported(.enableBuiltinModule) {
      try commandLine.appendLast(.enableBuiltinModule, from: &parsedOptions)
    }

    if isFrontendArgSupported(.disableSandbox) {
      try commandLine.appendLast(.disableSandbox, from: &parsedOptions)
    }

    if isFrontendArgSupported(.disableDynamicActorIsolation) {
      try commandLine.appendLast(.disableDynamicActorIsolation, from: &parsedOptions)
    }

    if !directModuleCC1Mode, let workingDirectory = workingDirectory {
      // Add -Xcc -working-directory before any other -Xcc options to ensure it is
      // overridden by an explicit -Xcc -working-directory, although having a
      // different working directory is probably incorrect.
      commandLine.appendFlag(.Xcc)
      commandLine.appendFlag(.workingDirectory)
      commandLine.appendFlag(.Xcc)
      try addPathArgument(.absolute(workingDirectory), to: &commandLine, remap: jobNeedPathRemap)
    }

    // Only pass in a resource directory to the frontend if one was passed to
    // swift-driver. Make an exception for scan-dependencies jobs for now till
    // we figure out a remaining problem with in-process scanning.
    if parsedOptions.hasArgument(.resourceDir) || kind == .scanDependencies {
      try addPathOption(option: .resourceDir,
                        path: VirtualPath.lookup(frontendTargetInfo.runtimeResourcePath.path),
                        to: &commandLine,
                        remap: jobNeedPathRemap)
    }

    if self.useStaticResourceDir {
      commandLine.appendFlag("-use-static-resource-dir")
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

      // Always try to append -file-compilation-dir when debug info is used.
      // TODO: Should we support -fcoverage-compilation-dir?
      commandLine.appendFlag(.fileCompilationDir)
      if let compilationDir = parsedOptions.getLastArgument(.fileCompilationDir)?.asSingle {
        let compDirPath = try VirtualPath.intern(path: compilationDir)
        try addPathArgument(VirtualPath.lookup(compDirPath), to:&commandLine, remap: jobNeedPathRemap)
      } else if let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory {
        let compDirPath = VirtualPath.absolute(cwd)
        try addPathArgument(compDirPath, to:&commandLine, remap: jobNeedPathRemap)
      }
    }

    // CAS related options.
    if isCachingEnabled {
      commandLine.appendFlag(.cacheCompileJob)
      if let casPath = try Self.getOnDiskCASPath(parsedOptions: &parsedOptions,
                                                 toolchain: toolchain) {
        commandLine.appendFlag(.casPath)
        commandLine.appendFlag(casPath.pathString)
      }
      if let pluginPath = try Self.getCASPluginPath(parsedOptions: &parsedOptions,
                                                    toolchain: toolchain) {
        commandLine.appendFlag(.casPluginPath)
        commandLine.appendFlag(pluginPath.pathString)
      }
      try commandLine.appendAll(.casPluginOption, from: &parsedOptions)
      try commandLine.appendLast(.cacheRemarks, from: &parsedOptions)
      if !useClangIncludeTree {
        commandLine.appendFlag(.noClangIncludeTree)
      }
    }
    addCacheReplayMapping(to: &commandLine)

    // Pass through any subsystem flags.
    try commandLine.appendAll(.Xllvm, from: &parsedOptions)

    // Pass through all -Xcc flags if not under directModuleCC1Mode.
    if !directModuleCC1Mode {
      try commandLine.appendAll(.Xcc, from: &parsedOptions)
    }

    let (importedObjCHeader, precompiledObjCHeader) =
              try computeCanonicalObjCHeader(explicitModulePlanner: explicitModulePlanner)
    let objcHeaderFile = (kind == .scanDependencies) ? originalObjCHeaderFile : importedObjCHeader
    if let importedObjCHeader = objcHeaderFile, bridgingHeaderHandling != .ignored {
      if bridgingHeaderHandling == .precompiled, let pch = precompiledObjCHeader {
        // For explicit module build, we directly pass the compiled pch to
        // swift-frontend, rather than rely on swift-frontend to locate
        // the pch in the pchOutputDir and can start an implicit build in case
        // of a lookup failure.
        if parsedOptions.contains(.pchOutputDir) &&
           !parsedOptions.contains(.driverExplicitModuleBuild) {
          commandLine.appendFlag(.importObjcHeader)
          try addPathArgument(VirtualPath.lookup(importedObjCHeader), to:&commandLine, remap: jobNeedPathRemap)
          try commandLine.appendLast(.pchOutputDir, from: &parsedOptions)
          if !compilerMode.isSingleCompilation {
            commandLine.appendFlag(.pchDisableValidation)
          }
        } else {
          // If header chaining is enabled, pass objc header through `-import-objc-header` and
          // PCH file through `-import-pch`. Otherwise, pass either the PCH or header through
          // `-import-objc-header` option.
          if isFrontendArgSupported(.importPch), importedObjCHeader != originalObjCHeaderFile {
            commandLine.appendFlag(.importPch)
            try addPathArgument(VirtualPath.lookup(pch), to:&commandLine, remap: jobNeedPathRemap)
            if let originalHeader = originalObjCHeaderFile {
              commandLine.appendFlag(.importObjcHeader)
              try addPathArgument(VirtualPath.lookup(originalHeader), to:&commandLine, remap: jobNeedPathRemap)
            }
          } else {
            commandLine.appendFlag(.importObjcHeader)
            try addPathArgument(VirtualPath.lookup(pch), to:&commandLine, remap: jobNeedPathRemap)
          }
        }
      } else {
        commandLine.appendFlag(.importObjcHeader)
        try addPathArgument(VirtualPath.lookup(importedObjCHeader), to:&commandLine, remap: jobNeedPathRemap)
      }
    }

    // Pass bridging header chaining options.
    if isFrontendArgSupported(.autoBridgingHeaderChaining) {
      if bridgingHeaderChaining {
        commandLine.appendFlag(.autoBridgingHeaderChaining)
      } else {
        commandLine.appendFlag(.noAutoBridgingHeaderChaining)
      }
    }

    if parsedOptions.contains(.enableDeterministicCheck),
        isFrontendArgSupported(.enableDeterministicCheck) {
      commandLine.appendFlag(.enableDeterministicCheck)
      commandLine.appendFlag(.alwaysCompileOutputFiles)
      if enableCaching {
        commandLine.appendFlag(.cacheDisableReplay)
      }
    }

    // Pass along -no-verify-emitted-module-interface only if it's effective.
    // Assume verification by default as we want to know only when the user skips
    // the verification.
    if isFrontendArgSupported(.noVerifyEmittedModuleInterface) &&
       !parsedOptions.hasFlag(positive: .verifyEmittedModuleInterface,
                              negative: .noVerifyEmittedModuleInterface,
                              default: true) {
      commandLine.appendFlag("-no-verify-emitted-module-interface")
    }

    // Repl Jobs shouldn't include -module-name.
    if compilerMode != .repl && compilerMode != .intro {
      commandLine.appendFlags("-module-name", moduleOutputInfo.name)
    }

    if let packageName = packageName {
      commandLine.appendFlags("-package-name", packageName)
    }

    // Enable frontend Parseable-output, if needed.
    if parsedOptions.contains(.useFrontendParseableOutput) {
      commandLine.appendFlag("-frontend-parseable-output")
    }

    // If explicit auto-linking is enabled, ensure that compiler tasks do not produce
    // auto-link load commands in resulting object files.
    if parsedOptions.hasArgument(.explicitAutoLinking) {
      commandLine.appendFlag(.disableAllAutolinking)
    }

    savedUnknownDriverFlagsForSwiftFrontend.forEach {
      commandLine.appendFlag($0)
    }

    let toolchainStdlibPath = VirtualPath.lookup(frontendTargetInfo.runtimeResourcePath.path)
      .appending(components: frontendTargetInfo.target.triple.platformName() ?? "", "Swift.swiftmodule")
    let hasToolchainStdlib = try fileSystem.exists(toolchainStdlibPath)

    let skipMacroSearchPath = isPlanJobForExplicitModule && isFrontendArgSupported(.loadResolvedPlugin)
    // If the resource directory has the standard library, prefer the toolchain's plugins
    // to the platform SDK plugins.
    // For explicit module build, the resolved plugins are provided by scanner.
    if hasToolchainStdlib {
      try addPluginPathArguments(commandLine: &commandLine, skipMacroSearchPath: skipMacroSearchPath)
    }

    try toolchain.addPlatformSpecificCommonFrontendOptions(commandLine: &commandLine,
                                                           inputs: &inputs,
                                                           frontendTargetInfo: frontendTargetInfo,
                                                           driver: &self,
                                                           skipMacroOptions: skipMacroSearchPath)

    // Otherwise, prefer the platform's plugins.
    if !hasToolchainStdlib {
      try addPluginPathArguments(commandLine: &commandLine, skipMacroSearchPath: skipMacroSearchPath)
    }

    if let passPluginPath = parsedOptions.getLastArgument(.loadPassPluginEQ),
        isFrontendArgSupported(.loadPassPluginEQ) {
      commandLine.appendFlag("-load-pass-plugin=\(passPluginPath.asSingle)")
    }
  }

  mutating func addRuntimeLibraryFlags(commandLine: inout [Job.ArgTemplate]) throws {
    guard targetTriple.isWindows else { return }

    enum RuntimeFlavour {
      case MT
      case MTd
      case MD
      case MDd
    }

    let option = parsedOptions.getLastArgument(.libc)

    // NOTE: default to `/MD`.  This is different from `cl`'s default behaviour
    // of `/MT` on the command line, however, Visual Studio 2015 and newer will
    // default `/MD` as well.  Furthermore, this is far more useful of a mode
    // since the `/MT` mode requires that everything is statically linked.
    let runtime: RuntimeFlavour? = switch (option?.asSingle ?? "MD") {
      case "MD", "MultiThreadedDLL", "shared-ucrt":
        .MD
      case "MDd", "MultiThreadedDebugDLL", "shared-debug-ucrt":
        .MDd
      case "MT", "MultiThreaded", "static-ucrt":
        .MT
      case "MTd", "MultiThreadedDebug", "static-debug-ucrt":
        .MTd
      default:
        nil
    }

    guard let runtime else {
      diagnosticEngine.emit(.error_invalid_arg_value(arg: .libc, value: option!.asSingle))
      return
    }

    commandLine.appendFlag(.autolinkLibrary)
    commandLine.appendFlag("oldnames")

    commandLine.appendFlag(.autolinkLibrary)
    let name = switch (runtime) {
      case .MD: "msvcrt"
      case .MDd: "msvcrtd"
      case .MT: "libcmt"
      case .MTd: "libcmtd"
    }
    commandLine.appendFlag(name)

    commandLine.appendFlag(.Xcc)
    commandLine.appendFlag("-D_MT")

    if [.MD, .MDd].contains(runtime) {
      commandLine.appendFlag(.Xcc)
      commandLine.appendFlag("-D_DLL")
    }
  }

  mutating func addBridgingHeaderPCHCacheKeyArguments(commandLine: inout [Job.ArgTemplate],
                                                      pchCompileJob: Job?) throws {
    guard let pchJob = pchCompileJob, isCachingEnabled else { return }

    assert(pchJob.outputCacheKeys.count == 1, "Expect one and only one cache key from pch job")
    guard let bridgingHeaderCacheKey = pchJob.outputCacheKeys.first?.value else {
      fatalError("pch job doesn't have an associated cache key")
    }
    commandLine.appendFlag("-bridging-header-pch-key")
    commandLine.appendFlag(bridgingHeaderCacheKey)
  }

  mutating func addFrontendSupplementaryOutputArguments(commandLine: inout [Job.ArgTemplate],
                                                        primaryInputs: [TypedVirtualPath],
                                                        inputsGeneratingCodeCount: Int,
                                                        inputOutputMap: inout [TypedVirtualPath: [TypedVirtualPath]],
                                                        moduleOutputInfo: ModuleOutputInfo,
                                                        moduleOutputPaths: SupplementalModuleTargetOutputPaths,
                                                        includeModuleTracePath: Bool,
                                                        indexFilePath: TypedVirtualPath?) throws -> [TypedVirtualPath] {
    var flaggedInputOutputPairs: [(flag: String, input: TypedVirtualPath?, output: TypedVirtualPath)] = []

    /// Add output of a particular type, if needed.
    func addOutputOfType(
      outputType: FileType,
      finalOutputPath: VirtualPath.Handle?,
      input: TypedVirtualPath?,
      flag: String
    ) throws {
      // If there is no final output, there's nothing to do.
      guard let finalOutputPath = finalOutputPath else { return }

      // If the whole of the compiler output is this type, there's nothing to
      // do.
      if outputType == compilerOutputType { return }

      // Compute the output path based on the input path (if there is one), or
      // use the final output.
      let outputPath: VirtualPath.Handle
      if let input = input {
        if let outputFileMapPath = try outputFileMap?.existingOutput(inputFile: input.fileHandle, outputType: outputType) {
          outputPath = outputFileMapPath
        } else if let output = inputOutputMap[input]?.first, output.file != .standardOutput, compilerOutputType != nil {
          // Alongside primary output
          outputPath = try output.file.replacingExtension(with: outputType).intern()
        } else {
          outputPath = try VirtualPath.createUniqueTemporaryFile(RelativePath(validating: input.file.basenameWithoutExt.appendingFileTypeExtension(outputType))).intern()
        }

        // Update the input-output file map.
        let output = TypedVirtualPath(file: outputPath, type: outputType)
        if inputOutputMap[input] != nil {
          inputOutputMap[input]!.append(output)
        } else {
          inputOutputMap[input] = [output]
        }
      } else {
        outputPath = finalOutputPath
      }

      flaggedInputOutputPairs.append((flag: flag, input: input, output: TypedVirtualPath(file: outputPath, type: outputType)))
    }

    /// Add all of the outputs needed for a given input.
    func addAllOutputsFor(input: TypedVirtualPath?,
        moduleOutputInfo: ModuleOutputInfo,
        moduleOutputPaths: SupplementalModuleTargetOutputPaths) throws {
      if !emitModuleSeparately {
        // Generate the module files with the main job.
        try addOutputOfType(
          outputType: .swiftModule,
          finalOutputPath: moduleOutputInfo.output?.outputPath,
          input: input,
          flag: "-emit-module-path")
        try addOutputOfType(
          outputType: .swiftDocumentation,
          finalOutputPath: moduleOutputPaths.moduleDocOutputPath,
          input: input,
          flag: "-emit-module-doc-path")
        try addOutputOfType(
          outputType: .swiftSourceInfoFile,
          finalOutputPath: moduleOutputPaths.moduleSourceInfoPath,
          input: input,
          flag: "-emit-module-source-info-path")
      }

      try addOutputOfType(
        outputType: .dependencies,
        finalOutputPath: dependenciesFilePath,
        input: input,
        flag: "-emit-dependencies-path")

      try addOutputOfType(
        outputType: .swiftConstValues,
        finalOutputPath: constValuesFilePath,
        input: input,
        flag: "-emit-const-values-path")

      try addOutputOfType(
        outputType: .swiftDeps,
        finalOutputPath: referenceDependenciesPath,
        input: input,
        flag: "-emit-reference-dependencies-path")

      try addOutputOfType(
        outputType: self.optimizationRecordFileType ?? .yamlOptimizationRecord,
        finalOutputPath: optimizationRecordPath,
        input: input,
        flag: "-save-optimization-record-path")

      try addOutputOfType(
        outputType: .diagnostics,
        finalOutputPath: serializedDiagnosticsFilePath,
        input: input,
        flag: "-serialize-diagnostics-path")
    }

    if compilerMode.usesPrimaryFileInputs {
      for input in primaryInputs {
        try addAllOutputsFor(input: input,
            moduleOutputInfo: moduleOutputInfo,
            moduleOutputPaths: moduleOutputPaths)
      }
    } else {
      try addAllOutputsFor(input: nil,
        moduleOutputInfo: moduleOutputInfo,
        moduleOutputPaths: moduleOutputPaths)

      if !emitModuleSeparately {
        // Outputs that only make sense when the whole module is processed
        // together.
        try addOutputOfType(
          outputType: .objcHeader,
          finalOutputPath: objcGeneratedHeaderPath,
          input: nil,
          flag: "-emit-objc-header-path")

        try addOutputOfType(
          outputType: .swiftInterface,
          finalOutputPath: moduleOutputPaths.swiftInterfacePath,
          input: nil,
          flag: "-emit-module-interface-path")

        try addOutputOfType(
          outputType: .privateSwiftInterface,
          finalOutputPath: moduleOutputPaths.swiftPrivateInterfacePath,
          input: nil,
          flag: "-emit-private-module-interface-path")

        if let pkgName = packageName, !pkgName.isEmpty {
          try addOutputOfType(
            outputType: .packageSwiftInterface,
            finalOutputPath: moduleOutputPaths.swiftPackageInterfacePath,
            input: nil,
            flag: "-emit-package-module-interface-path")
        }
        try addOutputOfType(
          outputType: .tbd,
          finalOutputPath: tbdPath,
          input: nil,
          flag: "-emit-tbd-path")

        if let abiDescriptorPath = moduleOutputPaths.abiDescriptorFilePath {
          try addOutputOfType(outputType: .jsonABIBaseline,
                          finalOutputPath: abiDescriptorPath.fileHandle,
                          input: nil,
                          flag: "-emit-abi-descriptor-path")
        }

        try addOutputOfType(
          outputType: .jsonAPIDescriptor,
          finalOutputPath: moduleOutputPaths.apiDescriptorFilePath,
          input: nil,
          flag: "-emit-api-descriptor-path")
      }
    }

    if parsedOptions.hasArgument(.updateCode) {
      guard compilerMode == .standardCompile else {
        diagnosticEngine.emit(.error_update_code_not_supported(in: compilerMode))
        throw ErrorDiagnostics.emitted
      }
      assert(primaryInputs.count == 1, "Standard compile job had more than one primary input")
      let input = primaryInputs[0]
      let remapOutputPath: VirtualPath
      if let outputFileMapPath = try outputFileMap?.existingOutput(inputFile: input.fileHandle, outputType: .remap) {
        remapOutputPath = VirtualPath.lookup(outputFileMapPath)
      } else if let output = inputOutputMap[input]?.first, output.file != .standardOutput {
        // Alongside primary output
        remapOutputPath = try output.file.replacingExtension(with: .remap)
      } else {
        remapOutputPath =
          try VirtualPath.createUniqueTemporaryFile(RelativePath(validating: input.file.basenameWithoutExt.appendingFileTypeExtension(.remap)))
      }

      flaggedInputOutputPairs.append((flag: "-emit-remap-file-path",
                                      input: input,
                                      output: TypedVirtualPath(file: remapOutputPath.intern(), type: .remap)))
    }

    if includeModuleTracePath, let tracePath = loadedModuleTracePath {
      flaggedInputOutputPairs.append((flag: "-emit-loaded-module-trace-path",
                                      input: nil,
                                      output: TypedVirtualPath(file: tracePath, type: .moduleTrace)))
    }

    if inputsGeneratingCodeCount * FileType.allCases.count > fileListThreshold {
      var entries = [VirtualPath.Handle: [FileType: VirtualPath.Handle]]()
      for input in primaryInputs {
        if let output = inputOutputMap[input]?.first {
          try addEntry(&entries, input: input, output: output)
        } else {
          // Primary inputs are expected to appear in the output file map even
          // if they have no corresponding outputs.
          entries[input.fileHandle] = [:]
        }
      }

      if primaryInputs.isEmpty {
        // To match the legacy driver behavior, make sure we add the first input file
        // to the output file map if compiling without primary inputs (WMO), even
        // if there aren't any corresponding outputs.
        guard let firstSourceInputHandle = inputFiles.first(where:{ $0.type == .swift })?.fileHandle  else {
          fatalError("Formulating swift-frontend invocation without any input .swift files")
        }
        entries[firstSourceInputHandle] = [:]
      }

      for flaggedPair in flaggedInputOutputPairs {
        try addEntry(&entries, input: flaggedPair.input, output: flaggedPair.output)
      }
      // To match the legacy driver behavior, make sure we add an entry for the
      // file under indexing and the primary output file path.
      if let indexFilePath = indexFilePath, let idxOutput = inputOutputMap[indexFilePath]?.first {
        entries[indexFilePath.fileHandle] = [.indexData: idxOutput.fileHandle]
      }
      let outputFileMap = OutputFileMap(entries: entries)
      let fileList = try VirtualPath.createUniqueFilelist(RelativePath(validating: "supplementaryOutputs"),
                                                          .outputFileMap(outputFileMap))
      commandLine.appendFlag(.supplementaryOutputFileMap)
      commandLine.appendPath(fileList)
    } else {
      for flaggedPair in flaggedInputOutputPairs {
        // Add the appropriate flag.
        commandLine.appendFlag(flaggedPair.flag)
        commandLine.appendPath(flaggedPair.output.file)
      }
    }

    return flaggedInputOutputPairs.map { $0.output }
  }

  mutating func addCommonSymbolGraphOptions(commandLine: inout [Job.ArgTemplate],
                                            includeGraph: Bool = true) throws {
    if includeGraph {
      try commandLine.appendLast(.emitSymbolGraph, from: &parsedOptions)
      try commandLine.appendLast(.emitSymbolGraphDir, from: &parsedOptions)
    }
    try commandLine.appendLast(.includeSpiSymbols, from: &parsedOptions)
    try commandLine.appendLast(.emitExtensionBlockSymbols, .omitExtensionBlockSymbols, from: &parsedOptions)
    try commandLine.appendLast(.symbolGraphMinimumAccessLevel, from: &parsedOptions)
  }

  mutating func addEntry(_ entries: inout [VirtualPath.Handle: [FileType: VirtualPath.Handle]], input: TypedVirtualPath?, output: TypedVirtualPath) throws {
    let entryInput: VirtualPath.Handle
    if let input = input?.fileHandle, input != OutputFileMap.singleInputKey {
      entryInput = input
    } else {
      guard let firstSourceInputHandle = inputFiles.first(where:{ $0.type == .swift })?.fileHandle else {
        fatalError("Formulating swift-frontend invocation without any input .swift files")
      }
      entryInput = firstSourceInputHandle
    }
    let inputEntry = isCachingEnabled ? remapPath(VirtualPath.lookup(entryInput)).intern() : entryInput
    entries[inputEntry, default: [:]][output.type] = output.fileHandle
  }

  mutating func addPluginPathArguments(commandLine: inout [Job.ArgTemplate], skipMacroSearchPath: Bool) throws {
    guard isFrontendArgSupported(.pluginPath) else {
      return
    }
    let pluginPathRoot = VirtualPath.absolute(try toolchain.executableDir.parentDirectory)

    if isFrontendArgSupported(.inProcessPluginServerPath) {
      commandLine.appendFlag(.inProcessPluginServerPath)
#if os(Windows)
      commandLine.appendPath(pluginPathRoot.appending(components: "bin", sharedLibraryName("SwiftInProcPluginServer")))
#else
      commandLine.appendPath(pluginPathRoot.appending(components: "lib", "swift", "host", sharedLibraryName("libSwiftInProcPluginServer")))
#endif
    }

    guard !skipMacroSearchPath else {
      return
    }

    // Default paths for compiler plugins found within the toolchain
    // (loaded as shared libraries).
    commandLine.appendFlag(.pluginPath)
    commandLine.appendPath(pluginPathRoot.pluginPath)

    commandLine.appendFlag(.pluginPath)
    commandLine.appendPath(pluginPathRoot.localPluginPath)
  }

  /// In Explicit Module Build mode, distinguish between main module jobs and intermediate dependency build jobs,
  /// such as Swift modules built from .swiftmodule files and Clang PCMs.
  public func isExplicitMainModuleJob(job: Job) -> Bool {
    return job.moduleName == moduleOutputInfo.name
  }
}

extension Driver {
  private func getAbsolutePathFromVirtualPath(_ path: VirtualPath) -> AbsolutePath? {
    guard let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory else {
      return nil
    }
    return path.resolvedRelativePath(base: cwd).absolutePath
  }

  private mutating func remapPath(absolute path: AbsolutePath) -> AbsolutePath {
    guard !prefixMapping.isEmpty else {
      return path
    }
    for (prefix, value) in prefixMapping {
      if path.isDescendantOfOrEqual(to: prefix) {
        return value.appending(path.relative(to: prefix))
      }
    }
    return path
  }

  public mutating func remapPath(_ path: VirtualPath) -> VirtualPath {
    guard !prefixMapping.isEmpty,
      let absPath = getAbsolutePathFromVirtualPath(path) else {
      return path
    }
    let mappedPath = remapPath(absolute: absPath)
    return try! VirtualPath(path: mappedPath.pathString)
  }

  /// Helper function to add path to commandLine. Function will validate the path, and remap the path if needed.
  public mutating func addPathArgument(_ path: VirtualPath, to commandLine: inout [Job.ArgTemplate], remap: Bool = true) throws {
    guard remap && isCachingEnabled else {
      commandLine.appendPath(path)
      return
    }
    let mappedPath = remapPath(path)
    commandLine.appendPath(mappedPath)
  }

  public mutating func addPathOption(_ option: ParsedOption, to commandLine: inout [Job.ArgTemplate], remap: Bool = true) throws {
    let path = try VirtualPath(path: option.argument.asSingle)
    try addPathOption(option: option.option, path: path, to: &commandLine, remap: remap)
  }

  public mutating func addPathOption(option: Option, path: VirtualPath, to commandLine: inout [Job.ArgTemplate], remap: Bool = true) throws {
    let needRemap = remap && isCachingEnabled && option.attributes.contains(.argumentIsPath) &&
                    !option.attributes.contains(.cacheInvariant)
    let commandPath = needRemap ? remapPath(path) : path
    if option.kind == .joined {
      commandLine.append(.joinedOptionAndPath(option.spelling, commandPath))
    } else {
      // All other kinds that involves a path can be added as separated args.
      commandLine.appendFlag(option)
      commandLine.appendPath(commandPath)
    }
  }

  /// Helper function to add last argument with path to command-line.
  public mutating func addLastArgumentWithPath(_ options: Option...,
                                               to commandLine: inout [Job.ArgTemplate],
                                               remap: Bool = true) throws {
    guard let parsedOption = parsedOptions.last(for: options) else {
      return
    }
    try addPathOption(parsedOption, to: &commandLine, remap: remap)
  }

  /// Helper function to add all arguments with path to command-line.
  public mutating func addAllArgumentsWithPath(_ options: Option...,
                                               to commandLine: inout [Job.ArgTemplate],
                                               remap: Bool) throws {
    for matching in parsedOptions.arguments(for: options) {
      try addPathOption(matching, to: &commandLine, remap: remap)
    }
  }

  public mutating func addCacheReplayMapping(to commandLine: inout [Job.ArgTemplate]) {
    if isCachingEnabled && isFrontendArgSupported(.cacheReplayPrefixMap) {
      for (key, value) in prefixMapping {
        commandLine.appendFlag("-cache-replay-prefix-map")
        if isFrontendArgSupported(.scannerPrefixMapPaths) {
          commandLine.appendFlag(value.pathString)
          commandLine.appendFlag(key.pathString)
        } else {
          commandLine.appendFlag(value.pathString + "=" + key.pathString)
        }
      }
    }
  }
}

extension Driver {
  public mutating func computeOutputCacheKeyForJob(commandLine: [Job.ArgTemplate],
                                                   inputs: [(TypedVirtualPath, Int)]) throws -> [TypedVirtualPath: String] {
    // No caching setup, return empty dictionary.
    guard let cas = self.cas else {
      return [:]
    }
    // Resolve command-line first.
    let arguments: [String] = try executor.resolver.resolveArgumentList(for: commandLine)

    return try inputs.reduce(into: [:]) { keys, input in
      keys[input.0] = try cas.computeCacheKey(commandLine: arguments, index: input.1)
    }
  }

  public mutating func computeOutputCacheKey(commandLine: [Job.ArgTemplate],
                                             index: Int) throws -> String? {
    // No caching setup, return empty dictionary.
    guard let cas = self.cas else {
      return nil
    }
    // Resolve command-line first.
    let arguments: [String] = try executor.resolver.resolveArgumentList(for: commandLine)
    return try cas.computeCacheKey(commandLine: arguments, index: index)
  }
}

// Generate reproducer.
extension Driver {
  var supportsReproducer: Bool {
    isFrontendArgSupported(.genReproducer) && enableCaching
  }

  static func generateReproducer(_ job: Job, _ output: VirtualPath) -> Job {
    var reproJob = job
    reproJob.commandLine.appendFlag(.genReproducer)
    reproJob.commandLine.appendFlag(.genReproducerDir)
    reproJob.commandLine.appendPath(output)
    reproJob.commandLine.removeAll {
      guard case let .flag(opt) = $0 else {
        return false
      }
      return opt == Option.frontendParseableOutput.spelling
    }
    reproJob.outputs.removeAll()
    reproJob.outputCacheKeys.removeAll()
    return reproJob
  }
}

extension ParsedOptions {
  /// Checks whether experimental embedded mode is enabled.
  var isEmbeddedEnabled: Bool {
    mutating get {
      let experimentalFeatures = self.arguments(for: .enableExperimentalFeature)
      return experimentalFeatures.map(\.argument).map(\.asSingle).contains("Embedded")
    }
  }
}
