//===--------------- DebugInfo.swift - Swift Debug Information ------------===//
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

/// The debug information produced by the driver.
@_spi(Testing) public struct DebugInfo {

  /// Describes the format used for debug information.
  public enum Format: String {
    case dwarf
    case codeView = "codeview"
  }

  /// Describes the level of debug information.
  public enum Level {
    /// Line tables only (no type information).
    case lineTables

    /// Line tables with AST type references
    case astTypes

    /// Line tables with AST type references and DWARF types
    case dwarfTypes

    public var requiresModule: Bool {
      switch self {
      case .lineTables:
        return false

      case .astTypes, .dwarfTypes:
        return true
      }
    }
  }

  /// The format of debug information.
  public let format: Format

  /// The DWARF standard version to be produced.
  public let dwarfVersion: UInt8

  /// The level of debug information.
  public let level: Level?

  /// Whether 'dwarfdump' should be used to verify debug info.
  public let shouldVerify: Bool
}
