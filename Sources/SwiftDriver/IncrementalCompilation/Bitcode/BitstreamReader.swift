//===--------------- BitstreamReader.swift - LLVM Bitstream Reader -------===//
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

private extension Bits.Cursor {
  enum BitcodeError: Swift.Error {
    case vbrOverflow
  }

  mutating func readVBR(_ width: Int) throws -> UInt64 {
    precondition(width > 1)
    let testBit = UInt64(1 << (width &- 1))
    let mask = testBit &- 1

    var result: UInt64 = 0
    var offset: UInt64 = 0
    var next: UInt64
    repeat {
      next = try self.read(width)
      result |= (next & mask) << offset
      offset += UInt64(width &- 1)
      if offset > 64 { throw BitcodeError.vbrOverflow }
    } while next & testBit != 0

    return result
  }
}

internal struct BitstreamReader {
  enum Error: Swift.Error {
    case invalidAbbrev
    case nestedBlockInBlockInfo
    case missingSETBID
    case invalidBlockInfoRecord(recordID: UInt64)
    case abbrevWidthTooSmall(width: Int)
    case noSuchAbbrev(blockID: UInt64, abbrevID: Int)
    case missingEndBlock(blockID: UInt64)
  }

  var cursor: Bits.Cursor
  var blockInfo: [UInt64: BlockInfo] = [:]
  var globalAbbrevs: [UInt64: [Bitstream.Abbreviation]] = [:]

  init(buffer: ByteString) {
    self.cursor = Bits.Cursor(buffer: buffer)
  }

  mutating func readSignature() throws -> Bitcode.Signature {
    precondition(self.cursor.isAtStart)
    let bits = try UInt32(self.cursor.read(MemoryLayout<UInt32>.size * 8))
    return Bitcode.Signature(value: bits)
  }

  mutating func readAbbrevOp() throws -> Bitstream.Abbreviation.Operand {
    let isLiteralFlag = try cursor.read(1)
    if isLiteralFlag == 1 {
      return .literal(try cursor.readVBR(8))
    }

    switch try cursor.read(3) {
    case 0:
      throw Error.invalidAbbrev
    case 1:
      return .fixed(bitWidth: UInt8(try cursor.readVBR(5)))
    case 2:
      return .vbr(chunkBitWidth: UInt8(try cursor.readVBR(5)))
    case 3:
      return .array(try readAbbrevOp())
    case 4:
      return .char6
    case 5:
      return .blob
    case 6, 7:
      throw Error.invalidAbbrev
    default:
      fatalError()
    }
  }

  mutating func readAbbrev(numOps: Int) throws -> Bitstream.Abbreviation {
    guard numOps > 0 else { throw Error.invalidAbbrev }

    var operands: [Bitstream.Abbreviation.Operand] = []
    operands.reserveCapacity(numOps)
    for i in 0..<numOps {
      operands.append(try readAbbrevOp())

      if case .array = operands.last! {
        guard i == numOps - 2 else { throw Error.invalidAbbrev }
        break
      } else if case .blob = operands.last! {
        guard i == numOps - 1 else { throw Error.invalidAbbrev }
      }
    }

    return Bitstream.Abbreviation(operands)
  }

  mutating func readSingleAbbreviatedRecordOperand(_ operand: Bitstream.Abbreviation.Operand) throws -> UInt64 {
    switch operand {
    case .char6:
      let value = try cursor.read(6)
      switch value {
      case 0...25:
        return value + UInt64(("a" as UnicodeScalar).value)
      case 26...51:
        return value + UInt64(("A" as UnicodeScalar).value) - 26
      case 52...61:
        return value + UInt64(("0" as UnicodeScalar).value) - 52
      case 62:
        return UInt64(("." as UnicodeScalar).value)
      case 63:
        return UInt64(("_" as UnicodeScalar).value)
      default:
        fatalError()
      }
    case .literal(let value):
      return value
    case .fixed(let width):
      return try cursor.read(Int(width))
    case .vbr(let width):
      return try cursor.readVBR(Int(width))
    case .array, .blob:
      fatalError()
    }
  }

