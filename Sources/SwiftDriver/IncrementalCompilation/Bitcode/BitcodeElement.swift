//===--------------- BitcodeElement.swift - LLVM Bitcode Elements --------===//
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

internal enum BitcodeElement {
  internal struct Block {
    public var id: UInt64
    public var elements: [BitcodeElement]
  }

  /// A record element.
  ///
  /// - Warning: A `Record` element's fields and payload only live as long as
  ///            the `visit` function that provides them is called. To persist
  ///            a record, always make a copy of it.
  internal struct Record {
    internal enum Payload {
      case none
      case array([UInt64])
      case char6String(String)
      case blob(ArraySlice<UInt8>)
    }

    public var id: UInt64
    public var fields: UnsafeBufferPointer<UInt64>
    public var payload: Payload
  }

  case block(Block)
  case record(Record)
}

extension BitcodeElement.Record.Payload: CustomStringConvertible {
  internal var description: String {
    switch self {
    case .none:
      return "none"
    case .array(let vals):
      return "array(\(vals))"
    case .char6String(let s):
      return "char6String(\(s))"
    case .blob(let s):
      return "blob(\(s.count) bytes)"
    }
  }
}
