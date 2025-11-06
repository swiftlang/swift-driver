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
  mutating func generateDSYMJob(inputs: [TypedVirtualPath]) throws -> Job {
    assert(inputs.count == 1)
    let input = inputs[0]

    // Output is final output file + `.dSYM`
    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = try outputFileForImage
    }
    let outputPath = try VirtualPath(path: outputFile.description.appendingFileTypeExtension(.dSYM))

    var commandLine = [Job.ArgTemplate]()
    commandLine.appendPath(input.file)

    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .generateDSYM,
      tool: try toolchain.resolvedTool(.dsymutil),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: [.init(file: outputPath.intern(), type: .dSYM)]
    )
  }
}
