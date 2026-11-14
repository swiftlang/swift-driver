//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

@_spi(Testing) import SwiftDriver

import class TSCBasic.DiagnosticsEngine
import func TSCBasic.withTemporaryDirectory

@Suite struct TraceEventsWriterTests {
  @Test func writeAnEventAsJSONArray() async throws {
    let event = TraceEvent(
      name: "Compiling main.swift", category: "build", phase: .complete,
      timestamp: 1_000, duration: 250, processID: 42, threadID: 1,
      arguments: ["result": .string("success"), "inputs": .int(2)])
    let events = try await trace { $0.write(event) }
    #expect(events == [event])
  }

  /// Closing the writer multiple times is OK.
  @Test func redundantCloseCalls() async throws {
    let events = try await trace { writer in
      writer.write(.processName("swift-driver"))
      writer.close()
    }
    #expect(events.count == 1)
  }

#if !os(Windows)
  @Test func eventWithProcessID() {
    #expect(TraceEvent.currentProcessID == getpid())
    #expect(TraceEvent.processName("swift-driver").processID == getpid())
  }
#endif

#if canImport(Darwin) || canImport(Glibc)
  @Test func timestampsUseMachineClock() {
    let before = machineClock()
    let now = TraceClock.now()
    let after = machineClock()
    #expect(before <= now && now <= after)
  }

  /// Tracing must use the machine clock so that trace events from distinct
  /// processes can align their timelines
  private func machineClock() -> Int64 {
#if canImport(Darwin)
    Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1_000)
#else
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return Int64(now.tv_sec) * 1_000_000 + Int64(now.tv_nsec) / 1_000
#endif
  }
#endif

  @Test func metadataBasics() {
    let process = TraceEvent.processName("swift-driver")
    #expect(process.phase == .metadata)
    #expect(process.name == "process_name")
    #expect(process.arguments == ["name": .string("swift-driver")])
    let thread = TraceEvent.threadName("Lane 2", threadID: 2)
    #expect(thread.name == "thread_name")
    #expect(thread.threadID == 2)
    #expect(TraceEvent.threadSortIndex(2, threadID: 2).arguments == ["sort_index": .int(2)])
  }

  /// Helper to round-trip trace files
  private func trace(_ body: (TraceEventsWriter) async throws -> Void) async throws -> [TraceEvent] {
    try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmp in
      let path = tmp.appending(component: "trace.json")
      let writer = try TraceEventsWriter(path: path, diagnosticEngine: DiagnosticsEngine())
      try await body(writer)
      writer.close()
      return try JSONDecoder().decode(
        [TraceEvent].self, from: Data(contentsOf: URL(fileURLWithPath: path.pathString)))
    }
  }

  @Test func concurrentEventWriting() async throws {
    let events = try await trace { writer in
      await withTaskGroup { group in
        for i in 0..<1_000 {
          group.addTask {
            let e = TraceEvent(name: "job \(i)", category: "build", phase: .instant,
                               timestamp: TraceClock.now(), threadID: i % 8)
            writer.write(e)
          }
        }
      }
    }
    #expect(events.count == 1_000)
    #expect(Set(events.map(\.name)).count == 1_000)
  }

  #if !os(Windows)
  /// Since the driver spawns child processes, ensure that the trace files
  /// opened by the driver aren't inherited as open by children as we don't
  /// allow for multiple processes writing a single file.
  @Test func childProcessesDoNotInheritTraceFileDescriptor() throws {
    try withTemporaryDirectory(removeTreeOnDeinit: true) { tmp in
      let path = tmp.appending(component: "trace.json")
      let writer = try TraceEventsWriter(path: path, diagnosticEngine: DiagnosticsEngine())
      defer { writer.close() }
      #expect(fcntl(writer.fileDescriptor, F_GETFD) & FD_CLOEXEC != 0)
    }
  }

  /// Ensure trace file writes are done with methods that throw catchable Swift
  /// exceptions on failure. Not e.g. write(2)
  @Test func gracefulFailedWrites() async {
    await #expect(processExitsWith: .success) {
      try withTemporaryDirectory(removeTreeOnDeinit: true) { tmp in
        let writer = try TraceEventsWriter(
          path: tmp.appending(component: "trace.json"), diagnosticEngine: DiagnosticsEngine())

        // Cause artificial failures
        _ = close(writer.fileDescriptor)
        writer.write(.processName("swift-driver"))
        writer.close()
      }
    }
  }

  /// A failure to close the file should not crash.
  @Test func gracefulFailedClose() async {
    await #expect(processExitsWith: .success) {
      try withTemporaryDirectory(removeTreeOnDeinit: true) { tmp in
        let writer = try TraceEventsWriter(
          path: tmp.appending(component: "trace.json"), diagnosticEngine: DiagnosticsEngine())
        writer.write(.processName("swift-driver"))

        // Cause artificial failures
        _ = close(writer.fileDescriptor)
        writer.close()
      }
    }
  }
  #endif
}

@Suite struct TraceLanesTests {
  @Test func overlappingSpansAssignedDistinctLanes() {
    let lanes = TraceLanes()
    let taken: [Int] = [lanes.acquire(), lanes.acquire(), lanes.acquire()]
    #expect(taken == [1, 2, 3])
  }

  @Test func freeLaneReuse() {
    let lanes = TraceLanes()
    let a = lanes.acquire(), _ = lanes.acquire()
    lanes.release(a)
    #expect(lanes.acquire() == a)
  }

  @Test func lowestFreeLaneReused() {
    let lanes = TraceLanes()
    let one = lanes.acquire(), _ = lanes.acquire(), three = lanes.acquire(), _ = lanes.acquire()
    lanes.release(one)
    lanes.release(three)
    #expect(lanes.acquire() == 1)
    #expect(lanes.used == 1..<5)
  }

  @Test func distinctThreadsAssignedDistinctLanes() {
    let lanes = TraceLanes()
    let lock = NSLock()
    var taken: [Int] = []
    DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
      let lane = lanes.acquire()
      lock.withLock { taken.append(lane) }
    }
    #expect(Set(taken).count == 1_000)
    #expect(lanes.used == 1..<1_001)
  }
}
