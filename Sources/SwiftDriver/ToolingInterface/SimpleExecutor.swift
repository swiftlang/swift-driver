//===------- SimpleExecutor.swift - Swift Driver Source Version-----------===//
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

import protocol TSCBasic.FileSystem
import struct TSCBasic.ProcessResult
import class TSCBasic.Process

/// A simple executor sufficient for managing processes required during
/// build planning: e.g. querying frontend target info.
///
/// TODO: It would be nice if build planning did not involve an executor.
/// We must hunt down all uses of an executor during planning and move
/// relevant compiler functionality into libSwiftScan.
@_spi(Testing) public class SimpleExecutor: DriverExecutor {
  public let resolver: ArgsResolver
  let fileSystem: FileSystem
  let env: [String: String]

  public init(resolver: ArgsResolver, fileSystem: FileSystem, env: [String: String]) {
    self.resolver = resolver
    self.fileSystem = fileSystem
    self.env = env
  }

  public func execute(job: Job,
                      forceResponseFiles: Bool,
                      recordedInputModificationDates: [TypedVirtualPath : TimePoint]) throws -> ProcessResult {
    let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                               useResponseFiles: .heuristic)
    var childEnv = env
    childEnv.merge(job.extraEnvironment, uniquingKeysWith: { (_, new) in new })
    let process = try Process.launchProcess(arguments: arguments, env: childEnv)
    return try process.waitUntilExit()
  }

  public func execute(workload: DriverExecutorWorkload, delegate: JobExecutionDelegate,
                      numParallelJobs: Int, forceResponseFiles: Bool,
                      recordedInputModificationDates: [TypedVirtualPath : TimePoint]) throws {
    fatalError("Unsupported operation on current executor")
  }

  public func checkNonZeroExit(args: String..., environment: [String : String]) throws -> String {
    try Process.checkNonZeroExit(arguments: args, environment: environment)
  }

  public func description(of job: Job, forceResponseFiles: Bool) throws -> String {
    let useResponseFiles : ResponseFileHandling = forceResponseFiles ? .forced : .heuristic
    let (args, usedResponseFile) = try resolver.resolveArgumentList(for: job, useResponseFiles: useResponseFiles)
    var result = args.map { $0.spm_shellEscaped() }.joined(separator: " ")
    if usedResponseFile {
      result += " # \(job.commandLine.joinedUnresolvedArguments)"
    }
    return result
  }
}
