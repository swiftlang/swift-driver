//===----------- BitstreamVisitor.swift - LLVM Bitstream Visitor ----------===//
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

internal protocol BitstreamVisitor {
  /// Customization point to validate a bitstream's signature or "magic number".
  func validate(signature: Bitcode.Signature) throws
  /// Called when a new block is encountered. Return `true` to enter the block
  /// and read its contents, or `false` to skip it.
  mutating func shouldEnterBlock(id: UInt64) throws -> Bool
  /// Called when a block is exited.
  mutating func didExitBlock() throws
  /// Called whenever a record is encountered.
  mutating func visit(record: BitcodeElement.Record) throws
}
