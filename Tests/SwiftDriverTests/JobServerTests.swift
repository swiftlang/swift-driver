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

import XCTest
import Foundation

import class TSCBasic.DiagnosticsEngine
import typealias TSCBasic.ProcessEnvironmentBlock

@testable import SwiftDriverExecution

#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

final class JobServerTests: XCTestCase {

  func testParsingJobServerAuthentication() {
    XCTAssertEqual(JobServer.parseAuthentication(from: "--jobserver-auth=3,4"), "3,4")

    // GNU make 4.1 and earlier -- including the make 3.81 shipped as
    // `/usr/bin/make` on macOS -- only ever emit the old spelling.
    XCTAssertEqual(JobServer.parseAuthentication(from: "w -j --jobserver-fds=7,8 --debug"),
                   "7,8")

    // GNU make 4.4 can advertise a named FIFO instead of descriptors.
    XCTAssertEqual(JobServer.parseAuthentication(from: "--jobserver-auth=fifo:/tmp/GMfifo1"),
                   "fifo:/tmp/GMfifo1")

    // Later flags override earlier ones, so the last occurrence wins.
    XCTAssertEqual(JobServer.parseAuthentication(from: "--jobserver-fds=1,2 --jobserver-auth=5,6"),
                   "5,6")

    XCTAssertNil(JobServer.parseAuthentication(from: "-j8 --output-sync"))
    XCTAssertNil(JobServer.parseAuthentication(from: ""))
  }

  func testDetectRequiresOptIn() {
    let diagnosticsEngine = DiagnosticsEngine()

    // Without the opt-in flag, an advertised pool alone does not join the build.
    XCTAssertNil(JobServer.detect(
      env: ProcessEnvironmentBlock(["MAKEFLAGS": "--jobserver-auth=3,4"]),
      enabled: false, diagnosticsEngine: diagnosticsEngine))

    // Opted in, but no pool advertised: nothing to join, and no diagnostic.
    XCTAssertNil(JobServer.detect(
      env: ProcessEnvironmentBlock([String: String]()),
      enabled: true, diagnosticsEngine: diagnosticsEngine))

    XCTAssertFalse(diagnosticsEngine.hasErrors)
  }

#if !os(Windows)
  func testRejectingAnUnusablePool() {
    XCTAssertNil(JobServer(auth: "not-a-pool"))
    XCTAssertNil(JobServer(auth: "3"))
    XCTAssertNil(JobServer(auth: "fifo:/definitely/not/a/fifo"))

    // Descriptors that are not open: what GNU make leaves behind for a recipe
    // it did not treat as recursive.
    XCTAssertNil(JobServer(auth: "9998,9999"))
  }

  func testConcurrencyIsBoundedByThePool() throws {
    // Three tokens, plus the implicit one this process already owns because
    // whoever launched it spent a token to do so: `make -j4`.
    let tokens = [UInt8(ascii: "a"), UInt8(ascii: "b"), UInt8(ascii: "c")]

    var peak = 0
    let returned = try withPipePool(seededWith: tokens) { jobServer in
      peak = self.peakConcurrency(over: jobServer, jobCount: 60)
    }

    XCTAssertLessThanOrEqual(peak, tokens.count + 1,
                             "ran more jobs at once than the pool allows")
    XCTAssertGreaterThan(peak, 1, "never ran two jobs at once")

    // A token that is not returned shrinks the pool for the rest of the build,
    // and the protocol requires writing back the same byte that was read rather
    // than an arbitrary one.
    XCTAssertEqual(returned.sorted(), tokens.sorted())
  }

  func testEmptyPoolSerializesOnTheImplicitToken() throws {
    // A client with no spare tokens may still run one job at a time. Returning
    // the implicit token puts nothing into the pipe, so this covers a waiter
    // sleeping through its own token becoming free again -- which deadlocked
    // the build after its first job.
    var peak = 0
    let returned = try withPipePool(seededWith: []) { jobServer in
      peak = self.peakConcurrency(over: jobServer, jobCount: 8)
    }

    XCTAssertEqual(peak, 1)
    XCTAssertEqual(returned, [])
  }

