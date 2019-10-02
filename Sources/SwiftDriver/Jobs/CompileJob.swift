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

      commandLine.appendFlag(compileModeOption.option!)
    }
  }

  /// Add the compiler inputs for a frontend compilation job, and return the corresponding primary set of outputs.
  mutating func addCompileInputs(primaryInputs: [InputFile], inputs: inout [VirtualPath], commandLine: inout [Job.ArgTemplate]) -> [VirtualPath] {
    // Collect the set of input files that are part of the Swift compilation.
    let swiftInputFiles: [VirtualPath] = inputFiles.compactMap { inputFile in
      if inputFile.type.isPartOfSwiftCompilation {
        return inputFile.file
      }

      return nil
    }

    // If we will be passing primary files via -primary-file, form a set of primary input files so
    // we can check more quickly.
    let usesPrimaryFileInputs = compilerMode.usesPrimaryFileInputs
    assert(!usesPrimaryFileInputs || !primaryInputs.isEmpty)
    let primaryInputFiles: Set<VirtualPath> = usesPrimaryFileInputs ? Set(primaryInputs.map { $0.file }) : Set()

    // Add each of the input files.
    // FIXME: Use/create input file lists and primary input file lists.
    var primaryOutputs: [VirtualPath] = []
    for input in swiftInputFiles {
      inputs.append(input)

      let isPrimary = usesPrimaryFileInputs && primaryInputFiles.contains(input)
      if isPrimary {
        commandLine.appendFlag("-primary-file")
      }
      commandLine.append(.path(input))

      // If there is a primary output, add it.
      if isPrimary, let compilerOutputType = compilerOutputType {
        primaryOutputs.append(outputFileMap.getOutput(inputFile: input, outputType: compilerOutputType))
      }
    }

    return primaryOutputs
  }

  /// Form a compile job, which executes the Swift frontend to produce various outputs.
  mutating func compileJob(primaryInputs: [InputFile], outputType: FileType?,
                           allOutputs: inout [InputFile]) -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [VirtualPath] = []
    var outputs: [VirtualPath] = []

    commandLine.appendFlag("-frontend")
    addCompileModeOption(outputType: outputType, commandLine: &commandLine)
    let primaryOutputs = addCompileInputs(primaryInputs: primaryInputs, inputs: &inputs, commandLine: &commandLine)

    if let stderrStream = stderrStream.stream as? LocalFileOutputByteStream, TerminalController.isTTY(stderrStream) {
      commandLine.appendFlag(.color_diagnostics)
    }

    // Add primary outputs.
    for primaryOutput in primaryOutputs {
      outputs.append(primaryOutput)
      commandLine.appendFlag("-o")
      commandLine.append(.path(primaryOutput))

      allOutputs.append(InputFile(file:primaryOutput, type: compilerOutputType!))
    }

    return Job(tool: swiftCompiler, commandLine: commandLine, inputs: inputs, outputs: outputs)
  }
}

// FIXME: Utilities that may need to be moved or generalized

extension Array where Element == Job.ArgTemplate {
  /// Append a fixed flag to the command line arguments.
  ///
  /// When possible, use the more semantic forms `appendFlag` or
  /// `append(_: Option)`.
  mutating func appendFlag(_ string: String) {
    append(.flag(string))
  }

  ///. Append a flag option's spelling to the command line arguments.
  mutating func appendFlag(_ option: Option) {
    assert(option.kind == .flag)
    append(.flag(option.spelling))
  }
}

extension FileType {
  /// Determine the frontend compile option that corresponds to the given output type.
  fileprivate var frontendCompileOption: Option {
    switch self {
    case .object:
      return .c
    case .pch:
      return .emit_pch
    case .ast:
      return .dump_ast
    case .raw_sil:
      return .emit_silgen
    case .sil:
      return .emit_sil
    case .raw_sib:
      return .emit_sibgen
    case .sib:
      return .emit_sib
    case .llvmIR:
      return .emit_ir
    case .llvmBitcode:
      return .emit_bc
    case .assembly:
      return .S
    case .swiftModule:
      return .emit_module
    case .importedModules:
      return .emit_imported_modules
    case .indexData:
      return .typecheck
    case .remap:
      return .update_code

    case .swift, .dSYM, .autolink, .dependencies, .swiftDocumentation, .pcm,
         .diagnostics, .objcHeader, .image, .swiftDeps, .moduleTrace, .tbd,
         .optimizationRecord,.swiftInterface:
      fatalError("Output type can never be a primary output")
    }
  }
}
