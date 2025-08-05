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
import enum TSCBasic.ProcessEnv
import func TSCBasic.exec
import protocol TSCBasic.FileSystem
import struct TSCBasic.ProcessResult
import typealias TSCBasic.ProcessEnvironmentBlock

public final class SwiftDriverExecutor: DriverExecutor {
  let diagnosticsEngine: DiagnosticsEngine
  let processSet: ProcessSet
  let fileSystem: FileSystem
  public let resolver: ArgsResolver
  let env: ProcessEnvironmentBlock

  public init(diagnosticsEngine: DiagnosticsEngine,
              processSet: ProcessSet,
              fileSystem: FileSystem,
              env: ProcessEnvironmentBlock) throws {
    self.diagnosticsEngine = diagnosticsEngine
    self.processSet = processSet
    self.fileSystem = fileSystem
    self.env = env
    self.resolver = try ArgsResolver(fileSystem: fileSystem)
  }

  public func execute(job: Job,
                      forceResponseFiles: Bool = false,
                      recordedInputMetadata: [TypedVirtualPath: FileMetadata] = [:]) throws -> ProcessResult {
    let useResponseFiles : ResponseFileHandling = forceResponseFiles ? .forced : .heuristic
    let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                               useResponseFiles: useResponseFiles)

    try job.verifyInputsNotModified(since: recordedInputMetadata.mapValues{metadata in metadata.mTime},
                                    fileSystem: fileSystem)

    if job.requiresInPlaceExecution {
      for (envVar, value) in job.extraEnvironmentBlock {
        try ProcessEnv.setVar(envVar.value, value: value)
      }

      try exec(path: arguments[0], args: arguments)
    } else {
      var childEnv = env
      childEnv.merge(job.extraEnvironmentBlock, uniquingKeysWith: { (_, new) in new })
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

  public func execute(job: Job,
                      forceResponseFiles: Bool,
                      recordedInputModificationDates: [TypedVirtualPath : TimePoint]) throws -> ProcessResult {
    fatalError("Unsupported legacy operation on current executor")
  }

  public func execute(workload: DriverExecutorWorkload,
                      delegate: JobExecutionDelegate,
                      numParallelJobs: Int = 1,
                      forceResponseFiles: Bool = false,
                      recordedInputMetadata: [TypedVirtualPath: FileMetadata] = [:]
  ) throws {
    let llbuildExecutor = MultiJobExecutor(
      workload: workload,
      resolver: resolver,
      executorDelegate: delegate,
      diagnosticsEngine: diagnosticsEngine,
      numParallelJobs: numParallelJobs,
      processSet: processSet,
      forceResponseFiles: forceResponseFiles,
      recordedInputMetadata: recordedInputMetadata)
    try llbuildExecutor.execute(env: env, fileSystem: fileSystem)
  }

  public func execute(workload: DriverExecutorWorkload,
                      delegate: JobExecutionDelegate,
                      numParallelJobs: Int = 1,
                      forceResponseFiles: Bool = false,
                      recordedInputModificationDates: [TypedVirtualPath: TimePoint]) throws {
    fatalError("Unsuppored legacy operation on current executor")
  }

  @discardableResult
  public func checkNonZeroExit(args: String..., environment: [String: String] = ProcessEnv.vars) throws -> String {
    try Process.checkNonZeroExit(arguments: args, environmentBlock: ProcessEnvironmentBlock(environment))
  }

  @discardableResult
  public func checkNonZeroExit(args: String..., environmentBlock: ProcessEnvironmentBlock = ProcessEnv.block) throws -> String {
    try Process.checkNonZeroExit(arguments: args, environmentBlock: environmentBlock)
  }

  public func description(of job: Job, forceResponseFiles: Bool) throws -> String {
    let useResponseFiles : ResponseFileHandling = forceResponseFiles ? .forced : .heuristic
    let (args, usedResponseFile) = try resolver.resolveArgumentList(for: job, useResponseFiles: useResponseFiles)
    var result = args.map { $0.spm_shellEscaped() }.joined(separator: " ")

    if usedResponseFile {
      // Print the response file arguments as a comment.
      result += " # \(job.commandLine.joinedUnresolvedArguments)"
    }

    if !job.extraEnvironmentBlock.isEmpty {
      result += " #"
      for (envVar, val) in job.extraEnvironmentBlock {
        result += " \(envVar)=\(val)"
      }
    }
    return result
  }
}
