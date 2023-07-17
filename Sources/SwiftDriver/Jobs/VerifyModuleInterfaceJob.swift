//===- VerifyModuleInterface.swift - Swift Module Interface Verification --===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Driver {
  func computeCacheKeyForInterface(emitModuleJob: Job,
                                   interfaceKind: FileType) throws -> String? {
    assert(interfaceKind == .swiftInterface || interfaceKind == .privateSwiftInterface,
           "only expect interface output kind")
    let isNeeded = emitModuleJob.outputs.contains { $0.type == interfaceKind }
    guard enableCaching && isNeeded else { return nil }

    // Assume swiftinterface file is always the supplementary output for first input file.
    let mainInput = emitModuleJob.inputs[0]
    return try interModuleDependencyOracle.computeCacheKeyForOutput(kind: interfaceKind,
                                                                    commandLine: emitModuleJob.commandLine,
                                                                    input: mainInput.fileHandle)
  }

  mutating func verifyModuleInterfaceJob(interfaceInput: TypedVirtualPath, emitModuleJob: Job, optIn: Bool) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = [interfaceInput]
    commandLine.appendFlags("-frontend", "-typecheck-module-from-interface")
    commandLine.appendPath(interfaceInput.file)
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .verifyModuleInterface)
    // FIXME: MSVC runtime flags

    // Output serialized diagnostics for this job, if specifically requested
    var outputs: [TypedVirtualPath] = []
    if let outputPath = try outputFileMap?.existingOutput(inputFile: interfaceInput.fileHandle,
                                                      outputType: .diagnostics) {
      outputs.append(TypedVirtualPath(file: outputPath, type: .diagnostics))
    }

    if parsedOptions.contains(.driverExplicitModuleBuild) {
      commandLine.appendFlag("-explicit-interface-module-build")
      if let key = try computeCacheKeyForInterface(emitModuleJob: emitModuleJob, interfaceKind: interfaceInput.type) {
        commandLine.appendFlag("-input-file-key")
        commandLine.appendFlag(key)
      }
      // Need to create an output file for swiftmodule output. Currently put it next to the swift interface.
      let moduleOutPath = try interfaceInput.file.appendingToBaseName(".verified.swiftmodule")
      commandLine.appendFlags("-o", moduleOutPath.name)
    }

    // TODO: remove this because we'd like module interface errors to fail the build.
    if !optIn && isFrontendArgSupported(.downgradeTypecheckInterfaceError) {
      commandLine.appendFlag(.downgradeTypecheckInterfaceError)
    }
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .verifyModuleInterface,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [interfaceInput],
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs
    )
  }
}
