import TSCBasic

public enum Tool {
  case swiftCompiler
  case staticLinker
  case dynamicLinker
  case clang
}

/// Describes a toolchain, which includes information about compilers, linkers
/// and other tools required to build Swift code.
public protocol Toolchain {
  /// Retrieve the absolute path to a particular tool.
  func getToolPath(_ tool: Tool) throws -> AbsolutePath

  /// Returns path of the default SDK, if there is one.
  func defaultSDKPath() throws -> AbsolutePath?
  func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String

  /// When the compiler invocation should be stored in debug information.
  var shouldStoreInvocationInDebugInfo: Bool { get }
}
