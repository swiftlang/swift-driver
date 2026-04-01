//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Dispatch

/// A lightweight time trace profiler for the Swift driver.
///
/// Produces output compatible with LLVM's TimeProfiler JSON format, which can
/// be viewed in chrome://tracing or Perfetto. When `-time-trace` is passed to
/// the driver, events are recorded for key phases (planning, dependency
/// scanning, job execution) and written to a `.driver.time-trace.json` file
/// that SwiftPM's `importCompilerTimeTraces` picks up automatically.
public final class TimeTrace {
  struct Event {
    let name: String
    let startMicroseconds: Int64
    let durationMicroseconds: Int64
  }

  public let enabled: Bool
  private let beginningOfTime: Int64
  private let startNanos: UInt64
  private(set) var events: [Event] = []
  private let pid: Int32

  public init(enabled: Bool = false) {
    self.enabled = enabled
    self.beginningOfTime = Int64(Date().timeIntervalSince1970 * 1_000_000)
    self.startNanos = DispatchTime.now().uptimeNanoseconds
    self.pid = ProcessInfo.processInfo.processIdentifier
  }

  /// Measure a block and record it as a trace event.
  /// When `enabled` is `false`, just executes the body without recording.
  @discardableResult
  public func measure<T>(_ name: String, body: () throws -> T) rethrows -> T {
    guard enabled else { return try body() }
    let eventStartNanos = DispatchTime.now().uptimeNanoseconds
    let result = try body()
    let eventEndNanos = DispatchTime.now().uptimeNanoseconds
    let startUs = Int64(eventStartNanos - startNanos) / 1000
    let durUs = Int64(eventEndNanos - eventStartNanos) / 1000
    events.append(Event(
      name: name,
      startMicroseconds: startUs,
      durationMicroseconds: durUs
    ))
    return result
  }

  /// Check if an event with the given name has been recorded.
  public func hasEvent(named name: String) -> Bool {
    events.contains { $0.name == name }
  }

  /// Write the trace to a JSON file at the given path.
  /// When `enabled` is `false`, returns without writing.
  public func write(to path: String) throws {
    guard enabled else { return }
    var traceEvents: [[String: Any]] = []

    for event in events {
      traceEvents.append([
        "pid": pid,
        "tid": 0,
        "ts": event.startMicroseconds,
        "ph": "X",
        "dur": event.durationMicroseconds,
        "name": event.name,
      ])
    }

    // Add process_name metadata
    traceEvents.append([
      "pid": pid,
      "tid": 0,
      "ts": 0,
      "ph": "M",
      "name": "process_name",
      "args": ["name": "swift-driver"],
    ])

    let output: [String: Any] = [
      "beginningOfTime": beginningOfTime,
      "traceEvents": traceEvents,
    ]

    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    try data.write(to: URL(fileURLWithPath: path))
  }
}
