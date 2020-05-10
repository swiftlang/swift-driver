//===--------------- ReplJob.swift - Swift REPL ---------------------------===//
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
  mutating func replJob() throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    try addCommonFrontendOptions(commandLine: &commandLine)
    // FIXME: MSVC runtime flags

    try commandLine.appendLast(.importObjcHeader, from: &parsedOptions)
    try commandLine.appendAll(.l, .framework, .L, from: &parsedOptions)

    // Squash important frontend options into a single argument for LLDB.
    let lldbArg = "--repl=\(commandLine.joinedArguments)"
    return Job(
      kind: .repl,
      tool: .absolute(try toolchain.getToolPath(.lldb)),
      commandLine: [Job.ArgTemplate.flag(lldbArg)],
      inputs: [],
      outputs: [],
      requiresInPlaceExecution: true
    )
  }
}
