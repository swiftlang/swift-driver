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

import class Foundation.ProcessInfo

@_spi(Testing) public struct TraceEvent: Codable, Equatable, Sendable {
  public enum Phase: String, Codable, Sendable {
    /// A span of time with a beginning and duration
    case complete = "X"
    case instant = "i"
    case metadata = "M"
  }

  public enum Argument: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)

    public func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .string(let s): try container.encode(s)
      case .int(let i): try container.encode(i)
      }
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let i = try? container.decode(Int.self) {
        self = .int(i)
      } else {
        self = .string(try container.decode(String.self))
      }
    }
  }

  public var name: String
  public var category: String
  public var phase: Phase

  /// When the event happened in microseconds from TraceClock
  public var timestamp: Int64

  /// Length of event in microseconds of uptime
  public var duration: Int64?

  public var processID: Int32

  public var threadID: Int

  public var arguments: [String: Argument]?

  public init(
    name: String, category: String, phase: Phase, timestamp: Int64,
    duration: Int64? = nil, processID: Int32 = TraceEvent.currentProcessID,
    threadID: Int, arguments: [String: Argument]? = nil
  ) {
    self.name = name
    self.category = category
    self.phase = phase
    self.timestamp = timestamp
    self.duration = duration
    self.processID = processID
    self.threadID = threadID
    self.arguments = arguments
  }

  enum CodingKeys: String, CodingKey {
    case name
    case category = "cat"
    case phase = "ph"
    case timestamp = "ts"
    case duration = "dur"
    case processID = "pid"
    case threadID = "tid"
    case arguments = "args"
  }

  public static var currentProcessID: Int32 { ProcessInfo.processInfo.processIdentifier }
}

// Event creation conveniences
extension TraceEvent {
  public static func processName(
    _ name: String, processID: Int32 = TraceEvent.currentProcessID
  ) -> TraceEvent {
    metadata("process_name", processID: processID, threadID: 0, ["name": .string(name)])
  }

  public static func threadName(
    _ name: String, threadID: Int, processID: Int32 = TraceEvent.currentProcessID
  ) -> TraceEvent {
    metadata("thread_name", processID: processID, threadID: threadID, ["name": .string(name)])
  }

  public static func threadSortIndex(
    _ index: Int, threadID: Int, processID: Int32 = TraceEvent.currentProcessID
  ) -> TraceEvent {
    metadata("thread_sort_index", processID: processID, threadID: threadID, ["sort_index": .int(index)])
  }

  private static func metadata(
    _ name: String, processID: Int32, threadID: Int, _ arguments: [String: Argument]
  ) -> TraceEvent {
    TraceEvent(name: name, category: "", phase: .metadata, timestamp: 0,
               processID: processID, threadID: threadID, arguments: arguments)
  }
}
