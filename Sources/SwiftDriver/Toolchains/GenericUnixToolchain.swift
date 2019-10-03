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

    throw Error.unableToFind(tool: exec)
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
    }
  }

  public func defaultSDKPath() throws -> AbsolutePath? {
    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool { false }
}
