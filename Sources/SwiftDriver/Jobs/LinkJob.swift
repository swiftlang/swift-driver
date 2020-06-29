//===--------------- LinkJob.swift - Swift Linking Job --------------------===//
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

  /// Compute the output file for an image output.
  private var outputFileForImage: VirtualPath {
    if inputFiles.count == 1 && moduleOutputInfo.nameIsFallback && inputFiles[0].file != .standardInput {
      return .relative(RelativePath(inputFiles[0].file.basenameWithoutExt))
    }

    let outputName =
      toolchain.makeLinkerOutputFilename(moduleName: moduleOutputInfo.name,
                                         type: linkerOutputType!)
    return .relative(RelativePath(outputName))
  }

  /// Link the given inputs.
  mutating func linkJob(inputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = []

    // Compute the final output file
    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = outputFileForImage
    }

    // Defer to the toolchain for platform-specific linking

    let toolPath = try toolchain.addPlatformSpecificLinkerArgs(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      linkerOutputType: linkerOutputType!,
      inputs: inputs,
      outputFile: outputFile,
      sdkPath: sdkPath,
      sanitizers: enabledSanitizers,
      targetInfo: frontendTargetInfo
    )

    // TODO: some, but not all, linkers support response files.
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .link,
      tool: .absolute(toolPath),
      commandLine: commandLine,
      inputs: inputs,
      outputs: [.init(file: outputFile, type: .image)]
    )
  }
}
