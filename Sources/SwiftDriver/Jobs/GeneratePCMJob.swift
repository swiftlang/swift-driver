//===--------------- GeneratePCMJob.swift - Generate PCM Job ----===//
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
  /// Create a job that generates a Clang module (.pcm) that is suitable for
  /// use.
  ///
  /// The input is a Clang module map
  /// (https://clang.llvm.org/docs/Modules.html#module-map-language) and the
  /// output is a compiled module that also includes the additional information
  /// needed by Swift's Clang importer, e.g., the Swift name lookup tables.
  mutating func generateEmitPCMJob(input: TypedVirtualPath) throws -> Job {
    var inputs = [TypedVirtualPath]()
    var outputs = [TypedVirtualPath]()

    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    commandLine.appendFlag("-frontend")
    commandLine.appendFlag(.emitPcm)

    // Input module map.
    inputs.append(input)
    commandLine.appendPath(input.file)

    // Compute the output file.
    let output: TypedVirtualPath
    if let outputArg = parsedOptions.getLastArgument(.o) {
      output = .init(file: try VirtualPath.intern(path: outputArg.asSingle),
                     type: .pcm)
    } else {
      output = .init(
        file: try VirtualPath.intern(
          path: moduleOutputInfo.name.appendingFileTypeExtension(.pcm)),
        type: .pcm)
    }

    outputs.append(output)
    commandLine.appendFlag(.o)
    commandLine.appendPath(output.file)

    try addCommonFrontendOptions(
      commandLine: &commandLine, inputs: &inputs, kind: .generatePCM, bridgingHeaderHandling: .ignored)

    try commandLine.appendLast(.indexStorePath, from: &parsedOptions)
    let cacheKeys = try computeOutputCacheKeyForJob(commandLine: commandLine, inputs: [(input, 0)])

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .generatePCM,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs,
      outputCacheKeys: cacheKeys
    )
  }

  /// Create a job that dumps information about a Clang module
  ///
  /// The input is a Clang Pre-compiled module file (.pcm).
  mutating func generateDumpPCMJob(input: TypedVirtualPath) throws -> Job {
    var inputs = [TypedVirtualPath]()
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    commandLine.appendFlag("-frontend")
    commandLine.appendFlag(.dumpPcm)

    // Input precompiled module.
    inputs.append(input)
    commandLine.appendPath(input.file)

    try addCommonFrontendOptions(
      commandLine: &commandLine, inputs: &inputs, kind: .generatePCM, bridgingHeaderHandling: .ignored)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .dumpPCM,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: []
    )
  }
}
