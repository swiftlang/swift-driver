import TSCBasic

public enum Tool {
  case swiftCompiler
  case staticLinker
  case dynamicLinker
}

/// Describes a toolchain, which includes information about compilers, linkers
/// and other tools required to build Swift code.
public protocol Toolchain {
  /// Retrieve the absolute path to a particular tool.
  func getToolPath(_ tool: Tool) throws -> AbsolutePath
}

/// The host's toolchain, to use as a default.
public var hostToolchain: Toolchain {
  // FIXME: Support Linux, Windows, Android, etc. toolchains as well!
  return DarwinToolchain()
}
