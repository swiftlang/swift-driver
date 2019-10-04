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

  /// When the compiler invocation should be stored in debug information.
  var shouldStoreInvocationInDebugInfo: Bool { get }

  /// Constructs a proper output file name for a linker product.
  func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String

  /// Adds platform-specific linker flags to the provided command line
  func addPlatformSpecificLinkerArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    linkerOutputType: LinkOutputType,
    inputs: [TypedVirtualPath],
    outputFile: VirtualPath,
    sdkPath: String?,
    targetTriple: Triple
  ) throws -> AbsolutePath
}
