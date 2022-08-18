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
#if os(Windows)
import CRT
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif
import TSCBasic

import Dispatch

#if os(Windows)
import WinSDK
#endif

import enum TSCUtility.Diagnostics

let interruptSignalSource = DispatchSource.makeSignalSource(signal: SIGINT)
let diagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler])
var driverInterrupted = false
func getExitCode(_ code: Int32) -> Int32 {
  if driverInterrupted {
    interruptSignalSource.cancel()
#if os(Windows)
    TerminateProcess(GetCurrentProcess(), UINT(0xC0000000 | UINT(2)))
#else
    signal(SIGINT, SIG_DFL)
    kill(getpid(), SIGINT)
#endif
    fatalError("Invalid state, could not kill process")
  }
  return code
}

do {
  #if !os(Windows)
  signal(SIGINT, SIG_IGN)
  #endif
  let processSet = ProcessSet()
  interruptSignalSource.setEventHandler {
    // Terminate running compiler jobs and let the driver exit gracefully, remembering
    // to return a corresponding exit code when done.
    processSet.terminate()
    driverInterrupted = true
  }
  interruptSignalSource.resume()

  if ProcessEnv.vars["SWIFT_ENABLE_EXPLICIT_MODULE"] != nil {
    CommandLine.arguments.append("-explicit-module-build")
  }

  let (mode, arguments) = try Driver.invocationRunMode(forArgs: CommandLine.arguments)

  if case .subcommand(let subcommand) = mode {
    // We are running as a subcommand, try to find the subcommand adjacent to the executable we are running as.
    // If we didn't find the tool there, let the OS search for it.
    let subcommandPath = Process.findExecutable(arguments[0])?.parentDirectory.appending(component: subcommand)
                         ?? Process.findExecutable(subcommand)

    if subcommandPath == nil || !localFileSystem.exists(subcommandPath!) {
      throw Driver.Error.unknownOrMissingSubcommand(subcommand)
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
    exit(getExitCode(EXIT_FAILURE))
  }
  exit(getExitCode(0))
} catch Diagnostics.fatalError {
  exit(getExitCode(EXIT_FAILURE))
} catch let diagnosticData as DiagnosticData {
  diagnosticsEngine.emit(.error(diagnosticData))
  exit(getExitCode(EXIT_FAILURE))
} catch {
  print("error: \(error)")
  exit(getExitCode(EXIT_FAILURE))
}
