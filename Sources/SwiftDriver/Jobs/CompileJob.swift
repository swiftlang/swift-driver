//===--------------- CompileJob.swift - Swift Compilation Job -------------===//
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

import struct TSCBasic.RelativePath

extension Driver {
  /// Add the appropriate compile mode option to the command line for a compile job.
  mutating func addCompileModeOption(outputType: FileType?, commandLine: inout [Job.ArgTemplate]) {
    if let compileOption = outputType?.frontendCompileOption {
      commandLine.appendFlag(compileOption)
    } else {
      guard let compileModeOption = parsedOptions.getLast(in: .modes) else {
        fatalError("We were told to perform a standard compile, but no mode option was passed to the driver.")
      }

      commandLine.appendFlag(compileModeOption.option)
    }
  }

  mutating func computeIndexUnitOutput(for input: TypedVirtualPath, outputType: FileType, topLevel: Bool) throws -> TypedVirtualPath? {
    if let path = try outputFileMap?.existingOutput(inputFile: input.fileHandle, outputType: .indexUnitOutputPath) {
      return TypedVirtualPath(file: path, type: outputType)
    }
    if topLevel {
      if let baseOutput = parsedOptions.getLastArgument(.indexUnitOutputPath)?.asSingle,
         let baseOutputPath = try? VirtualPath.intern(path: baseOutput) {
        return TypedVirtualPath(file: baseOutputPath, type: outputType)
      }
    }
    return nil
  }

  mutating func computePrimaryOutput(for input: TypedVirtualPath, outputType: FileType,
                                        isTopLevel: Bool) throws -> TypedVirtualPath {
    if let path = try outputFileMap?.existingOutput(inputFile: input.fileHandle, outputType: outputType) {
      return TypedVirtualPath(file: path, type: outputType)
    }

    if isTopLevel {
      if let baseOutput = parsedOptions.getLastArgument(.o)?.asSingle,
         let baseOutputPath = try? VirtualPath.intern(path: baseOutput) {
        return TypedVirtualPath(file: baseOutputPath, type: outputType)
      } else if compilerOutputType?.isTextual == true {
        return TypedVirtualPath(file: .standardOutput, type: outputType)
      } else if outputType == .swiftModule, let moduleOutput = moduleOutputInfo.output {
        return TypedVirtualPath(file: moduleOutput.outputPath, type: outputType)
      }
    }

    let baseName: String
    if !compilerMode.usesPrimaryFileInputs && numThreads == 0 {
      baseName = moduleOutputInfo.name
    } else {
      baseName = input.file.basenameWithoutExt
    }

    if !isTopLevel {
      return TypedVirtualPath(file: try VirtualPath.createUniqueTemporaryFile(.init(validating: baseName.appendingFileTypeExtension(outputType))).intern(),
                              type: outputType)
    }
    return TypedVirtualPath(file: try useWorkingDirectory(try .init(validating: baseName.appendingFileTypeExtension(outputType))).intern(), type: outputType)
  }

  /// Is this compile job top-level
  func isTopLevelOutput(type: FileType?) -> Bool {
    switch type {
    case .assembly, .sil, .raw_sil, .raw_llvmIr, .llvmIR, .ast, .jsonDependencies, .sib,
          .raw_sib, .importedModules, .indexData:
      return true
    case .object:
      return (linkerOutputType == nil)
    case .llvmBitcode:
      if compilerOutputType != .llvmBitcode {
        // The compiler output isn't bitcode, so bitcode isn't top-level (-embed-bitcode).
        return false
      } else {
        // When -lto is set, .bc will be used for linking. Otherwise, .bc is
        // top-level output (-emit-bc)
        return lto == nil || linkerOutputType == nil
      }
    case .swiftModule:
      return compilerMode.isSingleCompilation && moduleOutputInfo.output?.isTopLevel ?? false
    case .swift, .image, .dSYM, .dependencies, .emitModuleDependencies, .autolink,
         .swiftDocumentation, .swiftInterface, .privateSwiftInterface, .packageSwiftInterface, .swiftSourceInfoFile,
         .diagnostics, .emitModuleDiagnostics, .objcHeader, .swiftDeps, .remap, .tbd,
         .moduleTrace, .yamlOptimizationRecord, .bitstreamOptimizationRecord, .pcm, .pch,
         .clangModuleMap, .jsonCompilerFeatures, .jsonTargetInfo, .jsonSwiftArtifacts,
         .indexUnitOutputPath, .modDepCache, .jsonAPIBaseline, .jsonABIBaseline,
         .swiftConstValues, .jsonAPIDescriptor, .moduleSummary, .moduleSemanticInfo,
         .cachedDiagnostics, .jsonSupportedFeatures, nil:
      return false
    }
  }

