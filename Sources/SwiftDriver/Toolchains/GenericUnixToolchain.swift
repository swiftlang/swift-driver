import TSCBasic

/// Toolchain for Unix-like systems.
public final class GenericUnixToolchain: Toolchain {
  enum Error: Swift.Error {
    case unableToFind(tool: String)
  }

  private let searchPaths: [AbsolutePath]

  init() {
    self.searchPaths = getEnvSearchPaths(pathString: ProcessEnv.vars["PATH"], currentWorkingDirectory: localFileSystem.currentWorkingDirectory)
  }

  private func lookup(exec: String) throws -> AbsolutePath {
    if let path = lookupExecutablePath(filename: exec, searchPaths: searchPaths) {
      return path
    }

    // If we happen to be on a macOS host, some tools might not be in our
    // PATH, so we'll just use xcrun to find them too.
    #if os(macOS)
    return try xcrunFind(exec: exec)
    #else
    throw Error.unableToFind(tool: exec)
    #endif

  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return moduleName
    case .dynamicLibrary: return "lib\(moduleName).so"
    case .staticLibrary: return "lib\(moduleName).a"
    }
  }

  public func getToolPath(_ tool: Tool) throws -> AbsolutePath {
    switch tool {
    case .swiftCompiler:
      return try lookup(exec: "swift")
    case .staticLinker:
      return try lookup(exec: "ar")
    case .dynamicLinker:
      // FIXME: This needs to look in the tools_directory first.
      return try lookup(exec: "clang")
    case .clang:
      return try lookup(exec: "clang")
    case .swiftAutolinkExtract:
      return try lookup(exec: "swift-autolink-extract")
    case .dsymutil:
      return try lookup(exec: "dsymutil")
    }
  }

  public func defaultSDKPath() throws -> AbsolutePath? {
    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool { false }
}
