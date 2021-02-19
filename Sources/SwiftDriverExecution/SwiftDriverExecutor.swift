//===--- MultiJobExecutor.swift - Builtin DriverExecutor implementation ---===//
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
import TSCBasic
import Foundation
import TSCUtility

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
                      recordedInputModificationDates: [TypedVirtualPath: Date] = [:]) throws -> ProcessResult {
    let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                               forceResponseFiles: forceResponseFiles)

    try job.verifyInputsNotModified(since: recordedInputModificationDates,
                                    fileSystem: fileSystem)

    if job.requiresInPlaceExecution {
      for (envVar, value) in job.extraEnvironment {
        try ProcessEnv.setVar(envVar, value: value)
      }

      try exec(path: arguments[0], args: arguments)
      fatalError("unreachable, exec always throws on failure")
    } else {
      var childEnv = env
      childEnv.merge(job.extraEnvironment, uniquingKeysWith: { (_, new) in new })

      let process = try Process.launchProcess(arguments: arguments, env: childEnv)
      return try process.waitUntilExit()
    }
  }

  private class JobCollectorDelegate: JobExecutionDelegate {
    let subDelegate: JobExecutionDelegate
    var startedJobs: [(Job, Int)] = []
    var finishedJobs = Set<Job>()

    init(subDelegate: JobExecutionDelegate) {
      self.subDelegate = subDelegate
    }
    func jobStarted(job: Job, arguments: [String], pid: Int) {
      subDelegate.jobStarted(job: job, arguments: arguments, pid: pid)
      startedJobs.append((job, pid))
    }

    func jobFinished(job: Job, result: ProcessResult, pid: Int) {
      subDelegate.jobFinished(job: job, result: result, pid: pid)
      finishedJobs.insert(job)
    }

    func jobSkipped(job: Job) {
      subDelegate.jobSkipped(job: job)
    }

    func createSignaledResult(_ job: Job, executor: DriverExecutor, forceResponseFiles: Bool,
                              environment: [String: String]) throws -> ProcessResult {
      let arguments: [String] = try executor.resolver.resolveArgumentList(for: job,
        forceResponseFiles: forceResponseFiles)
      return ProcessResult(arguments: arguments, environment: environment,
                           exitStatus: .signalled(signal: 0),
                           output: .success([]),
                           stderrOutput: .success([]))
    }

    func reportSignaledJobs(executor: DriverExecutor, forceResponseFiles: Bool) throws {
      try startedJobs.filter {!finishedJobs.contains($0.0)}.forEach {
        subDelegate.jobFinished(job: $0.0, result:
          try createSignaledResult($0.0, executor: executor, forceResponseFiles: forceResponseFiles,
                                   environment: [:]), pid: $0.1)
      }
    }
  }

  public func execute(workload: DriverExecutorWorkload,
                      delegate: JobExecutionDelegate,
                      numParallelJobs: Int = 1,
                      forceResponseFiles: Bool = false,
                      recordedInputModificationDates: [TypedVirtualPath: Date] = [:]
  ) throws {
    let realDelegate = JobCollectorDelegate(subDelegate: delegate)
    let _ = try InterruptHandler {
      self.processSet.terminate()
      do {
        try realDelegate.reportSignaledJobs(executor: self,
                                            forceResponseFiles: forceResponseFiles)
      } catch {

      }
    }
    let llbuildExecutor = MultiJobExecutor(
      workload: workload,
      resolver: resolver,
      executorDelegate: realDelegate,
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
    let (args, usedResponseFile) = try resolver.resolveArgumentList(for: job, forceResponseFiles: forceResponseFiles)
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
