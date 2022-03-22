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
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs)
    // FIXME: MSVC runtime flags

    // Output serialized diagnostics for this job, if specifically requested
    var outputs: [TypedVirtualPath] = []
    if let outputPath = outputFileMap?.existingOutput(inputFile: interfaceInput.fileHandle,
                                                      outputType: .diagnostics) {
      outputs.append(TypedVirtualPath(file: outputPath, type: .diagnostics))
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