  /// Add the compiler inputs for a frontend compilation job, and return the
  /// corresponding primary set of outputs and, if not identical, the output
  /// paths to record in the index data (empty otherwise).
  mutating func addCompileInputs(primaryInputs: [TypedVirtualPath],
                                 indexFilePath: TypedVirtualPath?,
                                 inputs: inout [TypedVirtualPath],
                                 inputOutputMap: inout [TypedVirtualPath: [TypedVirtualPath]],
                                 outputType: FileType?,
                                 commandLine: inout [Job.ArgTemplate])
  throws -> ([TypedVirtualPath], [TypedVirtualPath]) {
    let useInputFileList = shouldUseInputFileList
    if let sourcesFileList = allSourcesFileList {
      commandLine.appendFlag(.filelist)
      commandLine.appendPath(sourcesFileList)
    } else if shouldUseInputFileList {
      let swiftInputs = inputFiles.filter(\.type.isPartOfSwiftCompilation)
      let remappedSourcesFileList = try VirtualPath.createUniqueFilelist(RelativePath(validating: "sources"),
                                                                         .list(swiftInputs.map{ return remapPath($0.file) }))
      // Remember the filelist created.
      self.allSourcesFileList = remappedSourcesFileList
      commandLine.appendFlag(.filelist)
      commandLine.appendPath(remappedSourcesFileList)
    }

    let usePrimaryInputFileList = primaryInputs.count > fileListThreshold
    if usePrimaryInputFileList {
      // primary file list
      commandLine.appendFlag(.primaryFilelist)
      let fileList = try VirtualPath.createUniqueFilelist(RelativePath(validating: "primaryInputs"),
                                                          .list(primaryInputs.map{ return remapPath($0.file) }))
      commandLine.appendPath(fileList)
    }

    let isTopLevel = isTopLevelOutput(type: outputType)

    // If we will be passing primary files via -primary-file, form a set of primary input files so
    // we can check more quickly.
    let usesPrimaryFileInputs: Bool
    // N.B. We use an array instead of a hashed collection like a set because
    // TypedVirtualPaths are quite expensive to hash. To the point where a
    // linear scan beats Set.contains by a factor of 4 for heavy workloads.
    let primaryInputFiles: [TypedVirtualPath]
    if compilerMode.usesPrimaryFileInputs {
      assert(!primaryInputs.isEmpty)
      usesPrimaryFileInputs = true
      primaryInputFiles = primaryInputs
    } else if let path = indexFilePath {
      // If -index-file is used, we perform a single compile but pass the
      // -index-file-path as a primary input file.
      usesPrimaryFileInputs = true
      primaryInputFiles = [path]
    } else {
      usesPrimaryFileInputs = false
      primaryInputFiles = []
    }

    let isMultithreaded = numThreads > 0

    // Add each of the input files.
    var primaryOutputs: [TypedVirtualPath] = []
    var primaryIndexUnitOutputs: [TypedVirtualPath] = []
    var indexUnitOutputDiffers = false
    let firstSwiftInput = inputs.count
    for input in self.inputFiles where input.type.isPartOfSwiftCompilation {
      inputs.append(input)

      let isPrimary = usesPrimaryFileInputs && primaryInputFiles.contains(input)
      if isPrimary {
        if !usePrimaryInputFileList {
          try addPathOption(option: .primaryFile, path: input.file, to:&commandLine)
        }
      } else {
        if !useInputFileList {
          try addPathArgument(input.file, to: &commandLine)
        }
      }

      // If there is a primary output or we are doing multithreaded compiles,
      // add an output for the input.
      if let outputType = outputType,
        isPrimary || (!usesPrimaryFileInputs && isMultithreaded && outputType.isAfterLLVM) {
        let output = try computePrimaryOutput(for: input,
                                              outputType: outputType,
                                              isTopLevel: isTopLevel)
        primaryOutputs.append(output)
        inputOutputMap[input] = [output]

        if let indexUnitOut = try computeIndexUnitOutput(for: input, outputType: outputType, topLevel: isTopLevel) {
          indexUnitOutputDiffers = true
          primaryIndexUnitOutputs.append(indexUnitOut)
        } else {
          primaryIndexUnitOutputs.append(output)
        }
      }
    }

    // When not using primary file inputs or multithreading, add a single output.
    if let outputType = outputType,
       !usesPrimaryFileInputs && !(isMultithreaded && outputType.isAfterLLVM) {
      let input = TypedVirtualPath(file: OutputFileMap.singleInputKey, type: inputs[firstSwiftInput].type)
      let output = try computePrimaryOutput(for: input,
                                            outputType: outputType,
                                            isTopLevel: isTopLevel)
      primaryOutputs.append(output)
      inputOutputMap[input] = [output]

      if let indexUnitOut = try computeIndexUnitOutput(for: input, outputType: outputType, topLevel: isTopLevel) {
        indexUnitOutputDiffers = true
        primaryIndexUnitOutputs.append(indexUnitOut)
      } else {
        primaryIndexUnitOutputs.append(output)
      }
    }

    if !indexUnitOutputDiffers {
      primaryIndexUnitOutputs.removeAll()
    } else {
      assert(primaryOutputs.count == primaryIndexUnitOutputs.count)
    }

    return (primaryOutputs, primaryIndexUnitOutputs)
  }

