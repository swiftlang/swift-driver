//===--------------- GenerateDSYMJob.swift - Swift dSYM Generation --------===//
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
  func generateDSYMJob(inputs: [TypedVirtualPath]) throws -> Job {
    assert(inputs.count == 1)
    let input = inputs[0]
    let outputPath = try input.file.replacingExtension(with: .dSYM)

    var commandLine = [Job.ArgTemplate]()
    commandLine.appendPath(input.file)

    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath)

    return Job(
      kind: .generateDSYM,
      tool: .absolute(try toolchain.getToolPath(.dsymutil)),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      outputs: [.init(file: outputPath, type: .dSYM)]
    )
  }
}
