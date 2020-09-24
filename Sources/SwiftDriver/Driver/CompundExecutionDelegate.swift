//===------CompoundExecutionDelegate.swift --------------------------------===//
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

import Foundation
import TSCBasic

/// A delegate compounds the effects of multiple delegates and collects discovered jobs.
public struct CompoundExecutionDelegate: JobExecutionDelegate {
  var delegates: [JobExecutionDelegate]

  public init(delegates: [JobExecutionDelegate]) {
    self.delegates = delegates
  }

  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    delegates.forEach {
      $0.jobStarted(job: job, arguments: arguments, pid: pid)
    }
  }

  public func jobFinished(job: Job, result: ProcessResult, pid: Int) -> [Job] {
    var discoveredJobs: [Job] = []
    delegates.forEach {
      discoveredJobs.append(contentsOf: $0.jobFinished(job: job, result: result, pid: pid))
    }
    return discoveredJobs
  }
}

