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
  var resolver: ArgsResolver { get }

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

  /// Returns a textual description of the job as it would be run by the executor.
  func description(of job: Job, forceResponseFiles: Bool) throws -> String
}

enum JobExecutionError: Error {
  case jobFailedWithNonzeroExitCode(Int, String)
  case failedToReadJobOutput
  // A way to pass more information to the catch point
  case decodingError(DecodingError, Data, ProcessResult)
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
      let returnCode = Self.computeReturnCode(exitStatus: result.exitStatus)
      throw JobExecutionError.jobFailedWithNonzeroExitCode(returnCode, try result.utf8stderrOutput())
    }
    guard let outputData = try? Data(result.utf8Output().utf8) else {
      throw JobExecutionError.failedToReadJobOutput
    }

    do {
      return try JSONDecoder().decode(outputType, from: outputData)
    }
    catch let err as DecodingError {
      throw JobExecutionError.decodingError(err, outputData, result)
    }
  }

  static func computeReturnCode(exitStatus: ProcessResult.ExitStatus) -> Int {
    var returnCode: Int
    switch exitStatus {
      case .terminated(let code):
        returnCode = Int(code)
      #if !os(Windows)
      case .signalled(let signal):
        returnCode = Int(signal)
      #endif
    }
    return returnCode
  }
}

public protocol JobExecutionDelegate {
  /// Called when a job starts executing.
  func jobStarted(job: Job, arguments: [String], pid: Int)
  
  /// Called when a job finished. May return newly discovered jobs.
  func jobFinished(job: Job, result: ProcessResult, pid: Int) -> [Job]
}
