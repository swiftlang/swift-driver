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

    // Look for -lldb-repl or -deprecated-integrated-repl to determine which
    // REPL to use. If neither is provided, prefer LLDB if it can be found.
    if parsedOptions.hasFlag(positive: .lldbRepl,
                             negative: .deprecatedIntegratedRepl,
                             default: (try? toolchain.getToolPath(.lldb)) != nil) {
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
    } else {
      // Invoke the integrated REPL, which is part of the frontend.
      commandLine = [.flag("-frontend"), .flag("-repl")] + commandLine
      commandLine.appendFlags("-module-name", moduleName)
      return Job(
        kind: .repl,
        tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
        commandLine: commandLine,
        inputs: [],
        outputs: [],
        requiresInPlaceExecution: true
      )
    }
  }
}
