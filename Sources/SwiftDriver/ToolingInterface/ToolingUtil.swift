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
import struct TSCBasic.ProcessEnvironmentBlock
import var TSCBasic.localFileSystem
import struct TSCBasic.AbsolutePath
import SwiftOptions

//typedef enum {
//  SWIFTDRIVER_TOOLING_DIAGNOSTIC_ERROR = 0,
//  SWIFTDRIVER_TOOLING_DIAGNOSTIC_WARNING = 1,
//  SWIFTDRIVER_TOOLING_DIAGNOSTIC_REMARK = 2,
//  SWIFTDRIVER_TOOLING_DIAGNOSTIC_NOTE = 3
//} swiftdriver_tooling_diagnostic_kind;
public let SWIFTDRIVER_TOOLING_DIAGNOSTIC_ERROR: CInt = 0;
public let SWIFTDRIVER_TOOLING_DIAGNOSTIC_WARNING: CInt = 1;
public let SWIFTDRIVER_TOOLING_DIAGNOSTIC_REMARK: CInt = 2;
public let SWIFTDRIVER_TOOLING_DIAGNOSTIC_NOTE: CInt = 3;

@_cdecl("swift_getSingleFrontendInvocationFromDriverArgumentsV2")
public func getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: UnsafePointer<CChar>,
                                                             argListCount: CInt,
                                                             argList: UnsafePointer<UnsafePointer<CChar>?>,
                                                             action: @convention(c) (CInt, UnsafePointer<UnsafePointer<CChar>?>) -> Bool,
                                                             diagnosticCallback: @convention(c) (CInt, UnsafePointer<CChar>) -> Void,
                                                             forceNoOutputs: Bool = false) -> Bool {
  return getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: driverPath, argListCount: argListCount,
                                                          argList: argList, action: action,
                                                          diagnosticCallback: diagnosticCallback,
                                                          compilerIntegratedTooling: true)
}

@_cdecl("swift_getSingleFrontendInvocationFromDriverArgumentsV3")
public func getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: UnsafePointer<CChar>,
                                                             argListCount: CInt,
                                                             argList: UnsafePointer<UnsafePointer<CChar>?>,
                                                             action: @convention(c) (CInt, UnsafePointer<UnsafePointer<CChar>?>) -> Bool,
                                                             diagnosticCallback: @convention(c) (CInt, UnsafePointer<CChar>) -> Void,
                                                             compilerIntegratedTooling: Bool = false,
                                                             forceNoOutputs: Bool = false) -> Bool {
  // Bridge the driver path argument
  let bridgedDriverPath = String(cString: driverPath)

  // Bridge the argv equivalent
  let argListBufferPtr = UnsafeBufferPointer<UnsafePointer<CChar>?>(start: argList, count: Int(argListCount))
  let bridgedArgList = [bridgedDriverPath] + argListBufferPtr.map { String(cString: $0!) }

  // Bridge the action callback
  let bridgedAction: ([String]) -> Bool = { args in
    return withArrayOfCStrings(args) {
      return action(CInt(args.count), $0!)
    }
  }

  // Bridge the diagnostic callback
  let bridgedDiagnosticCallback: (CInt, String) -> Void = { diagKind, message in
    diagnosticCallback(diagKind, message)
  }

  var diagnostics: [Diagnostic] = []
  let result = getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: bridgedDriverPath,
                                                                argList: bridgedArgList,
                                                                action: bridgedAction,
                                                                diagnostics: &diagnostics,
                                                                diagnosticCallback: bridgedDiagnosticCallback,
                                                                compilerIntegratedTooling: compilerIntegratedTooling,
                                                                forceNoOutputs: forceNoOutputs)
  return result
}

public func getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: String,
                                                             argList: [String],
                                                             action: ([String]) -> Bool,
                                                             diagnostics: inout [Diagnostic],
                                                             diagnosticCallback:  @escaping (CInt, String) -> Void,
                                                             compilerIntegratedTooling: Bool = false,
                                                             forceNoOutputs: Bool = false) -> Bool {
    let env = ProcessEnv.vars
    let executor: SimpleExecutor
    do {
        let resolver = try ArgsResolver(fileSystem: localFileSystem)
        executor = SimpleExecutor(resolver: resolver,
                                      fileSystem: localFileSystem,
                                      env: env)
    } catch {
        print("Unexpected error: \(error)")
        return true
    }

    return getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: driverPath, argList: argList, action: action, diagnostics: &diagnostics, diagnosticCallback: diagnosticCallback, env: env, executor: executor, compilerIntegratedTooling: compilerIntegratedTooling, forceNoOutputs: forceNoOutputs)
}

