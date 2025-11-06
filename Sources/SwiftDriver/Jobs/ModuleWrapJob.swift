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
  mutating func moduleWrapJob(moduleInput: TypedVirtualPath) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    commandLine.appendFlags("-modulewrap")

    // Add the input.
    commandLine.append(.path(moduleInput.file))

    commandLine.appendFlags("-target", targetTriple.triple)

    let outputPath = try moduleInput.file.replacingExtension(with: .object)
    commandLine.appendFlag("-o")
    commandLine.appendPath(outputPath)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .moduleWrap,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      inputs: [moduleInput],
      primaryInputs: [],
      outputs: [.init(file: outputPath.intern(), type: .object)]
    )
  }
}
