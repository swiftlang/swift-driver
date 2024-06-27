//===----------- BistreamWriter.swift - LLVM Bitstream Writer -------------===//
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

/// A `BitstreamWriter` is an object that is capable of emitting data in the
/// [LLVM Bitstream](https://llvm.org/docs/BitCodeFormat.html#bitstream-format)
/// format.
///
/// Defining A Container Format
/// ===========================
///
/// While `BitstreamWriter` provides APIs to write raw bytes into a bitstream
/// file, it is recommended that the higher-level structured API be used
/// instead. Begin by identifying the top-level blocks your container will need.
/// Most container formats will need a metadata block followed by a series of
/// user-defined blocks. These can be given in an extension of
/// `Bitstream.BlockID` as they will be referred to often. For example:
///
/// ```
/// extension Bitstream.BlockID {
///     static let metadata     = Self.firstApplicationID
///     static let diagnostics  = Self.firstApplicationID + 1
/// }
/// ```
///
/// Next, identify the kinds of records needed in the format and assign them
/// unique, stable identifiers. For example:
///
/// ```
/// enum DiagnosticRecordID: UInt8 {
///     case version        = 1
///     case diagnostic     = 2
///     case sourceRange    = 3
///     case diagnosticFlag = 4
///     case category       = 5
///     case filename       = 6
///     case fixIt          = 7
/// }
/// ```
///
/// Now, instantiate a `BitstreamWriter` and populate the leading "block info"
/// block with records describing the data layout of sub-blocks and records. The following
/// block info section describes the layout of the 'metadata' block which contains a single
/// version record:
///
/// ```
/// var versionAbbrev: Bitstream.AbbreviationID? = nil
/// let recordWriter = BitstreamWriter()
/// recordWriter.writeBlockInfoBlock {
///     // Define the 'metadata' block and give it a name
///     recordWriter.writeRecord(BitstreamWriter.BlockInfoCode.setBID) {
///         $0.append(Bitstream.BlockID.metadata)
///     }
///     recordWriter.writeRecord(BitstreamWriter.BlockInfoCode.blockName) {
///         $0.append("Meta")
///     }
///
///     // Define the 'version' record and register its name
///     recordWriter.writeRecord(BitstreamWriter.BlockInfoCode.setRecordName) {
///         $0.append(DiagnosticRecordID.version)
///         $0.append("Version")
///     }
///
///     versionAbbrev = recordWriter.defineBlockInfoAbbreviation(.metadata, .init([
///         .literalCode(DiagnosticRecordID.version),
///         .fixed(bitWidth: 32)
///     ]))
///
///     // Emit a block ID for the 'diagnostics' block as above and define the
///     // layout of its records similarly...
/// }
/// ```
///
/// Finally, write any blocks containing the actual data to be serialized.
///
/// ```
/// recordWriter.writeBlock(.metadata, newAbbrevWidth: 3) {
///     recordWriter.writeRecord(versionAbbrev!) {
///         $0.append(DiagnosticRecordID.version)
///         $0.append(25 as UInt32)
///     }
/// }
/// ```
///
/// The higher-level APIs will automatically ensure that `BitstreamWriter.data`
/// is valid. Once serialization has completed, simply emit this data to a file.
internal final class BitstreamWriter {
    /// The buffer of data being written to.
    private(set) public var data: [UInt8]

    /// The current value. Only bits < currentBit are valid.
    private var currentValue: UInt32 = 0

    /// Always between 0 and 31 inclusive, specifies the next bit to use.
    private var currentBit: UInt8 = 0

    /// The bit width used for abbreviated codes.
    private var codeBitWidth: UInt8

    /// The list of defined abbreviations.
    private var currentAbbreviations = [Bitstream.Abbreviation]()

    /// Represents an in-flight block currently being emitted.
    struct Block {
        /// The code width before we started emitting this block.
        let previousCodeWidth: UInt8

        /// The index into the data buffer where this block's length placeholder
        /// lives.
        let lengthPlaceholderByteIndex: Int

        /// The previous set of abbreviations registered.
        let previousAbbrevs: [Bitstream.Abbreviation]
    }

    /// This keeps track of the blocks that are being emitted.
    private var blockScope = [Block]()

    /// This contains information emitted to BLOCKINFO_BLOCK blocks.
    /// These describe abbreviations that all blocks of the specified ID inherit.
    final class BlockInfo {
        var abbrevs = [Bitstream.Abbreviation]()
    }
    /// This maps BlockInfo IDs to their corresponding values.
    private var blockInfoRecords = [UInt8: BlockInfo]()

