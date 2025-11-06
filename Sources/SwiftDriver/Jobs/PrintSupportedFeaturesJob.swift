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

extension Toolchain {
  @_spi(Testing) public func printSupportedFeaturesJob(
    requiresInPlaceExecution: Bool = false,
    swiftCompilerPrefixArgs: [String]
  ) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.append(contentsOf: [
      .flag("-frontend"),
      .flag("-print-supported-features"),
    ])

    return Job(
      moduleName: "",
      kind: .printSupportedFeatures,
      tool: try resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [],
      inputs: [],
      primaryInputs: [],
      outputs: [.init(file: .standardOutput, type: .jsonSupportedFeatures)],
      requiresInPlaceExecution: requiresInPlaceExecution
    )
  }
}