  /// Computes a non-owning view of a `BitcodeElement.Record` that is valid for
  /// the lifetime of the call to `body`.
  ///
  /// - Warning: If this function throws, the `body` block will not be called.
  mutating func withAbbreviatedRecord(
    _ abbrev: Bitstream.Abbreviation,
    body: (BitcodeElement.Record) throws -> Void
  ) throws {
    let code = try readSingleAbbreviatedRecordOperand(abbrev.operands.first!)

    let lastOperand = abbrev.operands.last!
    let lastRegularOperandIndex: Int = abbrev.operands.endIndex - (lastOperand.isPayload ? 1 : 0)

    // Safety: `lastRegularOperandIndex` is always at least 1. An abbreviation
    // is required by the format to contain at least one operand. If that last
    // operand is a payload (and thus we subtracted one from the total number of
    // operands above), then that must mean it is either a trailing array
    // or trailing blob. Both of these are preceded by their length field.
    let fields = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: lastRegularOperandIndex - 1)
    defer { fields.deallocate() }

    for (idx, op) in abbrev.operands[1..<lastRegularOperandIndex].enumerated() {
      fields[idx] = try readSingleAbbreviatedRecordOperand(op)
    }

    let payload: BitcodeElement.Record.Payload
    if !lastOperand.isPayload {
      payload = .none
    } else {
      switch lastOperand {
      case .array(let element):
        let length = try cursor.readVBR(6)
        if case .char6 = element {
          // FIXME: Once the minimum deployment target bumps to macOS 11, use
          // the more ergonomic stdlib API everywhere.
          if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            payload = try .char6String(String(unsafeUninitializedCapacity: Int(length)) { buffer in
              for i in 0..<Int(length) {
                buffer[i] = try UInt8(readSingleAbbreviatedRecordOperand(element))
              }
              return Int(length)
            })
          } else {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(length))
            defer { buffer.deallocate() }
            for i in 0..<Int(length) {
              buffer[i] = try UInt8(readSingleAbbreviatedRecordOperand(element))
            }
            payload = .char6String(String(decoding: buffer, as: UTF8.self))
          }
        } else {
          var elements = [UInt64]()
          for _ in 0..<length {
            elements.append(try readSingleAbbreviatedRecordOperand(element))
          }
          payload = .array(elements)
        }
      case .blob:
        let length = Int(try cursor.readVBR(6))
        try cursor.advance(toBitAlignment: 32)
        payload = .blob(try cursor.read(bytes: length))
        try cursor.advance(toBitAlignment: 32)
      default:
        fatalError()
      }
    }

    return try body(.init(id: code, fields: UnsafeBufferPointer(fields), payload: payload))
  }

  mutating func readBlockInfoBlock(abbrevWidth: Int) throws {
    var currentBlockID: UInt64?
    while true {
      switch try cursor.read(abbrevWidth) {
      case Bitstream.AbbreviationID.endBlock.rawValue:
        try cursor.advance(toBitAlignment: 32)
        // FIXME: check expected length
        return

      case Bitstream.AbbreviationID.enterSubblock.rawValue:
        throw Error.nestedBlockInBlockInfo

      case Bitstream.AbbreviationID.defineAbbreviation.rawValue:
        guard let blockID = currentBlockID else {
          throw Error.missingSETBID
        }
        let numOps = Int(try cursor.readVBR(5))
        if globalAbbrevs[blockID] == nil { globalAbbrevs[blockID] = [] }
        globalAbbrevs[blockID]!.append(try readAbbrev(numOps: numOps))

      case Bitstream.AbbreviationID.unabbreviatedRecord.rawValue:
        let code = try cursor.readVBR(6)
        let numOps = try cursor.readVBR(6)
        var operands = [UInt64]()
        for _ in 0..<numOps {
          operands.append(try cursor.readVBR(6))
        }

        switch code {
        case UInt64(Bitstream.BlockInfoCode.setBID.rawValue):
          guard operands.count == 1 else { throw Error.invalidBlockInfoRecord(recordID: code) }
          currentBlockID = operands.first
        case UInt64(Bitstream.BlockInfoCode.blockName.rawValue):
          guard let blockID = currentBlockID else {
            throw Error.missingSETBID
          }
          if blockInfo[blockID] == nil { blockInfo[blockID] = BlockInfo() }
          blockInfo[blockID]!.name = String(bytes: operands.map { UInt8($0) }, encoding: .utf8) ?? "<invalid>"
        case UInt64(Bitstream.BlockInfoCode.setRecordName.rawValue):
          guard let blockID = currentBlockID else {
            throw Error.missingSETBID
          }
          if blockInfo[blockID] == nil { blockInfo[blockID] = BlockInfo() }
          guard let recordID = operands.first else {
            throw Error.invalidBlockInfoRecord(recordID: code)
          }
          blockInfo[blockID]!.recordNames[recordID] = String(bytes: operands.dropFirst().map { UInt8($0) }, encoding: .utf8) ?? "<invalid>"
        default:
          throw Error.invalidBlockInfoRecord(recordID: code)
        }

      case let abbrevID:
        throw Error.noSuchAbbrev(blockID: 0, abbrevID: Int(abbrevID))
      }
    }
  }

  mutating func readBlock<Visitor: BitstreamVisitor>(id: UInt64, abbrevWidth: Int, abbrevInfo: [Bitstream.Abbreviation], visitor: inout Visitor) throws {
    var abbrevInfo = abbrevInfo

    while !cursor.isAtEnd {
      switch try cursor.read(abbrevWidth) {
      case Bitstream.AbbreviationID.endBlock.rawValue:
        try cursor.advance(toBitAlignment: 32)
        // FIXME: check expected length
        try visitor.didExitBlock()
        return

      case Bitstream.AbbreviationID.enterSubblock.rawValue:
        let blockID = try cursor.readVBR(8)
        let newAbbrevWidth = Int(try cursor.readVBR(4))
        try cursor.advance(toBitAlignment: 32)
        let blockLength = try cursor.read(32) * 4

        switch blockID {
        case 0:
          try readBlockInfoBlock(abbrevWidth: newAbbrevWidth)
        case 1...7:
          // Metadata blocks we don't understand yet
          fallthrough
        default:
          guard try visitor.shouldEnterBlock(id: blockID) else {
            try cursor.skip(bytes: Int(blockLength))
            break
          }
          try readBlock(
            id: blockID, abbrevWidth: newAbbrevWidth,
            abbrevInfo: globalAbbrevs[blockID] ?? [], visitor: &visitor)
        }

      case Bitstream.AbbreviationID.defineAbbreviation.rawValue:
        let numOps = Int(try cursor.readVBR(5))
        abbrevInfo.append(try readAbbrev(numOps: numOps))

      case Bitstream.AbbreviationID.unabbreviatedRecord.rawValue:
        let code = try cursor.readVBR(6)
        let numOps = try cursor.readVBR(6)
        let operands = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: Int(numOps))
        defer { operands.deallocate() }
        for i in 0..<Int(numOps) {
          operands[i] = try cursor.readVBR(6)
        }
        try visitor.visit(record: .init(id: code, fields: UnsafeBufferPointer(operands), payload: .none))

      case let abbrevID:
        guard Int(abbrevID) - 4 < abbrevInfo.count else {
          throw Error.noSuchAbbrev(blockID: id, abbrevID: Int(abbrevID))
        }
        try withAbbreviatedRecord(abbrevInfo[Int(abbrevID) - 4]) { record in
          try visitor.visit(record: record)
        }
      }
    }

    guard id == Self.fakeTopLevelBlockID else {
      throw Error.missingEndBlock(blockID: id)
    }
  }

  static let fakeTopLevelBlockID: UInt64 = ~0
}
