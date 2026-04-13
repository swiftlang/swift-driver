//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

extension Driver {
  mutating func generateDWPJob(inputs: [TypedVirtualPath]) throws -> Job {
    assert(inputs.allSatisfy { $0.type == .dwo })

    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = try outputFileForImage
    }
    let outputPath = try VirtualPath(
      path: outputFile.description.appendingFileTypeExtension(.dwp))

    var commandLine = [Job.ArgTemplate]()

    // llvm-dwp <input1.dwo> <input2.dwo> ... -o <output.dwp>
    for input in inputs {
      commandLine.appendPath(input.file)
    }
    commandLine.appendFlag("-o")
    commandLine.appendPath(outputPath)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .generateDWP,
      tool: try toolchain.resolvedTool(.dwp),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: [.init(file: outputPath.intern(), type: .dwp)]
    )
  }
}
