//====--------------- StatsReporter.swift - Driver performance statistics ====//
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

/// Collects driver performance statistics.
/// WARNING: This class is not thread safe.
@_spi(Testing) public final class StatsReporter {
  private var jobTimers: [Job: Timer] = [:]

  func recordStart(of job: Job) {
    var timer = Timer()
    timer.start()
    jobTimers[job] = timer
  }

  func recordCompletion(of job: Job) {
    jobTimers[job]?.end()
  }
}

extension StatsReporter {
  @_spi(Testing) public func printTimings(to stream: OutputByteStream) {
    let jobs = jobTimers.keys
    let totalUserTime = jobs.map { jobTimers[$0]?.elapsedTime?.userTime.seconds ?? 0 }.reduce(0, +)
    let totalSystemTime = jobs.map { jobTimers[$0]?.elapsedTime?.systemTime.seconds ?? 0 }.reduce(0, +)
    let totalWallTime = jobs.map { jobTimers[$0]?.elapsedTime?.wallTime.seconds ?? 0 }.reduce(0, +)
    let totalUserPlusSystem = totalUserTime + totalSystemTime

    stream <<< "===-------------------------------------------------------------------------===\n"
    stream <<< "                            Driver Compilation Time                            \n"
    stream <<< "===-------------------------------------------------------------------------===\n"
    stream <<< "  Total Execution Time: \(totalUserTime + totalSystemTime, specifier: "%.4f") seconds (\(totalWallTime, specifier: "%.4f") wall clock)\n"
    stream <<< "\n"
    stream <<< "   ----User Time----   ---System Time---   ---User+System---   ----Wall Time----   ---Description---\n"

    var entries: [(Double, String)] = []
    let ts = "%8.4f"
    let ps = "%5.1f"

    for job in jobs {
      let elapsed = jobTimers[job]?.elapsedTime
      let userTime = elapsed?.userTime.seconds ?? 0
      let systemTime = elapsed?.systemTime.seconds ?? 0
      let wallTime = elapsed?.wallTime.seconds ?? 0
      let userPlusSystem = userTime + systemTime
      let tableRow = ["\(userTime, specifier: ts) (\(userTime / totalUserTime * 100, specifier: ps)%)",
                      "\(systemTime, specifier: ts) (\(systemTime / totalSystemTime * 100, specifier: ps)%)",
                      "\(userTime + systemTime, specifier: ts) (\(userPlusSystem / totalUserPlusSystem * 100, specifier: ps)%)",
                      "\(wallTime, specifier: ts) (\(wallTime / totalWallTime * 100, specifier: ps)%)",
                      job.description
      ].joined(separator: "   ")
      entries.append((wallTime, tableRow))
    }

    entries.sorted {
      $0.0 > $1.0
    }.forEach {
      stream <<< "   " <<< $0.1 <<< "\n"
    }

    stream <<< "   \(totalUserTime, specifier: ts) (100.0%)   \(totalSystemTime, specifier: ts) (100.0%)   \(totalUserPlusSystem, specifier: ts) (100.0%)   \(totalWallTime, specifier: ts) (100.0%)   Total\n"

    stream.flush()
  }
}

fileprivate struct Timer {
  private var startedAt: TimeValues? = nil
  private var endedAt: TimeValues? = nil
  private var failed: Bool = false

  init() {}

  mutating func start() {
    assert(startedAt == nil && endedAt == nil)
    startedAt = currentTimeValues()
    if startedAt == nil {
      failed = true
    }
  }

  mutating func end() {
    assert((startedAt != nil || failed) && endedAt == nil)
    endedAt = currentTimeValues()
    if endedAt == nil {
      failed = true
    }
  }

  var elapsedTime: TimeValues? {
    guard let start = startedAt, let end = endedAt else {
      precondition(failed)
      return nil
    }
    return TimeValues(userTime: end.userTime - start.userTime,
                      systemTime: end.systemTime - start.systemTime,
                      wallTime: end.wallTime - start.wallTime)
  }
}

struct StatsReportingExecutionDelegate: JobExecutionDelegate {
  let reporter: StatsReporter

  func jobStarted(job: Job, arguments: [String], pid: Int) {
    reporter.recordStart(of: job)
  }

  func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    reporter.recordCompletion(of: job)
  }
}
