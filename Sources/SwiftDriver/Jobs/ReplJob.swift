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
  mutating func replJob() throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .repl)
    try addRuntimeLibraryFlags(commandLine: &commandLine)

    try commandLine.appendLast(
      .importObjcHeader, .internalImportBridgingHeader,
      from: &parsedOptions
    )
    toolchain.addLinkedLibArgs(
      to: &commandLine,
      parsedOptions: &parsedOptions
    )
    try commandLine.appendAll(.framework, .L, from: &parsedOptions)

    // Squash important frontend options into a single argument for LLDB.
    let lldbCommandLine: [Job.ArgTemplate] = [.squashedArgumentList(option: "--repl=", args: commandLine)]
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .repl,
      tool: try toolchain.resolvedTool(.lldb),
      commandLine: lldbCommandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: [],
      requiresInPlaceExecution: true
    )
  }
}
