//===--------------- main.swift - Swift Debug Information Kind ------------===//
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
/// Describes the format used for debug information.
public enum DebugInfoFormat: String {
  case dwarf
  case codeView = "codeview"
}

public enum DebugInfoLevel {
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
