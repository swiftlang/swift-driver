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
  func verifyDebugInfoJob(inputs: [TypedVirtualPath]) throws -> Job {
    assert(inputs.count == 1)
    let input = inputs[0]

    // This mirrors the clang driver's --verify-debug-info option.
    var commandLine = [Job.ArgTemplate]()
    commandLine.appendFlags("--verify", "--debug-info", "--eh-frame", "--quiet")
    commandLine.appendPath(input.file)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .verifyDebugInfo,
      tool: try toolchain.resolvedTool(.dwarfdump),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: []
    )
  }
}
