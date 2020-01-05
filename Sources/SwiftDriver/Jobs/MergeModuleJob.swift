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

extension Driver {
  mutating func mergeModuleJob(inputs allInputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: moduleOutput!.outputPath, type: .swiftModule)
    ]

    commandLine.appendFlags("-frontend", "-merge-modules", "-emit-module")

    // FIXME: Input file list.

    // Add the inputs.
    for input in allInputs {
      assert(input.type == .swiftModule)
      commandLine.append(.path(input.file))
      inputs.append(input)
    }

    // Tell all files to parse as library, which is necessary to load them as
    // serialized ASTs.
    commandLine.appendFlag(.parseAsLibrary)

    // Merge serialized SIL from partial modules.
    commandLine.appendFlag(.silMergePartialModules)

    // Disable SIL optimization passes; we've already optimized the code in each
    // partial mode.
    commandLine.appendFlag(.disableDiagnosticPasses)
    commandLine.appendFlag(.disableSilPerfOptzns)

    try addCommonFrontendOptions(commandLine: &commandLine)
    // FIXME: Add MSVC runtime library flags

    try addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs)

    commandLine.appendFlag(.o)
    commandLine.appendPath(moduleOutput!.outputPath)

    return Job(
      kind: .mergeModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs,
      supportsResponseFiles: true
    )
  }
}