    /// When emitting blockinfo, this is the ID of the current block being
    /// emitted.
    private var currentBlockID: Bitstream.BlockID?

    /// Creates a new BitstreamWriter with the provided data stream.
    public init(data: [UInt8] = []) {
        self.data = data
        self.codeBitWidth = 2
    }


    public var bufferOffset: Int {
        return data.count
    }

    /// \brief Retrieve the current position in the stream, in bits.
    public var bitNumber: Int {
        return bufferOffset * 8 + Int(currentBit)
    }

    public var isEmpty: Bool {
        return self.data.isEmpty
    }
}

// MARK: Data Writing Primitives

extension BitstreamWriter {
    /// Writes the provided UInt32 to the data stream directly.
    internal func write(_ int: UInt32) {
        let index = data.count

        // Add 4 bytes of zeroes to be overwritten.
        data.append(0)
        data.append(0)
        data.append(0)
        data.append(0)

        overwriteBytes(int, byteIndex: index)
    }

    /// Writes the provided number of bits to the buffer.
    ///
    /// - Parameters:
    ///   - int: The integer containing the bits you'd like to write
    ///   - width: The number of low-bits of the integer you're writing to the
    ///            buffer
    internal func writeVBR<IntType>(_ int: IntType, width: UInt8)
        where IntType: UnsignedInteger & ExpressibleByIntegerLiteral
    {
        let threshold = UInt64(1) << (UInt64(width) - 1)
        var value = UInt64(int)

        // Emit the bits with VBR encoding, (width - 1) bits at a time.
        while value >= threshold {
            let masked = (value & (threshold - 1)) | threshold
            write(masked, width: width)
            value >>= width - 1
        }

        write(value, width: width)
    }

    /// Writes the provided number of bits to the buffer.
    ///
    /// - Parameters:
    ///   - int: The integer containing the bits you'd like to write
    ///   - width: The number of low-bits of the integer you're writing to the
    ///            buffer
    internal func write<IntType>(_ int: IntType, width: UInt8)
        where IntType: UnsignedInteger & ExpressibleByIntegerLiteral
    {
        precondition(width > 0, "cannot emit 0 bits")
        precondition(width <= 32, "can only write at most 32 bits")

        let intPattern = UInt32(int)

        precondition(intPattern & ~(~(0 as UInt32) >> (32 - width)) == 0,
                     "High bits set!")

        // Mask the bits of the argument over the current bit we're tracking
        let intMask = intPattern << currentBit
        currentValue |= intMask

        // If we haven't spilled past the temp buffer, just update the
        // current bit.
        if currentBit + width < 32 {
            currentBit += width
            return
        }

        // Otherwise, write the current value.
        write(currentValue)

        if currentBit > 0 {
            // If we still have bits leftover, replace the current buffer with
            // the low bits of the input, offset by the current bit.
            // For example, when we're adding:
            // 0b00000000_00000000_00000000_00000011
            // to
            // 0b01111111_11111111_11111111_11111111
            //    ^ currentBit (31)
            // We've already taken 1 bit off the end of the first number,
            // leaving an extra 1 bit that needs to be represented for the next
            // write.
            // Subtract the currentBit from 32 to get the number of bits
            // leftover and then shift to get rid of the already-recorded bits.
            currentValue = UInt32(int) >> (32 - UInt32(currentBit))
        } else {
            // Otherwise, reset our buffer.
            currentValue = 0
        }
        currentBit = (currentBit + width) & 31
    }

    internal func alignIfNeeded() {
        guard currentBit > 0 else { return }
        write(currentValue)
        assert(bufferOffset % 4 == 0, "buffer must be 32-bit aligned")
        currentValue = 0
        currentBit = 0
    }

    /// Writes a Bool as a 1-bit integer value.
    internal func write(_ bool: Bool) {
        write(bool ? 1 as UInt : 0, width: 1)
    }

    /// Writes the provided BitCode Abbrev operand to the stream.
    internal func write(_ abbrevOp: Bitstream.Abbreviation.Operand) {
        write(abbrevOp.isLiteral) // the Literal bit.
        switch abbrevOp {
        case .literal(let value):
            // Literal values are 1 (for the Literal bit) and then a vbr8
            // encoded literal.
            writeVBR(value, width: 8)
        case .fixed(let bitWidth):
            // Fixed values are the encoding kind then the bitWidth as a vbr5
            // value.
            write(abbrevOp.encodedKind, width: 3)
            writeVBR(bitWidth, width: 5)
        case .vbr(let chunkBitWidth):
            // VBR values are the encoding kind then the chunk width as a
            // vbr5 value.
            write(abbrevOp.encodedKind, width: 3)
            writeVBR(chunkBitWidth, width: 5)
        case .array(let eltOp):
            // Arrays are encoded as the Array kind, then the element type
            // directly after.
            write(abbrevOp.encodedKind, width: 3)
            write(eltOp)
        case .char6, .blob:
            // Blobs and Char6 are just their encoding kind.
            write(abbrevOp.encodedKind, width: 3)
        }
    }

