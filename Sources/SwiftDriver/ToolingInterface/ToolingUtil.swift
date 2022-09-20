//===------- ToolingUtil.swift - Swift Driver Source Version--------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class TSCBasic.DiagnosticsEngine
import struct TSCBasic.Diagnostic
import class TSCBasic.ProcessSet
import enum TSCBasic.ProcessEnv
import var TSCBasic.localFileSystem
import SwiftOptions

/// Generates the list of arguments that would be passed to the compiler
/// frontend from the given driver arguments.
///
/// \param ArgList The driver arguments (i.e. normal arguments for \c swiftc).
/// \param ForceNoOutputs If true, override the output mode to "-typecheck" and
/// produce no outputs. For example, this disables "-emit-module" and "-c" and
/// prevents the creation of temporary files.
/// \param outputFrontendArgs Contains the resulting frontend invocation command
/// \param emittedDiagnostics Contains the diagnostics emitted by the driver
///
/// \returns true on error
///
/// \note This function is not intended to create invocations which are
/// suitable for use in REPL or immediate modes.
public func getSingleFrontendInvocationFromDriverArguments(argList: [String],
                                                           outputFrontendArgs: inout [String],
                                                           emittedDiagnostics: inout [Diagnostic],
                                                           forceNoOutputs: Bool = false) -> Bool {
  var args: [String] = []
  args.append(contentsOf: argList)
  
  // When creating a CompilerInvocation, ensure that the driver creates a single
  // frontend command.
  args.append("-whole-module-optimization")
  
  // Explicitly disable batch mode to avoid a spurious warning when combining
  // -enable-batch-mode with -whole-module-optimization.  This is an
  // implementation detail.
  args.append("-disable-batch-mode");
  
  // Prevent having a separate job for emit-module, we would like
  // to just have one job
  args.append("-no-emit-module-separately-wmo")

  // Avoid using filelists
  args.append("-driver-filelist-threshold");
  args.append(String(Int.max));
  
  let diagnosticsEngine = DiagnosticsEngine()
  defer { emittedDiagnostics = diagnosticsEngine.diagnostics }
  
  do {
    args = try ["swiftc"] + Driver.expandResponseFiles(args,
                                                       fileSystem: localFileSystem,
                                                       diagnosticsEngine: diagnosticsEngine)

    let optionTable = OptionTable()
    var parsedOptions = try optionTable.parse(Array(args), for: .batch, delayThrows: true)
    if forceNoOutputs {
      // Clear existing output modes and supplementary outputs.
      parsedOptions.eraseAllArguments(in: .modes)
      parsedOptions.eraseSupplementaryOutputs()
      parsedOptions.addOption(.typecheck, argument: .none)
    }
    
    // Instantiate the driver, setting up the toolchain in the process, etc.
    let resolver = try ArgsResolver(fileSystem: localFileSystem)
    let executor = SimpleExecutor(resolver: resolver,
                                  fileSystem: localFileSystem,
                                  env: ProcessEnv.vars)
    var driver = try Driver(args: parsedOptions.commandLine,
                            diagnosticsEngine: diagnosticsEngine,
                            executor: executor)
    if diagnosticsEngine.hasErrors {
      return true
    }
    
    
    let buildPlan = try driver.planBuild()
    if diagnosticsEngine.hasErrors {
      return true
    }
    let compileJobs = buildPlan.filter({ $0.kind == .compile })
    guard let compileJob = compileJobs.spm_only else {
      diagnosticsEngine.emit(.error_expected_one_frontend_job())
      return true
    }
    if !compileJob.commandLine.starts(with: [.flag("-frontend")]) {
      diagnosticsEngine.emit(.error_expected_frontend_command())
      return true
    }
    outputFrontendArgs = try executor.description(of: compileJob,
                                                  forceResponseFiles: false).components(separatedBy: " ")
  } catch {
    print("Unexpected error: \(error).")
    return true
  }

  return false
}
