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
import SwiftOptions

extension Driver {
  mutating func helpIntroJobs() throws -> [Job] {
    return [
      Job(
        moduleName: moduleOutputInfo.name,
        kind: .help,
        tool: try toolchain.resolvedTool(.swiftHelp),
        commandLine: [.flag("intro")],
        inputs: [],
        primaryInputs: [],
        outputs: [],
        requiresInPlaceExecution: false
      ),
    ]
  }
}