    /// Writes the specified abbreviaion value to the stream, as a 32-bit quantity.
    internal func writeCode(_ code: Bitstream.AbbreviationID) {
        writeCode(code.rawValue)
    }

    /// Writes the specified Code value to the stream, as a 32-bit quantity.
    internal func writeCode<IntType>(_ code: IntType)
        where IntType: UnsignedInteger & ExpressibleByIntegerLiteral
    {
        write(code, width: codeBitWidth)
    }

    /// Writes an ASCII character to the stream, as an 8-bit ascii value.
    internal func writeASCII(_ character: Character) {
        precondition(character.unicodeScalars.count == 1, "character is not ASCII")
        let c = UInt8(ascii: character.unicodeScalars.first!)
        write(c, width: 8)
    }
}

// MARK: Abbreviations

extension BitstreamWriter {
    /// Defines an abbreviation and returns the unique identifier for that
    /// abbreviation.
    internal func defineAbbreviation(_ abbrev: Bitstream.Abbreviation) -> Bitstream.AbbreviationID {
        encodeAbbreviation(abbrev)
        currentAbbreviations.append(abbrev)
        let rawValue = UInt64(currentAbbreviations.count - 1) +
                                Bitstream.AbbreviationID.firstApplicationID.rawValue
        return Bitstream.AbbreviationID(rawValue: rawValue)
    }

    /// Encodes the definition of an abbreviation to the stream.
    private func encodeAbbreviation(_ abbrev: Bitstream.Abbreviation) {
        writeCode(.defineAbbreviation)
        writeVBR(UInt(abbrev.operands.count), width: 5)
        for op in abbrev.operands {
            write(op)
        }
    }
}

// MARK: Writing Records

extension BitstreamWriter {
    internal struct RecordBuffer {
        private(set) var values = [UInt32]()

        fileprivate init() {
            self.values = []
            self.values.reserveCapacity(8)
        }

        fileprivate init<CodeType>(recordID: CodeType)
            where CodeType: RawRepresentable, CodeType.RawValue: UnsignedInteger & ExpressibleByIntegerLiteral
        {
            self.values = [ UInt32(recordID.rawValue) ]
        }

        fileprivate init(block: Bitstream.BlockID) {
            self.values = [ UInt32(block.rawValue) ]
        }

        fileprivate init(abbreviation: Bitstream.AbbreviationID) {
            self.values = [ UInt32(abbreviation.rawValue) ]
        }

        public mutating func append<CodeType>(_ code: CodeType)
            where CodeType: RawRepresentable, CodeType.RawValue: UnsignedInteger & ExpressibleByIntegerLiteral
        {
            values.append(UInt32(code.rawValue))
        }

        public mutating func append<IntType>(_ int: IntType)
            where IntType: UnsignedInteger & ExpressibleByIntegerLiteral
        {
            values.append(UInt32(int))
        }

        public mutating func append(_ string: String) {
            self.values.reserveCapacity(self.values.capacity + string.utf8.count)
            for byte in string.utf8 {
                values.append(UInt32(byte))
            }
        }
    }

    /// Writes an unabbreviated record to the stream.
    internal func writeRecord<CodeType>(_ code: CodeType, _ composeRecord: (inout RecordBuffer) -> Void)
        where CodeType: RawRepresentable, CodeType.RawValue == UInt8
    {
        writeCode(.unabbreviatedRecord)
        writeVBR(code.rawValue, width: 6)
        var record = RecordBuffer()
        composeRecord(&record)
        writeVBR(UInt(record.values.count), width: 6)
        for value in record.values {
            writeVBR(value, width: 6)
        }
    }

