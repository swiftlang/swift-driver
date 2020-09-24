//===--------------- ToolExecutionDelegate.swift - Tool Execution Delegate ===//
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
import TSCBasic

#if canImport(Darwin)
import Darwin.C
#elseif os(Windows)
import MSVCRT
import WinSDK
#elseif canImport(Glibc)
import Glibc
#else
#error("Missing libc or equivalent")
#endif

/// Delegate for printing execution information on the command-line.
struct ReferenceDependenciesProcessingDelegate: JobExecutionDelegate {
  let driver: Driver
  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    assert(driver.parsedOptions.hasArgument(.incremental))
  }
  
  public func jobFinished(job: Job, result: ProcessResult, pid: Int) -> [Job] {
    guard case .compile = job.kind else {return []}
    let swiftDepsOutputs = job.outputs.filter {$0.type == .swiftDeps}
    return driver.additionalJobs(updatingDependenciesWith: swiftDepsOutputs, exitStatus: result.exitStatus)
  }
}
