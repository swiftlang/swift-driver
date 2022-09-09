//===--------------- MergeModuleJob.swift - Swift Module Merging ----------===//
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

import struct TSCBasic.RelativePath

extension Driver {
  mutating func mergeModuleJob(inputs providedInputs: [TypedVirtualPath],
                               inputsFromOutputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: moduleOutputInfo.output!.outputPath, type: .swiftModule)
    ]

    commandLine.appendFlags("-frontend", "-merge-modules", "-emit-module")

    // Input file list.
    if shouldUseInputFileList {
      commandLine.appendFlag(.filelist)
      let fileList = VirtualPath.createUniqueFilelist(RelativePath("inputs"),
                                                      .list(inputsFromOutputs.map { $0.file }))
      commandLine.appendPath(fileList)
      inputs.append(contentsOf: inputsFromOutputs)
      
      for input in providedInputs {
        assert(input.type == .swiftModule)
        commandLine.append(.path(input.file))
        inputs.append(input)
      }
    } else {
      // Add the inputs.
      for input in providedInputs + inputsFromOutputs {
        assert(input.type == .swiftModule)
        commandLine.append(.path(input.file))
        inputs.append(input)
      }
    }

    // Tell all files to parse as library, which is necessary to load them as
    // serialized ASTs.
    commandLine.appendFlag(.parseAsLibrary)

    // Disable SIL optimization passes; we've already optimized the code in each
    // partial mode.
    commandLine.appendFlag(.disableDiagnosticPasses)
    commandLine.appendFlag(.disableSilPerfOptzns)

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, bridgingHeaderHandling: .parsed)
    // FIXME: Add MSVC runtime library flags

    addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs, isMergeModule: true)

    try commandLine.appendLast(.emitSymbolGraph, from: &parsedOptions)
    try commandLine.appendLast(.emitSymbolGraphDir, from: &parsedOptions)
    try commandLine.appendLast(.includeSpiSymbols, from: &parsedOptions)
    try commandLine.appendLast(.symbolGraphMinimumAccessLevel, from: &parsedOptions)

    // Propagate the disable flag for cross-module incremental builds
    // if necessary. Note because we're interested in *disabling* this feature,
    // we consider the disable form to be the positive and enable to be the
    // negative.
    if parsedOptions.hasFlag(positive: .disableIncrementalImports,
                             negative: .enableIncrementalImports,
                             default: false) {
      try commandLine.appendLast(.disableIncrementalImports, from: &parsedOptions)
    }

    let outputPath = VirtualPath.lookup(moduleOutputInfo.output!.outputPath)
    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath)

    if let abiPath = abiDescriptorPath {
      commandLine.appendFlag(.emitAbiDescriptorPath)
      commandLine.appendPath(abiPath.file)
      outputs.append(abiPath)
    }
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .mergeModule,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs
    )
  }
}