    /// Writes a record with the provided abbreviation ID and record contents.
    /// Optionally, emits the provided blob if the abbreviation referenced
    /// by that ID requires it.
    internal func writeRecord(
        _ abbrevID: Bitstream.AbbreviationID,
        _ composeRecord: (inout RecordBuffer) -> Void,
        blob: String? = nil
    ) {
        let index = Bitstream.AbbreviationID.firstApplicationID.rawValue.distance(to: abbrevID.rawValue)
        guard index < currentAbbreviations.count else {
            fatalError("unregistered abbreviation \(index)")
        }

        let abbrev = currentAbbreviations[Int(index)]
        var record = RecordBuffer()
        composeRecord(&record)
        let values = record.values
        var valueIndex = 0
        writeCode(abbrevID)
        for op in abbrev.operands {
            switch op {
            case .array(let eltOp):
                // First, emit the length as a VBR6
                let length = UInt(values.count - valueIndex)
                writeVBR(length, width: 6)

                // Emit the remaining values using that encoding.
                for idx in valueIndex..<values.count {
                    writeAbbrevField(eltOp, value: values[idx])
                }
            case .blob:
                guard let blob = blob else { fatalError("expected blob") }
                // Blobs are encoded as a VBR6 length, then a sequence of
                // 8-bit values.
                let length = UInt(blob.utf8.count)
                writeVBR(length, width: 6)
                alignIfNeeded()

                for char in blob.utf8 {
                    write(char, width: 8)
                }

                // Ensure total length of the blob is a multiple of 4 by
                // writing zeroes.
                alignIfNeeded()
            default:
                // Otherwise, write this value using its encoding directly and
                // increment the value index.
                writeAbbrevField(op, value: values[valueIndex])
                valueIndex += 1
            }
        }
    }
}

// MARK: Writing Data

extension BitstreamWriter {
    /// Char6 is encoded using a special encoding that uses 0 to 64 to encode
    /// English alphanumeric identifiers.
    /// The ranges are specified as:
    /// 'a' .. 'z' ---  0 .. 25
    /// 'A' .. 'Z' --- 26 .. 51
    /// '0' .. '9' --- 52 .. 61
    ///        '.' --- 62
    ///        '_' --- 63
    private static let char6Map =
        Array(zip("abcdefghijklmnopqrstuvwxyz" +
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                    "0123456789._", (0 as UInt)...))

    /// Writes a char6-encoded value.
    internal func writeChar6<IntType>(_ value: IntType)
        where IntType: UnsignedInteger & ExpressibleByIntegerLiteral
    {
        guard (0..<64).contains(value) else {
            fatalError("invalid char6 value")
        }
        let v = BitstreamWriter.char6Map[Int(value)].1
        write(v, width: 6)
    }

    /// Writes a value with the provided abbreviation encoding.
    internal func writeAbbrevField(_ op: Bitstream.Abbreviation.Operand, value: UInt32) {
        switch op {
        case .literal(let literalValue):
            // Do not write anything
            precondition(value == literalValue,
                         "literal value must match abbreviated literal " +
                            "(expected \(literalValue), got \(value))")
        case .fixed(let bitWidth):
            write(value, width: UInt8(bitWidth))
        case .vbr(let chunkBitWidth):
            writeVBR(value, width: UInt8(chunkBitWidth))
        case .char6:
            writeChar6(value)
        case .blob, .array:
            fatalError("cannot emit a field as array or blob")
        }
    }

    /// Writes a block, beginning with the provided block code and the
    /// abbreviation width
    internal func writeBlock(
        _ blockID: Bitstream.BlockID,
        newAbbrevWidth: UInt8? = nil,
        emitRecords: () -> Void
    ) {
        enterSubblock(blockID, abbreviationBitWidth: newAbbrevWidth)
        emitRecords()
        endBlock()
    }

    internal func writeBlob<S>(_ bytes: S, includeSize: Bool = true)
        where S: Collection, S.Element == UInt8
    {
        if includeSize {
            // Emit a vbr6 to indicate the number of elements present.
            self.writeVBR(UInt8(bytes.count), width: 6)
        }

        // Flush to a 32-bit alignment boundary.
        self.alignIfNeeded()

        // Emit literal bytes.
        for byte in bytes {
            self.write(byte, width: 8)
        }

        // Align end to 32-bits.
        while (self.bufferOffset & 3) != 0 {
            self.write(0 as UInt8, width: 8)
        }
    }


    /// Writes the blockinfo block and allows emitting abbreviations
    /// and records in it.
    internal func writeBlockInfoBlock(emitRecords: () -> Void) {
        writeBlock(.blockInfo, newAbbrevWidth: 2) {
            currentBlockID = nil
            blockInfoRecords = [:]
            emitRecords()
        }
    }
}

// MARK: Block Management

