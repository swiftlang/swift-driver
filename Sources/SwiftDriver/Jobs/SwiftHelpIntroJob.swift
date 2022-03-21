//===--------------- SwiftHelpIntroJob.swift - Swift REPL -----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
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
