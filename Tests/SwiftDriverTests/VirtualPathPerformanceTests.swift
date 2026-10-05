//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Opt-in, because timings are noisy on CI machines. Run with
// `swift test -c release -Xswiftc -DSWIFT_DRIVER_ENABLE_BENCHMARKS --filter VirtualPathPerformanceTests`.
#if SWIFT_DRIVER_ENABLE_BENCHMARKS

import Foundation
@_spi(Testing) import SwiftDriver
import XCTest

import var TSCBasic.localFileSystem

final class VirtualPathPerformanceTests: XCTestCase {
  /// Worst case for a single driver: every interned path is new to the process, so every call misses the cache.
  func testInterningNewPathsPerformance() throws {
    var batches = (0..<12).map { _ in Self.newPaths(count: Self.benchmarkSize(100_000), prefix: "single") }
    measure {
      for path in batches.removeLast() {
        _ = try! VirtualPath.intern(path: path)
      }
    }
  }

  /// Worst case for drivers sharing a process: many threads intern only new, distinct paths at the same time.
  func testConcurrentInterningNewPathsPerformance() throws {
    let workerCount = 16
    var batches = (0..<12).map { _ in (0..<workerCount).map { Self.newPaths(count: Self.benchmarkSize(10_000), prefix: "worker\($0)") } }
    measure {
      let paths = batches.removeLast()
      DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
        for path in paths[worker] {
          _ = try! VirtualPath.intern(path: path)
        }
      }
    }
  }

  /// Many threads interning cached paths, the most common call in a build.
  func testConcurrentInterningCachedPathsPerformance() throws {
    let workerCount = 16
    let paths = Self.newPaths(count: Self.benchmarkSize(10_000), prefix: "cached")
    for path in paths {
      _ = try VirtualPath.intern(path: path)
    }
    measure {
      DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
        for i in 0..<Self.benchmarkSize(50_000) {
          _ = try! VirtualPath.intern(path: paths[Self.index(i, worker: worker, count: paths.count)])
        }
      }
    }
  }

  /// The common case in a build: many threads resolve paths that are already interned, and some paths
  /// (the SDK, shared output directories) are requested far more often than others.
  func testConcurrentLookupOfInternedPathsPerformance() throws {
    let workerCount = 16
    let handles = try Self.newPaths(count: Self.benchmarkSize(10_000), prefix: "interned").map {
      try VirtualPath.intern(path: $0)
    }
    measure {
      DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
        for i in 0..<Self.benchmarkSize(50_000) {
          _ = VirtualPath.lookup(handles[Self.index(i, worker: worker, count: handles.count)])
        }
      }
    }
  }

  /// A quarter of the accesses hit one hot element, like the SDK path in a build.
  private static func index(_ i: Int, worker: Int, count: Int) -> Int {
    i.isMultiple(of: 4) ? 0 : (i &* 7 &+ worker &* 131) % count
  }

  /// Debug builds only check that the benchmarks work; the measured sizes need optimized code.
  private static func benchmarkSize(_ size: Int) -> Int {
    #if DEBUG
    return size / 50
    #else
    return size
    #endif
  }

  private static func newPaths(count: Int, prefix: String) -> [String] {
    // A unique root under the working directory keeps every batch new to the process-wide cache and valid as an
    // absolute path on every platform.
    let root = localFileSystem.currentWorkingDirectory!.appending(components: "virtual-path-benchmark", UUID().uuidString, prefix)
    return (0..<count).map { root.appending(components: "dir\($0 % 100)", "file\($0).swift").pathString }
  }
}

#endif