extension BitstreamWriter {
    /// Defines a scope under which a new block's contents can be defined.
    ///
    /// - Parameters:
    ///   - blockID: The ID of the block to emit.
    ///   - abbreviationBitWidth: The width of the largest abbreviation ID in this block.
    ///   - defineSubBlock: A closure that is called to define the contents of the new block.
    internal func withSubBlock(
        _ blockID: Bitstream.BlockID,
        abbreviationBitWidth: UInt8? = nil,
        defineSubBlock: () -> Void
    ) {
        self.enterSubblock(blockID, abbreviationBitWidth: abbreviationBitWidth)
        defineSubBlock()
        self.endBlock()
    }

    /// Marks the start of a new block record and switches to it.
    ///
    /// - Note: You must call `BitstreamWriter.endBlock()` once you are finished
    ///         encoding data into the newly-created block, else the resulting
    ///         bitstream file will become corrupted. It is recommended that
    ///         you use `BitstreamWriter.withSubBlock(_:abbreviationBitWidth:defineSubBlock:)`
    ///         instead.
    ///
    /// - Parameters:
    ///   - blockID: The ID of the block to emit.
    ///   - abbreviationBitWidth: The width of the largest abbreviation ID in this block.
    internal func enterSubblock(
        _ blockID: Bitstream.BlockID,
        abbreviationBitWidth: UInt8? = nil
    ) {
        // [ENTER_SUBBLOCK, blockid(vbr8), newabbrevlen(vbr4),
        //                  <align32bits>, blocklen_32]
        writeCode(.enterSubblock)

        let newWidth = abbreviationBitWidth ?? codeBitWidth

        writeVBR(blockID.rawValue,  width: 8)

        writeVBR(newWidth, width: 4)
        alignIfNeeded()

        // Caller is responsible for filling in the blocklen_32 value
        // after emitting the contents of the block.
        let byteOffset = bufferOffset
        write(0 as UInt, width: 32)

        let block = Block(previousCodeWidth: codeBitWidth,
                          lengthPlaceholderByteIndex: byteOffset,
                          previousAbbrevs: currentAbbreviations)

        codeBitWidth = newWidth
        currentAbbreviations = []
        blockScope.append(block)
        if let blockInfo = blockInfoRecords[blockID.rawValue] {
            currentAbbreviations.append(contentsOf: blockInfo.abbrevs)
        }
    }

    /// Marks the end of a new block record.
    internal func endBlock() {
        guard let block = blockScope.popLast() else {
            fatalError("endBlock() called with no block registered")
        }

        let blockLengthInBytes = data.count - block.lengthPlaceholderByteIndex
        let blockLengthIn32BitWords = UInt32(blockLengthInBytes / 4)

        writeCode(.endBlock)
        alignIfNeeded()

        // Backpatch the block length now that we've finished it
        overwriteBytes(blockLengthIn32BitWords,
                       byteIndex: block.lengthPlaceholderByteIndex)

        // Restore the inner block's code size and abbrev table.
        codeBitWidth = block.previousCodeWidth
        currentAbbreviations = block.previousAbbrevs
    }

    /// Defines an abbreviation within the blockinfo block for the provided
    /// block ID.
    internal func defineBlockInfoAbbreviation(
        _ blockID: Bitstream.BlockID,
        _ abbrev: Bitstream.Abbreviation
    ) -> Bitstream.AbbreviationID {
        self.switch(to: blockID)
        encodeAbbreviation(abbrev)
        let info = getOrCreateBlockInfo(blockID.rawValue)
        info.abbrevs.append(abbrev)
        let rawValue = UInt64(info.abbrevs.count - 1) + Bitstream.AbbreviationID.firstApplicationID.rawValue
        return Bitstream.AbbreviationID(rawValue: rawValue)
    }


    private func overwriteBytes(_ int: UInt32, byteIndex: Int) {
        let i = int.littleEndian
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: i, toByteOffset: byteIndex, as: UInt32.self)
        }
    }

    /// Gets the BlockInfo for the provided ID or creates it if it hasn't been
    /// created already.
    private func getOrCreateBlockInfo(_ id: UInt8) -> BlockInfo {
        if let blockInfo = blockInfoRecords[id] { return blockInfo }
        let info = BlockInfo()
        blockInfoRecords[id] = info
        return info
    }

    private func `switch`(to blockID: Bitstream.BlockID) {
        if currentBlockID == blockID { return }
        writeRecord(Bitstream.BlockInfoCode.setBID) {
            $0.append(blockID)
        }
        currentBlockID = blockID
    }
}
