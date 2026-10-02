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

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

extension Driver {
  internal var relativeOutputFileForImage: RelativePath {
    get throws {
      if inputFiles.count == 1 && moduleOutputInfo.nameIsFallback && inputFiles[0].file != .standardInput {
        return try RelativePath(validating: inputFiles[0].file.basenameWithoutExt)
      }

      let outputName =
      toolchain.makeLinkerOutputFilename(moduleName: moduleOutputInfo.name,
                                         type: linkerOutputType!)
      return try RelativePath(validating: outputName)
    }
  }

  /// Compute the output file for an image output.
  internal var outputFileForImage: VirtualPath {
    get throws {
      return try useWorkingDirectory(relativeOutputFileForImage)
    }
  }

  func useWorkingDirectory(_ relative: RelativePath) throws -> VirtualPath {
    return try Driver.useWorkingDirectory(relative, workingDirectory)
  }

  static func useWorkingDirectory(_ relative: RelativePath, _ workingDirectory: AbsolutePath?) throws -> VirtualPath {
    if let wd = workingDirectory {
      return .absolute(try AbsolutePath(validating: relative.pathString, relativeTo: wd))
    }
    return .relative(relative)
  }

  /// Link the given inputs.
  mutating func linkJob(inputs: [TypedVirtualPath],
                        explicitModulePlanner: ExplicitDependencyBuildPlanner?) throws -> Job {
    var commandLine: [Job.ArgTemplate] = []

    // Compute the final output file
    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = try outputFileForImage
    }

    if let gccToolchain = parsedOptions.getLastArgument(.gccToolchain) {
        commandLine.appendFlag(.XclangLinker)
        commandLine.appendFlag("--gcc-toolchain=\(gccToolchain.asSingle)")
    }

    // Under an explicit module build the compile job is passed
    // -debug-module-path, which supersedes -add_ast_path for this module. Tie
    // the two together: a frontend that does not record the module path in
    // debug info still needs the serialized AST in the binary.
    let shouldAddASTPaths = !(isExplicitModuleBuildEnabled
                              && isFeatureSupported(.debug_info_explicit_dependency))

    // Defer to the toolchain for platform-specific linking
    let linkTool = try toolchain.addPlatformSpecificLinkerArgs(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      linkerOutputType: linkerOutputType!,
      inputs: inputs,
      outputFile: outputFile,
      shouldUseInputFileList: shouldUseInputFileList,
      shouldAddASTPaths: shouldAddASTPaths,
      lto: lto,
      sanitizers: enabledSanitizers,
      targetInfo: frontendTargetInfo
    )

    if parsedOptions.hasArgument(.explicitAutoLinking) {
      try explicitModulePlanner?.getLinkLibraryLoadCommandFlags(&commandLine)
    }

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .link,
      tool: linkTool,
      commandLine: commandLine,
      displayInputs: inputs,
      inputs: inputs,
      primaryInputs: [],
      outputs: [.init(file: outputFile.intern(), type: .image)]
    )
  }
}
