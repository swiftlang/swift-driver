//===--------------- DriverExecutor.swift - Swift Driver Executor----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic
import Foundation

public protocol DriverExecutor {
  /// Execute a single job and capture the output.
  @discardableResult
  func execute(job: Job,
               forceResponseFiles: Bool,
               recordedInputModificationDates: [TypedVirtualPath: Date]) throws -> ProcessResult
  
  /// Execute multiple jobs, tracking job status using the provided execution delegate.
  func execute(jobs: [Job],
               delegate: JobExecutionDelegate,
               numParallelJobs: Int,
               forceResponseFiles: Bool,
               recordedInputModificationDates: [TypedVirtualPath: Date]
  ) throws
  
  /// Launch a process with the given command line and report the result.
  @discardableResult
  func checkNonZeroExit(args: String..., environment: [String: String]) throws -> String
}

enum JobExecutionError: Error {
  case jobFailedWithNonzeroExitCode(Int, String)
  case failedToReadJobOutput
}

extension DriverExecutor {
  func execute<T: Decodable>(job: Job,
                             capturingJSONOutputAs outputType: T.Type,
                             forceResponseFiles: Bool,
                             recordedInputModificationDates: [TypedVirtualPath: Date]) throws -> T {
    let result = try execute(job: job,
                             forceResponseFiles: forceResponseFiles,
                             recordedInputModificationDates: recordedInputModificationDates)
    
    if (result.exitStatus != .terminated(code: EXIT_SUCCESS)) {
      let returnCode: Int
      switch result.exitStatus {
      case .terminated(let code):
        returnCode = Int(code)
      case .signalled(let signal):
        returnCode = Int(signal)
      }
      throw JobExecutionError.jobFailedWithNonzeroExitCode(returnCode, try result.utf8stderrOutput())
    }
    guard let outputData = try? Data(result.utf8Output().utf8) else {
      throw JobExecutionError.failedToReadJobOutput
    }
    
    return try JSONDecoder().decode(outputType, from: outputData)
  }
}

public protocol JobExecutionDelegate {
  /// Called when a job starts executing.
  func jobStarted(job: Job, arguments: [String], pid: Int)
  
  /// Called when a job finished.
  func jobFinished(job: Job, result: ProcessResult, pid: Int)
}

public final class SwiftDriverExecutor: DriverExecutor {
  let diagnosticsEngine: DiagnosticsEngine
  let processSet: ProcessSet
  let fileSystem: FileSystem
  let resolver: ArgsResolver
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
  
  public func execute(jobs: [Job],
                      delegate: JobExecutionDelegate,
                      numParallelJobs: Int = 1,
                      forceResponseFiles: Bool = false,
                      recordedInputModificationDates: [TypedVirtualPath: Date] = [:]
  ) throws {
    let llbuildExecutor = MultiJobExecutor(jobs: jobs,
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
}
