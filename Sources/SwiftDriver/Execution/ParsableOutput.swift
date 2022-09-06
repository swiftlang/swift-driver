//===--------------- ParseableOutput.swift - Swift Parseable Output -------===//
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

import struct Foundation.Data
import class Foundation.JSONEncoder

@_spi(Testing) public struct ParsableMessage {
  public enum Kind {
    case began(BeganMessage)
    case finished(FinishedMessage)
    case abnormal(AbnormalExitMessage)
    case signalled(SignalledMessage)
    case skipped(SkippedMessage)
  }

  public let name: String
  public let kind: Kind

  public init(name: String, kind: Kind) {
    self.name = name
    self.kind = kind
  }

  public func toJSON() throws -> Data {
    let encoder = JSONEncoder()
    if #available(macOS 10.13, iOS 11.0, watchOS 4.0, tvOS 11.0, *) {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    } else {
      encoder.outputFormatting = [.prettyPrinted]
    }
    return try encoder.encode(self)
  }
}

@_spi(Testing) public struct ActualProcess: Encodable {
  public let realPid: Int

  public init(realPid: Int) {
    self.realPid = realPid
  }

  private enum CodingKeys: String, CodingKey {
    case realPid = "real_pid"
  }
}

@_spi(Testing) public struct BeganMessage: Encodable {
  public struct Output: Encodable {
    public let type: String
    public let path: String

    public init(path: String, type: String) {
      self.path = path
      self.type = type
    }
  }

  public let process: ActualProcess
  public let pid: Int
  public let inputs: [String]
  public let outputs: [Output]
  public let commandExecutable: String
  public let commandArguments: [String]

  public init(
    pid: Int,
    realPid: Int,
    inputs: [String],
    outputs: [Output],
    commandExecutable: String,
    commandArguments: [String]
  ) {
    self.pid = pid
    self.process = ActualProcess(realPid: realPid)
    self.inputs = inputs
    self.outputs = outputs
    self.commandExecutable = commandExecutable
    self.commandArguments = commandArguments
  }

  private enum CodingKeys: String, CodingKey {
    case pid
    case process
    case inputs
    case outputs
    case commandExecutable = "command_executable"
    case commandArguments = "command_arguments"
  }
}

@_spi(Testing) public struct SkippedMessage: Encodable {
  public let inputs: [String]

  public init( inputs: [String] ) {
    self.inputs = inputs
  }

  private enum CodingKeys: String, CodingKey {
    case inputs
  }
}

@_spi(Testing) public struct FinishedMessage: Encodable {
  let exitStatus: Int
  let pid: Int
  let process: ActualProcess
  let output: String?

  public init(
    exitStatus: Int,
    output: String?,
    pid: Int,
    realPid: Int
  ) {
    self.exitStatus = exitStatus
    self.pid = pid
    self.process = ActualProcess(realPid: realPid)
    self.output = output
  }

  private enum CodingKeys: String, CodingKey {
    case pid
    case process
    case output
    case exitStatus = "exit-status"
  }
}

@_spi(Testing) public struct AbnormalExitMessage: Encodable {
  let pid: Int
  let process: ActualProcess
  let output: String?
  let exception: UInt32

  public init(pid: Int, realPid: Int, output: String?, exception: UInt32) {
    self.pid = pid
    self.process = ActualProcess(realPid: realPid)
    self.output = output
    self.exception = exception
  }

  private enum CodingKeys: String, CodingKey {
    case pid
    case process
    case output
    case exception
  }
}

@_spi(Testing) public struct SignalledMessage: Encodable {
  let pid: Int
  let process: ActualProcess
  let output: String?
  let errorMessage: String
  let signal: Int

  public init(pid: Int, realPid: Int, output: String?, errorMessage: String, signal: Int) {
    self.pid = pid
    self.process = ActualProcess(realPid: realPid)
    self.output = output
    self.errorMessage = errorMessage
    self.signal = signal
  }

  private enum CodingKeys: String, CodingKey {
    case pid
    case process
    case output
    case errorMessage = "error-message"
    case signal
  }
}

@_spi(Testing) extension ParsableMessage: Encodable {
  enum CodingKeys: CodingKey {
    case name
    case kind
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)

    switch kind {
    case .began(let msg):
      try container.encode("began", forKey: .kind)
      try msg.encode(to: encoder)
    case .finished(let msg):
      try container.encode("finished", forKey: .kind)
      try msg.encode(to: encoder)
    case .abnormal(let msg):
      try container.encode("abnormal-exit", forKey: .kind)
      try msg.encode(to: encoder)
    case .signalled(let msg):
      try container.encode("signalled", forKey: .kind)
      try msg.encode(to: encoder)
    case .skipped(let msg):
      try container.encode("skipped", forKey: .kind)
      try msg.encode(to: encoder)

    }
  }
}
