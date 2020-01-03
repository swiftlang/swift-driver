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
import TSCBasic

extension Driver {
  /// Add the appropriate compile mode option to the command line for a compile job.
  private mutating func addCompileModeOption(outputType: FileType?, commandLine: inout [Job.ArgTemplate]) {
    if let compileOption = outputType?.frontendCompileOption {
      commandLine.appendFlag(compileOption)
    } else {
      guard let compileModeOption = parsedOptions.getLast(in: .modes) else {
        fatalError("We were told to perform a standard compile, but no mode option was passed to the driver.")
      }

      commandLine.appendFlag(compileModeOption.option)
    }
  }

  /// Add the compiler inputs for a frontend compilation job, and return the corresponding primary set of outputs.
  func addCompileInputs(primaryInputs: [TypedVirtualPath], inputs: inout [TypedVirtualPath], commandLine: inout [Job.ArgTemplate]) -> [TypedVirtualPath] {
    // Collect the set of input files that are part of the Swift compilation.
    let swiftInputFiles: [TypedVirtualPath] = inputFiles.compactMap { inputFile in
      if inputFile.type.isPartOfSwiftCompilation {
        return inputFile
      }

      return nil
    }

    // If we will be passing primary files via -primary-file, form a set of primary input files so
    // we can check more quickly.
    let usesPrimaryFileInputs = compilerMode.usesPrimaryFileInputs
    assert(!usesPrimaryFileInputs || !primaryInputs.isEmpty)
    let primaryInputFiles = usesPrimaryFileInputs ? Set(primaryInputs) : Set()

    // Add each of the input files.
    // FIXME: Use/create input file lists and primary input file lists.
    var primaryOutputs: [TypedVirtualPath] = []
    for input in swiftInputFiles {
      inputs.append(input)

      let isPrimary = usesPrimaryFileInputs && primaryInputFiles.contains(input)
      if isPrimary {
        commandLine.appendFlag(.primaryFile)
      }
      commandLine.append(.path(input.file))

      // If there is a primary output or we are doing multithreaded compiles,
      // add an output for the input.
      if isPrimary || numThreads > 0,
          let compilerOutputType = compilerOutputType {
        let output = (outputFileMap ?? OutputFileMap()).getOutput(
          inputFile: input.file,
          outputType: compilerOutputType
        )
        primaryOutputs.append(TypedVirtualPath(file: output, type: compilerOutputType))
      }
    }

    // When not using primary file inputs or multithreading, add a single output.
    if !usesPrimaryFileInputs && numThreads == 0,
        let outputType = compilerOutputType {
      let existingOutputPath = outputFileMap?.existingOutputForSingleInput(
          outputType: outputType)
      let output = existingOutputPath ?? VirtualPath.temporary(.init(moduleName.appendingFileTypeExtension(outputType)))
      primaryOutputs.append(TypedVirtualPath(file: output, type: outputType))
    }

    return primaryOutputs
  }

  /// Form a compile job, which executes the Swift frontend to produce various outputs.
  mutating func compileJob(primaryInputs: [TypedVirtualPath], outputType: FileType?,
                           allOutputs: inout [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = []

    commandLine.appendFlag("-frontend")
    addCompileModeOption(outputType: outputType, commandLine: &commandLine)
    let primaryOutputs = addCompileInputs(primaryInputs: primaryInputs, inputs: &inputs, commandLine: &commandLine)
    outputs += primaryOutputs
    outputs += try addFrontendSupplementaryOutputArguments(commandLine: &commandLine, primaryInputs: primaryInputs)

    // Forward migrator flags.
    try commandLine.appendLast(.apiDiffDataFile, from: &parsedOptions)
    try commandLine.appendLast(.apiDiffDataDir, from: &parsedOptions)
    try commandLine.appendLast(.dumpUsr, from: &parsedOptions)

    if parsedOptions.hasArgument(.parseStdlib) {
      commandLine.appendFlag(.disableObjcAttrRequiresFoundationModule)
    }

    try addCommonFrontendOptions(commandLine: &commandLine)
    // FIXME: MSVC runtime flags

    if parsedOptions.hasArgument(.parseAsLibrary, .emitLibrary) {
      commandLine.appendFlag(.parseAsLibrary)
    }

    try commandLine.appendLast(.parseSil, from: &parsedOptions)

    try commandLine.appendLast(.migrateKeepObjcVisibility, from: &parsedOptions)

    if numThreads > 0 {
      commandLine.appendFlags("-num-threads", numThreads.description)
    }

    // Add primary outputs.
    for primaryOutput in primaryOutputs {
      commandLine.appendFlag(.o)
      commandLine.append(.path(primaryOutput.file))
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
    }

    if parsedOptions.contains(.debugInfoStoreInvocation) &&
       toolchain.shouldStoreInvocationInDebugInfo {
      commandLine.appendFlag(.debugInfoStoreInvocation)
    }

    try commandLine.appendLast(.disableAutolinkingRuntimeCompatibility, from: &parsedOptions)
    try commandLine.appendLast(.runtimeCompatibilityVersion, from: &parsedOptions)
    try commandLine.appendLast(.disableAutolinkingRuntimeCompatibilityDynamicReplacements, from: &parsedOptions)

    allOutputs += outputs

    // If we're creating emit module job, order the compile jobs after that.
    if shouldCreateEmitModuleJob {
      inputs.append(TypedVirtualPath(file: moduleOutput!.outputPath, type: .swiftModule))
    }

    return Job(
      kind: .compile,
      tool: .absolute(swiftCompiler),
      commandLine: commandLine,
      displayInputs: primaryInputs,
      inputs: inputs,
      outputs: outputs
    )
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

    case .swift, .dSYM, .autolink, .dependencies, .swiftDocumentation, .pcm,
         .diagnostics, .objcHeader, .image, .swiftDeps, .moduleTrace, .tbd,
         .optimizationRecord, .swiftInterface, .swiftSourceInfoFile:
      fatalError("Output type can never be a primary output")
    }
  }
}
