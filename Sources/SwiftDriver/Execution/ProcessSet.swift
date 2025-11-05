//===--------------- ProcessSet.swift - Swift Subprocesses ---------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.Condition
import class TSCBasic.Process
import struct TSCBasic.ProcessResult
import class TSCBasic.Thread
import Dispatch
import Foundation

public enum ProcessSetError: Swift.Error {
  /// The process group was cancelled and doesn't allow adding more processes.
  case cancelled
}

/// A process set is a small wrapper for collection of processes.
///
/// This class is thread safe.
// TODO: Use `TaskGroup` with async `Process` APIs instead
public final class ProcessSet {

  /// Array to hold the processes.
  private var processes: Set<Process> = []

  /// Queue to mutate internal states of the process group.
  private let serialQueue = DispatchQueue(label: "org.swift.swiftpm.process-set")

  /// If the process group was asked to cancel all active processes.
  private var cancelled = false

  /// The timeout (in seconds) after which the processes should be terminated if they don't respond to SIGINT.
  public let terminateTimeout: Double

  /// Condition to block termination thread until timeout.
  private var terminationCondition = Condition()

  /// Boolean predicate for termination condition.
  private var shouldTerminate = false

  /// Create a process set.
  public init(terminateTimeout: Double = 5) {
    self.terminateTimeout = terminateTimeout
  }

  /// Add a process to the process set. This method will throw if the process set is terminated using the terminate()
  /// method.
  ///
  /// Call remove() method to remove the process from set once it has terminated.
  ///
  /// - Parameters:
  ///   - process: The process to add.
  /// - Throws: ProcessGroupError
  public func add(_ process: TSCBasic.Process) throws {
    return try serialQueue.sync {
      guard !cancelled else {
        throw ProcessSetError.cancelled
      }
      self.processes.insert(process)
    }
  }

  /// Terminate all the processes. This method blocks until all processes in the set are terminated.
  ///
  /// A process set cannot be used once it has been asked to terminate.
  public func terminate() {
    // Mark a process set as cancelled.
    serialQueue.sync {
      cancelled = true
    }

    // Interrupt all processes.
    signalAll(SIGINT)

    // Create a thread that will terminate all processes after a timeout.
    let thread = TSCBasic.Thread {
      // Compute the timeout date.
      let timeout = Date() + self.terminateTimeout
      // Block until we timeout or notification.
      self.terminationCondition.whileLocked {
        while !self.shouldTerminate {
          // Block until timeout expires.
          let timeLimitReached = !self.terminationCondition.wait(until: timeout)
          // Set shouldTerminate to true if time limit was reached.
          if timeLimitReached {
            self.shouldTerminate = true
          }
        }
      }
      // Send terminate signal to all processes.
#if os(Windows)
      self.signalAll(SIGTERM)
#else
      self.signalAll(SIGKILL)
#endif
    }

    thread.start()

    // Wait until all processes terminate and notify the termination thread
    // if everyone exited to avoid waiting till timeout.
    for process in self.processes {
      _ = try? process.waitUntilExit()
    }
    terminationCondition.whileLocked {
      shouldTerminate = true
      terminationCondition.signal()
    }

    // Join the termination thread so we don't exit before everything terminates.
    thread.join()
  }

  /// Sends signal to all processes in the set.
  private func signalAll(_ signal: Int32) {
    serialQueue.sync {
      // Signal all active processes.
      for process in self.processes {
        process.signal(signal)
      }
    }
  }
}
