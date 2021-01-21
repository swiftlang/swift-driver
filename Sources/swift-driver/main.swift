//===--------------- main.swift - Swift Driver Main Entrypoint ------------===//
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
import SwiftDriverExecution
import SwiftDriver

import TSCLibc
import TSCBasic
import TSCUtility

var intHandler: InterruptHandler?
let diagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler])

do {
  let processSet = ProcessSet()
  intHandler = try InterruptHandler {
    processSet.terminate()
    // If the swift-driver invocation is interrupted by the build system,
    // returning non-zero value emits red-herring error messages in the build logs.
    // So we exit with 0 here.
    exit(0)
  }

  if ProcessEnv.vars["SWIFT_ENABLE_EXPLICIT_MODULE"] != nil {
    CommandLine.arguments.append("-experimental-explicit-module-build")
  }

  let (mode, arguments) = try Driver.invocationRunMode(forArgs: CommandLine.arguments)

  if case .subcommand(let subcommand) = mode {
    // We are running as a subcommand, try to find the subcommand adjacent to the executable we are running as.
    // If we didn't find the tool there, let the OS search for it.
    let subcommandPath = Process.findExecutable(arguments[0])?.parentDirectory.appending(component: subcommand)
                         ?? Process.findExecutable(subcommand)

    if subcommandPath == nil || !localFileSystem.exists(subcommandPath!) {
      fatalError("cannot find subcommand executable '\(subcommand)'")
    }

    // Execute the subcommand.
    try exec(path: subcommandPath?.pathString ?? "", args: arguments)
  }

  let executor = try SwiftDriverExecutor(diagnosticsEngine: diagnosticsEngine,
                                         processSet: processSet,
                                         fileSystem: localFileSystem,
                                         env: ProcessEnv.vars)
  var driver = try Driver(args: arguments,
                          diagnosticsEngine: diagnosticsEngine,
                          executor: executor,
                          integratedDriver: false)
  // FIXME: The following check should be at the end of Driver.init, but current
  // usage of the DiagnosticVerifier in tests makes this difficult.
  guard !driver.diagnosticEngine.hasErrors else { throw Diagnostics.fatalError }

  let jobs = try driver.planBuild()
  try driver.run(jobs: jobs)

  if driver.diagnosticEngine.hasErrors {
    exit(EXIT_FAILURE)
  }
} catch Diagnostics.fatalError {
  exit(EXIT_FAILURE)
} catch let diagnosticData as DiagnosticData {
  diagnosticsEngine.emit(.error(diagnosticData))
  exit(EXIT_FAILURE)
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
