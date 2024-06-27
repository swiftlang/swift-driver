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

import class TSCBasic.Process
import struct TSCBasic.ProcessResult

import class Foundation.FileHandle
import struct Foundation.Data

/// Abstraction for functionality that allows working with subprocesses.
public protocol ProcessProtocol {
  /// The PID of the process.
  ///
  /// Clients that don't really launch a process can return
  /// a negative number to represent a "quasi-pid".
  ///
  /// - SeeAlso: https://github.com/apple/swift/blob/main/docs/DriverParseableOutput.rst#quasi-pids
  var processID: TSCBasic.Process.ProcessID { get }

  /// Wait for the process to finish execution.
  @discardableResult
  func waitUntilExit() throws -> ProcessResult

  static func launchProcess(
    arguments: [String],
    env: [String: String]
  ) throws -> Self

  static func launchProcessAndWriteInput(
    arguments: [String],
    env: [String: String],
    inputFileHandle: FileHandle
  ) throws -> Self
}

extension TSCBasic.Process: ProcessProtocol {
  public static func launchProcess(
    arguments: [String],
    env: [String: String]
  ) throws -> TSCBasic.Process {
    let process = Process(arguments: arguments, environment: env)
    try process.launch()
    return process
  }

  public static func launchProcessAndWriteInput(
    arguments: [String],
    env: [String: String],
    inputFileHandle: FileHandle
  ) throws -> TSCBasic.Process {
    let process = Process(arguments: arguments, environment: env)
    let processInputStream = try process.launch()
    var input: Data
    // Write out the contents of the input handle and close the input stream
    repeat {
      input = inputFileHandle.availableData
      processInputStream.write(input)
    } while (input.count > 0)
    processInputStream.flush()
    try processInputStream.close()
    return process
  }
}
