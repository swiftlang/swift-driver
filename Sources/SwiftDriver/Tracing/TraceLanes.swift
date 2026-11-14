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

import class Foundation.NSLock

/// Assigns overlapping event spans to distinct rows ("lanes") in the viewer
///
/// The Trace Event Format requires that event spans in a row nest — a parent
/// event's bounds should contain its children's bounds entirely. Otherwise,
/// the child event should be a separate event, positioned in a separate lane.
@_spi(Testing) public final class TraceLanes: @unchecked Sendable {
  private let lock = NSLock()
  private let first: Int

  /// Available lanes, sorted highest to lowest
  private var free: [Int] = []
  private var next: Int

  public init(first: Int = 1) {
    self.first = first
    self.next = first
  }

  /// Get the identifier of the next free lane
  public func acquire() -> Int {
    lock.withLock {
      if let lane = free.popLast() {
        return lane
      }
      defer { next += 1 }
      return next
    }
  }

  /// Return `lane` to the free list
  public func release(_ lane: Int) {
    lock.withLock {
      let index = free.firstIndex(where: { $0 < lane }) ?? free.endIndex
      free.insert(lane, at: index)
    }
  }

  public var used: Range<Int> { lock.withLock { first..<next } }
}
