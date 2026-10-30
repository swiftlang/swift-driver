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

import Foundation
@_spi(Testing) import SwiftDriver
import Testing

import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem

@Suite struct VirtualPathTests {
  /// The path cache is shared by every driver in a process, so build systems that plan many modules
  /// concurrently intern paths from many threads at once. Every thread must observe the same handle
  /// for a path, whichever spelling or entry point interns it first.
  @Test func concurrentInterningVendsOneHandlePerPath() throws {
    for _ in 0..<20 {
      try checkConcurrentInterning(pathCount: 200, workerCount: 16)
    }
  }

  private func checkConcurrentInterning(pathCount: Int, workerCount: Int) throws {
    // Rooting the paths in the working directory makes them valid absolute paths on every platform (Windows
    // needs a drive letter). A unique subdirectory keeps them out of the cache that other tests populate.
    let root = try #require(localFileSystem.currentWorkingDirectory)
      .appending(components: "virtual-path-tests", UUID().uuidString)
    let canonical = (0..<pathCount).map { root.appending(components: "dir\($0 % 10)", "file\($0).swift").pathString }
    #if os(Windows)
    // Path validation on Windows may not collapse "." components, so don't rely on an alias spelling there.
    let nonCanonical = canonical
    #else
    let nonCanonical = (0..<pathCount).map { "\(root.pathString)/./dir\($0 % 10)/file\($0).swift" }
    #endif

    let lock = NSLock()
    var handlesPerWorker: [[VirtualPath.Handle]] = []
    var errors: [String] = []

    DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
      // Slots: [0, n) canonical string, [n, 2n) non-canonical string, [2n, 3n) VirtualPath value.
      var handles = [VirtualPath.Handle](repeating: .standardInput, count: 3 * pathCount)
      var current = ""
      do {
        for offset in 0..<pathCount {
          // Half of the workers walk forward and half backward, so that several workers insert the
          // same new path at the same time, through different entry points.
          let i = worker.isMultiple(of: 2) ? offset : pathCount - 1 - offset
          current = canonical[i]
          switch worker % 3 {
          case 0:
            handles[i] = try VirtualPath.intern(path: canonical[i])
            handles[pathCount + i] = try VirtualPath.intern(path: nonCanonical[i])
            handles[2 * pathCount + i] = VirtualPath.absolute(try AbsolutePath(validating: canonical[i])).intern()
          case 1:
            handles[pathCount + i] = try VirtualPath.intern(path: nonCanonical[i])
            handles[2 * pathCount + i] = VirtualPath.absolute(try AbsolutePath(validating: canonical[i])).intern()
            handles[i] = try VirtualPath.intern(path: canonical[i])
          default:
            handles[2 * pathCount + i] = VirtualPath.absolute(try AbsolutePath(validating: canonical[i])).intern()
            handles[i] = try VirtualPath.intern(path: canonical[i])
            handles[pathCount + i] = try VirtualPath.intern(path: nonCanonical[i])
          }
          _ = VirtualPath.lookup(handles[i])
        }
        lock.lock()
        handlesPerWorker.append(handles)
        lock.unlock()
      } catch {
        lock.lock()
        errors.append("worker \(worker), path \(current): \(error)")
        lock.unlock()
      }
    }

    #expect(errors.isEmpty, "Unexpected errors: \(errors)")
    #expect(handlesPerWorker.count == workerCount)
    let expected = try #require(handlesPerWorker.first)
    for handles in handlesPerWorker {
      #expect(handles == expected)
    }
    for i in 0..<pathCount {
      #expect(expected[pathCount + i] == expected[i], "Spelling \(nonCanonical[i]) got its own handle")
      #expect(expected[2 * pathCount + i] == expected[i], "VirtualPath for \(canonical[i]) got its own handle")
      #expect(VirtualPath.lookup(expected[i]) == .absolute(try AbsolutePath(validating: canonical[i])))
    }
    #expect(Set(expected[0..<pathCount]).count == pathCount, "Distinct paths share a handle")
  }
}
