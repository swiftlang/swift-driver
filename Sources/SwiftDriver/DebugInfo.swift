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