public func getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: String,
                                                             argList: [String],
                                                             action: ([String]) -> Bool,
                                                             diagnostics: inout [Diagnostic],
                                                             diagnosticCallback:  @escaping (CInt, String) -> Void,
                                                             env: [String: String],
                                                             executor: some DriverExecutor,
                                                             compilerIntegratedTooling: Bool = false,
                                                             forceNoOutputs: Bool = false) -> Bool {
  return getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: driverPath, argList: argList, action: action, diagnostics: &diagnostics, diagnosticCallback: diagnosticCallback, env: env, executor: executor, compilerIntegratedTooling: compilerIntegratedTooling, compilerExecutableDir: nil, forceNoOutputs: forceNoOutputs)
}

/// Generates the list of arguments that would be passed to the compiler
/// frontend from the given driver arguments, for a single-compiler-invocation
/// context.
///
/// \param driverPath the driver executable path
/// \param argList The driver arguments (i.e. normal arguments for \c swiftc).
/// \param diagnostics Contains the diagnostics emitted by the driver
/// \param action invokes a user-provided action on the resulting frontend invocation command
/// \param compilerIntegratedTooling If true, this code is executed in the context of a
///        Swift compiler image which contains symbols normally queried from a libSwiftScan instance.
/// \param forceNoOutputs If true, override the output mode to "-typecheck" and
/// produce no outputs. For example, this disables "-emit-module" and "-c" and
/// prevents the creation of temporary files.
///
/// \returns true on error
///
/// \note This function is not intended to create invocations which are
/// suitable for use in REPL or immediate modes.
public func getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: String,
                                                             argList: [String],
                                                             action: ([String]) -> Bool,
                                                             diagnostics: inout [Diagnostic],
                                                             diagnosticCallback:  @escaping (CInt, String) -> Void,
                                                             env: [String: String],
                                                             executor: some DriverExecutor,
                                                             compilerIntegratedTooling: Bool = false,
                                                             compilerExecutableDir: AbsolutePath? = nil,
                                                             forceNoOutputs: Bool = false) -> Bool {
  /// Handler for emitting diagnostics to tooling clients.
  let toolingDiagnosticsHandler: DiagnosticsEngine.DiagnosticsHandler = { diagnostic in
    let diagnosticKind: CInt
    switch diagnostic.message.behavior {
    case .error:
      diagnosticKind = SWIFTDRIVER_TOOLING_DIAGNOSTIC_ERROR
    case .warning:
      diagnosticKind = SWIFTDRIVER_TOOLING_DIAGNOSTIC_WARNING
    case .note:
      diagnosticKind = SWIFTDRIVER_TOOLING_DIAGNOSTIC_NOTE
    case .remark:
      diagnosticKind = SWIFTDRIVER_TOOLING_DIAGNOSTIC_REMARK
    default:
      diagnosticKind = SWIFTDRIVER_TOOLING_DIAGNOSTIC_ERROR
    }
    diagnosticCallback(diagnosticKind, diagnostic.message.text)
  }
  let diagnosticsEngine = DiagnosticsEngine(handlers: [toolingDiagnosticsHandler])
  defer { diagnostics = diagnosticsEngine.diagnostics }

  var singleFrontendTaskCommand: [String] = []
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

  do {
    args = try [driverPath] + Driver.expandResponseFiles(args,
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
    var driver = try Driver(args: parsedOptions.commandLine,
                            env: env,
                            diagnosticsOutput: .engine(diagnosticsEngine),
                            executor: executor,
                            compilerIntegratedTooling: compilerIntegratedTooling,
                            compilerExecutableDir: compilerExecutableDir)
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
    singleFrontendTaskCommand = try executor.resolver.resolveArgumentList(for: compileJob, useResponseFiles: .disabled)
  } catch {
    print("Unexpected error: \(error).")
    return true
  }

  return action(singleFrontendTaskCommand)
}
