//===--------------- BitCode.swift - LLVM BitCode Helpers ----------------===//
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

import struct TSCBasic.ByteString

internal struct Bitcode {
  public let signature: Bitcode.Signature
  public let elements: [BitcodeElement]
  public let blockInfo: [UInt64:BlockInfo]
}

extension Bitcode {
  internal struct Signature: Equatable {
    private var value: UInt32

    public init(value: UInt32) {
      self.value = value
    }

    public init(string: String) {
      precondition(string.utf8.count == 4)
      var result: UInt32 = 0
      for byte in string.utf8.reversed() {
        result <<= 8
        result |= UInt32(byte)
      }
      self.value = result
    }
  }
}

extension Bitcode {
  /// Traverse a bitstream using the specified `visitor`, which will receive
  /// callbacks when blocks and records are encountered.
  internal static func read<Visitor: BitstreamVisitor>(bytes: ByteString, using visitor: inout Visitor) throws {
    precondition(bytes.count > 4)
    var reader = BitstreamReader(buffer: bytes)
    try visitor.validate(signature: reader.readSignature())
    try reader.readBlock(id: BitstreamReader.fakeTopLevelBlockID,
                         abbrevWidth: 2,
                         abbrevInfo: [],
                         visitor: &visitor)
  }
}