  /// Form a compile job, which executes the Swift frontend to produce various outputs.
  mutating func compileJob(primaryInputs: [TypedVirtualPath],
                           outputType: FileType?,
                           addJobOutputs: ([TypedVirtualPath]) -> Void,
                           pchCompileJob: Job?,
                           emitModuleTrace: Bool,
                           produceCacheKey: Bool)
  throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = []
    // Used to map primaryInputs to primaryOutputs
    var inputOutputMap = [TypedVirtualPath: [TypedVirtualPath]]()

    commandLine.appendFlag("-frontend")
    addCompileModeOption(outputType: outputType, commandLine: &commandLine)

    let indexFilePath: TypedVirtualPath?
    if let indexFileArg = parsedOptions.getLastArgument(.indexFilePath)?.asSingle {
      let path = try VirtualPath(path: indexFileArg)
      indexFilePath = inputFiles.first { $0.file == path }
    } else {
      indexFilePath = nil
    }

    let (primaryOutputs, primaryIndexUnitOutputs) =
      try addCompileInputs(primaryInputs: primaryInputs,
                           indexFilePath: indexFilePath,
                           inputs: &inputs,
                           inputOutputMap: &inputOutputMap,
                           outputType: outputType,
                           commandLine: &commandLine)
    outputs += primaryOutputs

    // FIXME: optimization record arguments are added before supplementary outputs
    // for compatibility with the integrated driver's test suite. We should adjust the tests
    // so we can organize this better.
    // -save-optimization-record and -save-optimization-record= have different meanings.
    // In this case, we specifically want to pass the EQ variant to the frontend
    // to control the output type of optimization remarks (YAML or bitstream).
    try commandLine.appendLast(.saveOptimizationRecordEQ, from: &parsedOptions)
    try commandLine.appendLast(.saveOptimizationRecordPasses, from: &parsedOptions)

    let inputsGeneratingCodeCount = primaryInputs.isEmpty
      ? inputs.count
      : primaryInputs.count

    outputs += try addFrontendSupplementaryOutputArguments(
      commandLine: &commandLine,
      primaryInputs: primaryInputs,
      inputsGeneratingCodeCount: inputsGeneratingCodeCount,
      inputOutputMap: &inputOutputMap,
      moduleOutputInfo: self.moduleOutputInfo,
      moduleOutputPaths: self.moduleOutputPaths,
      includeModuleTracePath: emitModuleTrace,
      indexFilePath: indexFilePath)

    // Forward migrator flags.
    try commandLine.appendLast(.apiDiffDataFile, from: &parsedOptions)
    try commandLine.appendLast(.apiDiffDataDir, from: &parsedOptions)
    try commandLine.appendLast(.dumpUsr, from: &parsedOptions)

