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

import Foundation

public struct ParsableMessage {
  public enum Kind {
    case began(BeganMessage)
    case finished(FinishedMessage)
    case signalled(SignalledMessage)
    case skipped
  }

  public let name: String
  public let kind: Kind

  public init(name: String, kind: Kind) {
    self.name = name
    self.kind = kind
  }

  public func toJSON() throws -> Data {
    let encoder = JSONEncoder()
    if #available(macOS 10.13, *) {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    } else {
      encoder.outputFormatting = [.prettyPrinted]
    }
    return try encoder.encode(self)
  }
}

public struct BeganMessage: Encodable {
  public struct Output: Encodable {
    public let type: String
    public let path: String

    public init(path: String, type: String) {
      self.path = path
      self.type = type
    }
  }

  public let pid: Int
  public let inputs: [String]
  public let outputs: [Output]
  public let commandExecutable: String
  public let commandArguments: [String]

  public init(
    pid: Int,
    inputs: [String],
    outputs: [Output],
    commandExecutable: String,
    commandArguments: [String]
  ) {
    self.pid = pid
    self.inputs = inputs
    self.outputs = outputs
    self.commandExecutable = commandExecutable
    self.commandArguments = commandArguments
  }

  private enum CodingKeys: String, CodingKey {
    case pid
    case inputs
    case outputs
    case commandExecutable = "command_executable"
    case commandArguments = "command_arguments"
  }
}

public struct FinishedMessage: Encodable {
  let exitStatus: Int
  let pid: Int
  let output: String?

  // proc-info

  public init(
    exitStatus: Int,
    pid: Int,
    output: String?
  ) {
    self.exitStatus = exitStatus
    self.pid = pid
    self.output = output
  }

  private enum CodingKeys: String, CodingKey {
    case pid
    case output
    case exitStatus = "exit-status"
  }
}

public struct SignalledMessage: Encodable {
  let pid: Int
  let output: String?
  let errorMessage: String
  let signal: Int

  public init(pid: Int, output: String?, errorMessage: String, signal: Int) {
    self.pid = pid
    self.output = output
    self.errorMessage = errorMessage
    self.signal = signal
  }

  private enum CodingKeys: String, CodingKey {
    case pid
    case output
    case errorMessage = "error-message"
    case signal
  }
}

extension ParsableMessage: Encodable {
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
    case .signalled(let msg):
      try container.encode("signalled", forKey: .kind)
      try msg.encode(to: encoder)
    case .skipped:
      break
    }
  }
}
