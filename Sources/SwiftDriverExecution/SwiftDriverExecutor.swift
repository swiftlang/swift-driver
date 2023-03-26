//===- SwiftDriverExecutor.swift - Builtin DriverExecutor implementation --===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftDriver
import class Foundation.FileHandle

import class TSCBasic.DiagnosticsEngine
import class TSCBasic.Process
import class TSCBasic.ProcessSet
import enum TSCBasic.ProcessEnv
import func TSCBasic.exec
import protocol TSCBasic.FileSystem
import struct TSCBasic.ProcessResult

public final class SwiftDriverExecutor: DriverExecutor {
  let diagnosticsEngine: DiagnosticsEngine
  let processSet: ProcessSet
  let fileSystem: FileSystem
  public let resolver: ArgsResolver
  let env: [String: String]

  public init(diagnosticsEngine: DiagnosticsEngine,
              processSet: ProcessSet,
              fileSystem: FileSystem,
              env: [String: String]) throws {
    self.diagnosticsEngine = diagnosticsEngine
    self.processSet = processSet
    self.fileSystem = fileSystem
    self.env = env
    self.resolver = try ArgsResolver(fileSystem: fileSystem)
  }

  public func execute(job: Job,
                      forceResponseFiles: Bool = false,
                      recordedInputModificationDates: [TypedVirtualPath: TimePoint] = [:]) throws -> ProcessResult {
    let useResponseFiles : ResponseFileHandling = forceResponseFiles ? .forced : .heuristic
    let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                               useResponseFiles: useResponseFiles)

    try job.verifyInputsNotModified(since: recordedInputModificationDates,
                                    fileSystem: fileSystem)

    if job.requiresInPlaceExecution {
      for (envVar, value) in job.extraEnvironment {
        try ProcessEnv.setVar(envVar, value: value)
      }

      try exec(path: arguments[0], args: arguments)
    } else {
      var childEnv = env
      childEnv.merge(job.extraEnvironment, uniquingKeysWith: { (_, new) in new })
      let process : ProcessProtocol
      if job.inputs.contains(TypedVirtualPath(file: .standardInput, type: .swift)) {
        process = try Process.launchProcessAndWriteInput(
          arguments: arguments, env: childEnv, inputFileHandle: FileHandle.standardInput
        )
      } else {
        process = try Process.launchProcess(arguments: arguments, env: childEnv)
      }
      return try process.waitUntilExit()
    }
  }

  public func execute(workload: DriverExecutorWorkload,
                      delegate: JobExecutionDelegate,
                      numParallelJobs: Int = 1,
                      forceResponseFiles: Bool = false,
                      recordedInputModificationDates: [TypedVirtualPath: TimePoint] = [:]
  ) throws {
    let llbuildExecutor = MultiJobExecutor(
      workload: workload,
      resolver: resolver,
      executorDelegate: delegate,
      diagnosticsEngine: diagnosticsEngine,
      numParallelJobs: numParallelJobs,
      processSet: processSet,
      forceResponseFiles: forceResponseFiles,
      recordedInputModificationDates: recordedInputModificationDates)
    try llbuildExecutor.execute(env: env, fileSystem: fileSystem)
  }

  @discardableResult
  public func checkNonZeroExit(args: String..., environment: [String: String] = ProcessEnv.vars) throws -> String {
    return try Process.checkNonZeroExit(arguments: args, environment: environment)
  }

  public func description(of job: Job, forceResponseFiles: Bool) throws -> String {
    let useResponseFiles : ResponseFileHandling = forceResponseFiles ? .forced : .heuristic
    let (args, usedResponseFile) = try resolver.resolveArgumentList(for: job, useResponseFiles: useResponseFiles)
    var result = args.map { $0.spm_shellEscaped() }.joined(separator: " ")

    if usedResponseFile {
      // Print the response file arguments as a comment.
      result += " # \(job.commandLine.joinedUnresolvedArguments)"
    }

    if !job.extraEnvironment.isEmpty {
      result += " #"
      for (envVar, val) in job.extraEnvironment {
        result += " \(envVar)=\(val)"
      }
    }
    return result
  }
}