  func testShutDownDoesNotBlockOnAnEmptyPool() throws {
    _ = try withPipePool(seededWith: []) { jobServer in
      let queue = OperationQueue()
      queue.maxConcurrentOperationCount = .max
      let dispatcher = JobServerDispatcher(jobServer: jobServer, queue: queue)
      dispatcher.start()

      let finished = expectation(description: "jobs ran")
      finished.expectedFulfillmentCount = 4
      for _ in 0..<4 {
        dispatcher.enqueue { finished.fulfill() }
      }
      wait(for: [finished], timeout: 60)

      let start = Date()
      dispatcher.shutDown()
      XCTAssertLessThan(Date().timeIntervalSince(start), 3,
                        "teardown blocked waiting for a token")
    }
  }

  func testFIFOTransport() throws {
    // GNU make 4.4 and newer can hand out `fifo:PATH`, which does not depend on
    // descriptors surviving every wrapper process in between.
    let path = NSTemporaryDirectory() + "GMfifo-swift-driver-test-\(getpid())"
    unlink(path)
    XCTAssertEqual(mkfifo(path, 0o600), 0)
    defer { unlink(path) }

    // The server side holds the FIFO open read-write and seeds it with tokens.
    let serverEnd = open(path, O_RDWR)
    XCTAssertGreaterThanOrEqual(serverEnd, 0)
    defer { close(serverEnd) }

    let tokens = [UInt8(ascii: "p"), UInt8(ascii: "q"), UInt8(ascii: "r")]
    for var token in tokens {
      XCTAssertEqual(write(serverEnd, &token, 1), 1)
    }

    let jobServer = try XCTUnwrap(JobServer(auth: "fifo:\(path)"))
    let peak = peakConcurrency(over: jobServer, jobCount: 60)
    XCTAssertLessThanOrEqual(peak, tokens.count + 1)
    XCTAssertGreaterThan(peak, 1)

    XCTAssertEqual(drain(serverEnd).sorted(), tokens.sorted())
  }

  // MARK: - Helpers

  /// Runs `jobCount` trivial jobs through a dispatcher over `jobServer` and
  /// reports the most that were ever in flight at once.
  private func peakConcurrency(over jobServer: JobServer, jobCount: Int) -> Int {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = .max
    let dispatcher = JobServerDispatcher(jobServer: jobServer, queue: queue)
    dispatcher.start()

    let finished = expectation(description: "all \(jobCount) jobs ran")
    finished.expectedFulfillmentCount = jobCount
    let lock = NSLock()
    var running = 0, peak = 0

    for _ in 0..<jobCount {
      dispatcher.enqueue {
        lock.lock()
        running += 1
        peak = max(peak, running)
        lock.unlock()

        // Long enough that jobs genuinely overlap when tokens allow it.
        Thread.sleep(forTimeInterval: 0.01)

        lock.lock()
        running -= 1
        lock.unlock()
        finished.fulfill()
      }
    }

    wait(for: [finished], timeout: 120)
    dispatcher.shutDown()

    lock.lock()
    defer { lock.unlock() }
    return peak
  }

  /// Sets up a pool over a pipe seeded with `tokens`, as a build system running
  /// `-j tokens.count + 1` would, and returns whatever was in it afterwards.
  @discardableResult
  private func withPipePool(seededWith tokens: [UInt8],
                            _ body: (JobServer) throws -> Void) throws -> [UInt8] {
    var descriptors: [CInt] = [0, 0]
    XCTAssertEqual(pipe(&descriptors), 0)
    let readEnd = descriptors[0], writeEnd = descriptors[1]
    defer {
      close(readEnd)
      close(writeEnd)
    }

    for var token in tokens {
      XCTAssertEqual(write(writeEnd, &token, 1), 1)
    }

    try body(try XCTUnwrap(JobServer(auth: "\(readEnd),\(writeEnd)")))
    return drain(readEnd)
  }

  /// Reads everything currently available on `fd` without blocking.
  private func drain(_ fd: CInt) -> [UInt8] {
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    var contents: [UInt8] = []
    while true {
      var byte: UInt8 = 0
      if read(fd, &byte, 1) != 1 { break }
      contents.append(byte)
    }
    return contents
  }
#endif
}
