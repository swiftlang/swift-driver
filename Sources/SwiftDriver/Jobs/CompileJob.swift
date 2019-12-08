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
  mutating func addCompileInputs(primaryInputs: [TypedVirtualPath], inputs: inout [TypedVirtualPath], commandLine: inout [Job.ArgTemplate]) -> [TypedVirtualPath] {
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
      tool: swiftCompiler,
      commandLine: commandLine,
      displayInputs: primaryInputs,
      inputs: inputs,
      outputs: outputs
    )
  }
}

// FIXME: Utilities that may need to be moved or generalized

extension Array where Element == Job.ArgTemplate {
  /// Append a fixed flag to the command line arguments.
  ///
  /// When possible, use the more semantic forms `appendFlag` or
  /// `append(_: Option)`.
  mutating func appendFlag<StringType: StringProtocol>(_ string: StringType) {
    append(.flag(String(string)))
  }

  /// Append multiple flags to the command line arguments.
  ///
  /// When possible, use the more semantic forms `appendFlag` or
  /// `append(_: Option)`.
  mutating func appendFlags(_ flags: String...) {
    appendFlags(flags)
  }

  /// Append multiple flags to the command line arguments.
  ///
  /// When possible, use the more semantic forms `appendFlag` or
  /// `append(_: Option)`.
  mutating func appendFlags(_ flags: [String]) {
    for flag in flags {
      append(.flag(flag))
    }
  }

  /// Append a virtual path to the command line arguments.
  mutating func appendPath(_ path: VirtualPath) {
    append(.path(path))
  }

  /// Append an absolute path to the command line arguments.
  mutating func appendPath(_ path: AbsolutePath) {
    append(.path(.absolute(path)))
  }

  /// Append an option's spelling to the command line arguments.
  mutating func appendFlag(_ option: Option) {
    switch option.kind {
    case .flag, .joinedOrSeparate, .remaining, .separate:
      break
    case .commaJoined, .input, .joined:
      fatalError("Option cannot be appended as a flag: \(option)")
    }

    append(.flag(option.spelling))
  }

  /// Append a single argument from the given option.
  private mutating func appendSingleArgument(option: Option, argument: String) throws {
    if option.attributes.contains(.argumentIsPath) {
      append(.path(try VirtualPath(path: argument)))
    } else {
      appendFlag(argument)
    }
  }

  /// Append a parsed option to the array of argument templates, expanding
  /// until multiple arguments if required.
  mutating func append(_ parsedOption: ParsedOption) throws {
    let option = parsedOption.option
    let argument = parsedOption.argument

    switch option.kind {
    case .input:
      try appendSingleArgument(option: option, argument: argument.asSingle)

    case .flag:
      appendFlag(option)

    case .separate, .joinedOrSeparate:
      appendFlag(option.spelling)
      try appendSingleArgument(option: option, argument: argument.asSingle)

    case .commaJoined:
      assert(!option.attributes.contains(.argumentIsPath))
      appendFlag(option.spelling + argument.asMultiple.joined(separator: ","))

    case .remaining:
      appendFlag(option.spelling)
      for arg in argument.asMultiple {
        try appendSingleArgument(option: option, argument: arg)
      }

    case .joined:
      if option.attributes.contains(.argumentIsPath) {
        fatalError("Not currently implementable")
      } else {
        appendFlag(option.spelling + argument.asSingle)
      }
    }
  }

  /// Append the last parsed option that matches one of the given options
  /// to this command line.
  mutating func appendLast(_ options: Option..., from parsedOptions: inout ParsedOptions) throws {
    guard let parsedOption = parsedOptions.last(for: options) else {
      return
    }

    try append(parsedOption)
  }

  /// Append the last parsed option from the given group to this command line.
  mutating func appendLast(in group: Option.Group, from parsedOptions: inout ParsedOptions) throws {
    guard let parsedOption = parsedOptions.getLast(in: group) else {
      return
    }

    try append(parsedOption)
  }

  mutating func append(contentsOf options: [ParsedOption]) throws {
    for option in options {
      try append(option)
    }
  }

  /// Append all parsed options that match one of the given options
  /// to this command line.
  mutating func appendAll(_ options: Option..., from parsedOptions: inout ParsedOptions) throws {
    for matching in parsedOptions.arguments(for: options) {
      try append(matching)
    }
  }

  /// Append just the arguments from all parsed options that match one of the given options
  /// to this command line.
  mutating func appendAllArguments(_ options: Option..., from parsedOptions: inout ParsedOptions) throws {
    for matching in parsedOptions.arguments(for: options) {
      try self.appendSingleArgument(option: matching.option, argument: matching.argument.asSingle)
    }
  }

  /// Append the last of the given flags that appears in the parsed options,
  /// or the flag that corresponds to the default value if neither
  /// appears.
  mutating func appendFlag(true trueFlag: Option, false falseFlag: Option, default defaultValue: Bool, from parsedOptions: inout ParsedOptions) {
    let isTrue = parsedOptions.hasFlag(
      positive: trueFlag,
      negative: falseFlag,
      default: defaultValue
    )
    appendFlag(isTrue ? trueFlag : falseFlag)
  }

  var joinedArguments: String {
    return self.map {
      switch $0 {
        case .flag(let string):
          return string.spm_shellEscaped()
        case .path(let path):
          return path.name.spm_shellEscaped()
      }
    }.joined(separator: " ")
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
