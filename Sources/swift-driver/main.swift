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
import SwiftOptions
#if os(Windows)
import CRT
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

import Dispatch
import Foundation

#if os(Windows)
import WinSDK
#endif

import struct TSCBasic.AbsolutePath
import func TSCBasic.exec
import enum TSCBasic.ProcessEnv
import class TSCBasic.DiagnosticsEngine
import class TSCBasic.Process
import func TSCBasic.resolveSymlinks
import protocol TSCBasic.DiagnosticData
import var TSCBasic.localFileSystem

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

  // Fallback to legacy driver if forced to
  if CommandLine.arguments.contains(Option.disallowForwardingDriver.spelling) ||
     ProcessEnv.block["SWIFT_USE_OLD_DRIVER"] != nil {
    // If CommandLine.argument[0] is not an absolute path, we would form a path
    // relative to the current directory rather than relative to the actual
    // location of the binary. Use the Founation `NSProcessInfo` type to compute
    // the executable that is being run and then form the invocation from the
    // `CommandLine.arguments[0]`. This allows us to merge both to form a path
    // relative to the location of the executable but with the desired
    // invocation for a multi-call binary.
    let executable: URL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
    let invocation: URL = URL(fileURLWithPath: CommandLine.arguments[0])

    #if compiler(>=6.2)
    let legacyExecutablePath: URL =
         executable.deletingLastPathComponent()
                   .appendingPathComponent("\(invocation.deletingPathExtension().lastPathComponent)-legacy-driver")
                   .appendingPathExtension(executable.pathExtension)
    #else
    // WORKAROUND: Check if the original path has a non-empty extension because
    // `url.deletingPathExtension().appendingPathExtension(url.pathExtension)`
    // will not be equal to `url` but be `\(url).` if `url` doesn't have an
    // extension on Swift 6.0. Remove this when we drop support for Swift 6.0
    // as a bootstrapping compiler.
    // See https://github.com/swiftlang/swift-foundation/issues/1080
    var legacyExecutablePath: URL =
        executable.deletingLastPathComponent()
                  .appendingPathComponent("\(invocation.deletingPathExtension().lastPathComponent)-legacy-driver")
    if !executable.pathExtension.isEmpty {
        legacyExecutablePath.appendPathExtension(executable.pathExtension)
    }
    #endif
    let path: String = legacyExecutablePath.withUnsafeFileSystemRepresentation { String(cString: $0!) }

    if localFileSystem.exists(try AbsolutePath(validating: path)) {
      let legacyDriverCommand = [path] + CommandLine.arguments[1...]
      try exec(path: path, args: legacyDriverCommand)
    } else {
      throw Driver.Error.unknownOrMissingSubcommand(
        legacyExecutablePath.lastPathComponent,
        legacyExecutablePath
          .deletingLastPathComponent()
          .withUnsafeFileSystemRepresentation { String(cString: $0!) })
    }
  }

  let (mode, arguments) = try Driver.invocationRunMode(forArgs: CommandLine.arguments)
  if case .subcommand(let subcommand) = mode {
    // We are running as a subcommand, try to find the subcommand adjacent to the executable we are running as.
    // If we didn't find the tool there, let the OS search for it.
    let subcommandPath: AbsolutePath?
    if let executablePath = Process.findExecutable(CommandLine.arguments[0]) {
      // Attempt to resolve the executable symlink in order to be able to
      // resolve compiler-adjacent library locations.
      subcommandPath = try TSCBasic.resolveSymlinks(executablePath).parentDirectory.appending(component: subcommand)
    } else {
      subcommandPath = Process.findExecutable(subcommand)
    }

    guard let subcommandPath = subcommandPath,
          localFileSystem.exists(subcommandPath) else {
      throw Driver.Error.unknownOrMissingSubcommand(subcommand, nil)
    }

    // Pass the full path to subcommand executable.
    var arguments = arguments
    arguments[0] = subcommandPath.pathString

    // Execute the subcommand.
    try exec(path: subcommandPath.pathString, args: arguments)
  }

  let executor = try SwiftDriverExecutor(diagnosticsEngine: diagnosticsEngine,
                                         processSet: processSet,
                                         fileSystem: localFileSystem,
                                         env: ProcessEnv.block)
  var driver = try Driver(args: arguments,
                          envBlock: ProcessEnv.block,
                          diagnosticsOutput: .engine(diagnosticsEngine),
                          executor: executor,
                          integratedDriver: false)

  // FIXME: The following check should be at the end of Driver.init, but current
  // usage of the DiagnosticVerifier in tests makes this difficult.
  guard !driver.diagnosticEngine.hasErrors else {
    throw Driver.ErrorDiagnostics.emitted
  }

  let jobs = try driver.planBuild()

  // Planning may result in further errors emitted
  // due to dependency scanning failures.
  guard !driver.diagnosticEngine.hasErrors else {
    throw Driver.ErrorDiagnostics.emitted
  }

  try driver.run(jobs: jobs)

  if driver.diagnosticEngine.hasErrors {
    exit(getExitCode(EXIT_FAILURE))
  }

  exit(getExitCode(0))
} catch let diagnosticData as DiagnosticData {
  diagnosticsEngine.emit(.error(diagnosticData))
  exit(getExitCode(EXIT_FAILURE))
} catch Driver.ErrorDiagnostics.emitted {
  exit(getExitCode(EXIT_FAILURE))
} catch {
  print("error: \(error)")
  exit(getExitCode(EXIT_FAILURE))
}
