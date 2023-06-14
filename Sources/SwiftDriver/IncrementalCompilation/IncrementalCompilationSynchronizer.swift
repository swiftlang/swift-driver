//===---------------IncrementalCompilationSynchronizer.swift --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch

/// Any instance that can find the confinmentQueue for the incremental compilation state.
/// By confirming, a type gains the use of the shorthand methods in the extension.
public protocol IncrementalCompilationSynchronizer {
  var incrementalCompilationQueue: DispatchQueue {get}
}

extension IncrementalCompilationSynchronizer {
  func mutationSafetyPrecondition() {
    incrementalCompilationQueue.mutationSafetyPrecondition()
  }
  func accessSafetyPrecondition() {
    incrementalCompilationQueue.accessSafetyPrecondition()
  }

  @_spi(Testing) public func blockingConcurrentAccessOrMutation<T>( _ fn: () throws -> T ) rethrows -> T {
    try incrementalCompilationQueue.blockingConcurrentAccessOrMutation(fn)
  }
  @_spi(Testing) public func blockingConcurrentMutation<T>( _ fn: () throws -> T ) rethrows -> T {
    try incrementalCompilationQueue.blockingConcurrentMutation(fn)
  }
}

/// Methods to bridge the semantic gap from intention to implementation.
extension DispatchQueue {
  /// Ensure that it is safe to mutate or access the state protected by the queue.
  fileprivate func mutationSafetyPrecondition() {
    dispatchPrecondition(condition: .onQueueAsBarrier(self))
  }
  /// Ensure that it is safe to access the state protected by the queue.
  fileprivate func accessSafetyPrecondition() {
    dispatchPrecondition(condition: .onQueue(self))
  }

  /// Block any concurrent access or muitation so that the argument may access or mutate the protected state.
  @_spi(Testing) public func blockingConcurrentAccessOrMutation<T>( _ fn: () throws -> T ) rethrows -> T {
    try sync(flags: .barrier, execute: fn)
  }
  /// Block any concurrent mutation so that argument may access (but not mutate) the protected state.
  @_spi(Testing) public func blockingConcurrentMutation<T>( _ fn: () throws -> T ) rethrows -> T {
    try sync(execute: fn)
  }
}

/// A fixture for tests and dot file creation, etc., that require synchronization and  an ``InternedStringTable``
public struct MockIncrementalCompilationSynchronizer: IncrementalCompilationSynchronizer {
  public let incrementalCompilationQueue: DispatchQueue

  init() {
    self.incrementalCompilationQueue = DispatchQueue(label: "testing")
  }

  func withInternedStringTable<R>(_ fn: (InternedStringTable) throws -> R) rethrows -> R {
    try blockingConcurrentAccessOrMutation {
      try fn(InternedStringTable(incrementalCompilationQueue))
    }
  }

  public static func withInternedStringTable<R>(_ fn: (InternedStringTable) throws -> R) rethrows -> R {
    try Self().withInternedStringTable(fn)
  }
}
