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
  mutating func verifyModuleInterfaceJob(interfaceInput: TypedVirtualPath, optIn: Bool) throws -> Job {
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
      if let key = swiftInterfaceCacheKey, interfaceInput.type == .swiftInterface {
        commandLine.appendFlag("-input-file-key")
        commandLine.appendFlag(key)
      }
      if let key = privateSwiftInterfaceCacheKey, interfaceInput.type == .privateSwiftInterface {
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