    if parsedOptions.hasArgument(.parseStdlib) {
      commandLine.appendFlag(.disableObjcAttrRequiresFoundationModule)
    }

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .compile)
    try addRuntimeLibraryFlags(commandLine: &commandLine)

    if Driver.canDoCrossModuleOptimization(parsedOptions: &parsedOptions) &&
       // For historical reasons, -cross-module-optimization turns on "aggressive" CMO
       // which is different from "default" CMO.
       !parsedOptions.hasArgument(.CrossModuleOptimization) &&
       !parsedOptions.hasArgument(.EnableCMOEverything) {
      assert(!emitModuleSeparately, "Cannot emit module separately with cross-module-optimization")
      commandLine.appendFlag("-enable-default-cmo")
    }

    if parsedOptions.hasArgument(.parseAsLibrary, .emitLibrary) {
      commandLine.appendFlag(.parseAsLibrary)
    }

    try commandLine.appendLast(.parseSil, from: &parsedOptions)

    try commandLine.appendLast(.migrateKeepObjcVisibility, from: &parsedOptions)

    if numThreads > 0 {
      commandLine.appendFlags("-num-threads", numThreads.description)
    }

    // Add primary outputs.
    if primaryOutputs.count > fileListThreshold {
      commandLine.appendFlag(.outputFilelist)
      let fileList = try VirtualPath.createUniqueFilelist(RelativePath(validating: "outputs"),
                                                          .list(primaryOutputs.map { $0.file }))
      commandLine.appendPath(fileList)
    } else {
      for primaryOutput in primaryOutputs {
        commandLine.appendFlag(.o)
        commandLine.appendPath(primaryOutput.file)
      }
    }

    // Add index unit output paths if needed.
    if !primaryIndexUnitOutputs.isEmpty {
      if primaryIndexUnitOutputs.count > fileListThreshold {
        commandLine.appendFlag(.indexUnitOutputPathFilelist)
        let fileList = try VirtualPath.createUniqueFilelist(RelativePath(validating: "index-unit-outputs"),
                                                            .list(primaryIndexUnitOutputs.map { $0.file }))
        commandLine.appendPath(fileList)
      } else {
        for primaryIndexUnitOutput in primaryIndexUnitOutputs {
          commandLine.appendFlag(.indexUnitOutputPath)
          commandLine.appendPath(primaryIndexUnitOutput.file)
        }
      }
    }

    try commandLine.appendLast(.embedBitcodeMarker, from: &parsedOptions)

    // For `-index-file` mode add `-disable-typo-correction`, since the errors
    // will be ignored and it can be expensive to do typo-correction.
    if compilerOutputType == FileType.indexData {
      commandLine.appendFlag(.disableTypoCorrection)
    }

    if parsedOptions.contains(.indexStorePath) {
      try commandLine.appendLast(.indexStorePath, from: &parsedOptions)
      if !parsedOptions.contains(.indexIgnoreSystemModules) {
        commandLine.appendFlag(.indexSystemModules)
      }
      try commandLine.appendLast(.indexIgnoreClangModules, from: &parsedOptions)
      try commandLine.appendLast(.indexIncludeLocals, from: &parsedOptions)
    }

    if parsedOptions.contains(.debugInfoStoreInvocation) ||
       toolchain.shouldStoreInvocationInDebugInfo {
      commandLine.appendFlag(.debugInfoStoreInvocation)
    }

    if let map = toolchain.globalDebugPathRemapping {
      commandLine.appendFlag(.debugPrefixMap)
      commandLine.appendFlag(map)
    }

    try commandLine.appendLast(.trackSystemDependencies, from: &parsedOptions)
    try commandLine.appendLast(.CrossModuleOptimization, from: &parsedOptions)
    try commandLine.appendLast(.EnableCMOEverything, from: &parsedOptions)
    try commandLine.appendLast(.ExperimentalPerformanceAnnotations, from: &parsedOptions)

    try commandLine.appendLast(.runtimeCompatibilityVersion, from: &parsedOptions)
    try commandLine.appendLast(.disableAutolinkingRuntimeCompatibility, from: &parsedOptions)
    try commandLine.appendLast(.disableAutolinkingRuntimeCompatibilityDynamicReplacements, from: &parsedOptions)
    try commandLine.appendLast(.disableAutolinkingRuntimeCompatibilityConcurrency, from: &parsedOptions)

    try commandLine.appendLast(.checkApiAvailabilityOnly, from: &parsedOptions)

    try addCommonSymbolGraphOptions(commandLine: &commandLine,
                                    includeGraph: compilerMode.isSingleCompilation)

    addJobOutputs(outputs)

    // Bridging header is needed for compiling these .swift sources.
    if let pchPath = bridgingPrecompiledHeader {
      let pchInput = TypedVirtualPath(file: pchPath, type: .pch)
      inputs.append(pchInput)
    }
    try addBridgingHeaderPCHCacheKeyArguments(commandLine: &commandLine, pchCompileJob: pchCompileJob)

    let displayInputs : [TypedVirtualPath]
    if case .singleCompile = compilerMode {
      displayInputs = inputs
    } else {
      displayInputs = primaryInputs
    }
    // The cache key for compilation is created one per input file, and each cache key contains all the output
    // files for that specific input file. All the module level output files are attached to the cache key for
    // the first input file. Only the input files that produce the output will have a cache key. This behavior
    // needs to match the cache key creation logic in swift-frontend.
    let cacheContributingInputs = inputs.enumerated().reduce(into: [(TypedVirtualPath, Int)]()) { result, input in
      guard input.element.type == .swift else { return }
      let singleInputKey = TypedVirtualPath(file: OutputFileMap.singleInputKey, type: .swift)
      if inputOutputMap[singleInputKey] != nil {
        // If singleInputKey exists, that means only the first swift file produces outputs.
        if result.isEmpty {
          result.append((input.element, input.offset))
        }
      } else if !inputOutputMap[input.element, default: []].isEmpty {
        // Otherwise, add all the inputs that produce output.
        result.append((input.element, input.offset))
      }
    }
    let cacheKeys = try computeOutputCacheKeyForJob(commandLine: commandLine, inputs: cacheContributingInputs)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .compile,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: displayInputs,
      inputs: inputs,
      primaryInputs: primaryInputs,
      outputs: outputs,
      outputCacheKeys: cacheKeys,
      inputOutputMap: inputOutputMap
    )
  }
}

