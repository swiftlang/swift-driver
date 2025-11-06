//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

extension Driver {
  mutating func interpretJob(inputs allInputs: [TypedVirtualPath],
                             explicitModulePlanner: ExplicitDependencyBuildPlanner?) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []

    commandLine.appendFlags("-frontend", "-interpret")

    // Add the inputs.
    for input in allInputs {
      commandLine.append(.path(input.file))
      inputs.append(input)
    }

    if parsedOptions.hasArgument(.parseStdlib) {
      commandLine.appendFlag(.disableObjcAttrRequiresFoundationModule)
    }

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .interpret,
                                 explicitModulePlanner: explicitModulePlanner)
    try addRuntimeLibraryFlags(commandLine: &commandLine)

    try commandLine.appendLast(.parseSil, from: &parsedOptions)
    toolchain.addLinkedLibArgs(to: &commandLine, parsedOptions: &parsedOptions)
    try commandLine.appendAll(.framework, from: &parsedOptions)

    // The immediate arguments must be last.
    try commandLine.appendLast(.DASHDASH, from: &parsedOptions)

    let extraEnvironment = try toolchain.platformSpecificInterpreterEnvironmentVariables(
      env: self.env, parsedOptions: &parsedOptions,
      sdkPath: frontendTargetInfo.sdkPath?.path, targetInfo: self.frontendTargetInfo)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .interpret,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: [],
      extraEnvironment: extraEnvironment,
      requiresInPlaceExecution: true
    )
  }
}
