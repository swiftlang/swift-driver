//===--------------- ProessProtocol.swift - Swift Subprocesses ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic

/// Abstraction for functionality that allows working with subprocesses.
public protocol ProcessProtocol {
  /// The PID of the process.
  ///
  /// Clients that don't really launch a process can return
  /// a negative number to represent a "quasi-pid".
  ///
  /// - SeeAlso: https://github.com/apple/swift/blob/master/docs/DriverParseableOutput.rst#quasi-pids
  var processID: Process.ProcessID { get }

  /// Wait for the process to finish execution.
  @discardableResult
  func waitUntilExit() throws -> ProcessResult
}

extension Process: ProcessProtocol {
  public static func launchProcess(
    arguments: [String]
  ) throws -> ProcessProtocol {
    let process = Process(arguments: arguments)
    try process.launch()
    return process
  }
}