extension Job {
  /// In whole-module-optimization mode (WMO), there are no primary inputs and every input generates
  /// code.
  public var inputsGeneratingCode: [TypedVirtualPath] {
    kind != .compile
      ? []
      : !primaryInputs.isEmpty
      ? primaryInputs
      : inputs.filter {$0.type.isPartOfSwiftCompilation}
  }
}

extension FileType {
  /// Determine the frontend compile option that corresponds to the given output type.
  fileprivate var frontendCompileOption: Option {
    switch self {
    case .object:
      return .c
    case .pch:
      return .emitPch
    case .ast:
      return .dumpAst
    case .raw_sil:
      return .emitSilgen
    case .sil:
      return .emitSil
    case .raw_sib:
      return .emitSibgen
    case .sib:
      return .emitSib
    case .raw_llvmIr:
      return .emitIrgen
    case .llvmIR:
      return .emitIr
    case .llvmBitcode:
      return .emitBc
    case .assembly:
      return .S
    case .swiftModule:
      return .emitModule
    case .importedModules:
      return .emitImportedModules
    case .indexData:
      return .typecheck
    case .remap:
      return .updateCode
    case .jsonDependencies:
      return .scanDependencies
    case .jsonTargetInfo:
      return .printTargetInfo
    case .jsonCompilerFeatures:
      return .emitSupportedFeatures
    case .jsonSupportedFeatures:
      return .printSupportedFeatures

    case .swift, .dSYM, .autolink, .dependencies, .emitModuleDependencies,
         .swiftDocumentation, .pcm, .diagnostics, .emitModuleDiagnostics,
         .objcHeader, .image, .swiftDeps, .moduleTrace, .tbd, .yamlOptimizationRecord,
         .bitstreamOptimizationRecord, .swiftInterface, .privateSwiftInterface, .packageSwiftInterface,
         .swiftSourceInfoFile, .clangModuleMap, .jsonSwiftArtifacts,
         .indexUnitOutputPath, .modDepCache, .jsonAPIBaseline, .jsonABIBaseline,
         .swiftConstValues, .jsonAPIDescriptor, .moduleSummary, .moduleSemanticInfo,
         .cachedDiagnostics:
      fatalError("Output type can never be a primary output")
    }
  }
}
