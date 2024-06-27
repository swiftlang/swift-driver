//===--------------- Bitstream.swift - LLVM Bitstream routines -----------===//
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

/// A top-level namespace for all bitstream-related structures.
internal enum Bitstream {}

extension Bitstream {
  /// An `Abbreviation` represents the encoding definition for a user-defined
  /// record. An `Abbreviation` is the primary form of compression available in
  /// a bitstream file.
  internal struct Abbreviation {
    internal enum Operand {
      /// A literal value (emitted as a VBR8 field).
      case literal(UInt64)

      /// A fixed-width field.
      case fixed(bitWidth: UInt8)

      /// A VBR-encoded value with the provided chunk width.
      case vbr(chunkBitWidth: UInt8)

      /// An array of values. This expects another operand encoded
      /// directly after indicating the element type.
      /// The array will begin with a vbr6 value indicating the length of
      /// the following array.
      indirect case array(Operand)

      /// A char6-encoded ASCII character.
      case char6

      /// Emitted as a vbr6 value, padded to a 32-bit boundary and then
      /// an array of 8-bit objects.
      case blob

      var isPayload: Bool {
        switch self {
        case .array, .blob: return true
        case .literal, .fixed, .vbr, .char6: return false
        }
      }

      /// Whether this case is the `literal` case.
      var isLiteral: Bool {
        if case .literal = self { return true }
        return false
      }

      /// The llvm::BitCodeAbbrevOp::Encoding value this
      /// enum case represents.
      /// - note: Must match the encoding in
      ///         http://llvm.org/docs/BitCodeFormat.html#define-abbrev-encoding
      var encodedKind: UInt8 {
        switch self {
        case .literal(_): return 0
        case .fixed(_): return 1
        case .vbr(_): return 2
        case .array: return 3
        case .char6: return 4
        case .blob: return 5
        }
      }
    }

    public var operands: [Operand] = []

    public init(_ operands: [Operand]) {
      self.operands = operands
    }
  }
}

extension Bitstream {
  /// An `AbbreviationID` is a fixed-width field that occurs at the start of
  /// abbreviated data records and inside block definitions.
  ///
  /// Bitstream reserves 4 special abbreviation IDs for its own bookkeeping.
  /// User defined IDs are expected to start at
  /// `Bitstream.AbbreviationID.firstApplicationID`.
  ///
  /// - Warning: Creating your own abbreviations by hand is not recommended as
  ///            you could potentially corrupt or collide with another
  ///            abbreviation defined by `BitstreamWriter`. Always use
  ///            `BitstreamWriter.defineBlockInfoAbbreviation(_:_:)`
  ///            to register abbreviations.
  internal struct AbbreviationID: RawRepresentable, Equatable, Hashable, Comparable, Identifiable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
      self.rawValue = rawValue
    }

    /// Marks the end of the current block.
    public static let endBlock = Self(rawValue: 0)
    /// Marks the beginning of a new block.
    public static let enterSubblock = Self(rawValue: 1)
    /// Marks the definition of a new abbreviation.
    public static let defineAbbreviation = Self(rawValue: 2)
    /// Marks the definition of a new unabbreviated record.
    public static let unabbreviatedRecord = Self(rawValue: 3)
    /// The first application-defined abbreviation ID.
    public static let firstApplicationID = Self(rawValue: 4)

    public var id: UInt64 {
      self.rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
}

extension Bitstream {
  /// A `BlockID` is a fixed-width field that occurs at the start of all blocks.
  ///
  /// Bistream reserves the first 7 block IDs for its own bookkeeping. User
  /// defined IDs are expected to start at
  /// `Bitstream.BlockID.firstApplicationID`.
  ///
  /// When defining new block IDs, it may be helpful to refer to them by
  /// a user-defined literal. For example, the `dia` serialized diagnostics
  /// format used by Clang would define constants for block IDs as follows:
  ///
  /// ```
  /// extension Bitstream.BlockID {
  ///     static let metadata     = Self.firstApplicationID
  ///     static let diagnostics  = Self.firstApplicationID + 1
  /// }
  /// ```
  internal struct BlockID: RawRepresentable, Equatable, Hashable, Comparable, Identifiable {
    public var rawValue: UInt8

    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    public static let blockInfo = Self(rawValue: 0)
    public static let firstApplicationID = Self(rawValue: 8)

    public var id: UInt8 {
      self.rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.rawValue < rhs.rawValue
    }

    public static func + (lhs: Self, rhs: UInt8) -> Self {
      return BlockID(rawValue: lhs.rawValue + rhs)
    }
  }
}

extension Bitstream {
    /// A `BlockInfoCode` enumerates the bits that occur in the metadata for
    /// a block or record. Of these bits, only `setBID` is required. If
    /// a name is given to a block or record with `blockName` or
    /// `setRecordName`, debugging tools like `llvm-bcanalyzer` can be used to
    /// introspect the structure of blocks and records in the bitstream file.
    internal enum BlockInfoCode: UInt8 {
        /// Indicates which block ID is being described.
        case setBID = 1
        /// An optional element that records which bytes of the record are the
        /// name of the block.
        case blockName = 2
        /// An optional element that records the record ID number and the bytes
        /// for the name of the corresponding record.
        case setRecordName = 3
    }
}
