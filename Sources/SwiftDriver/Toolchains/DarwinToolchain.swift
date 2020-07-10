//===--------------- DarwinToolchain.swift - Swift Darwin Toolchain -------===//
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
import TSCBasic

/// Toolchain for Darwin-based platforms, such as macOS and iOS.
///
/// FIXME: This class is not thread-safe.
public final class DarwinToolchain: Toolchain {
  public let env: [String: String]

  /// Doubles as path cache and point for overriding normal lookup
  private var toolPaths = [Tool: AbsolutePath]()

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for any file operations.
  public let fileSystem: FileSystem

  public init(env: [String: String], executor: DriverExecutor, fileSystem: FileSystem = localFileSystem) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
  }

  /// Retrieve the absolute path for a given tool.
  public func getToolPath(_ tool: Tool) throws -> AbsolutePath {
    // Check the cache
    if let toolPath = toolPaths[tool] {
      return toolPath
    }
    let path = try lookupToolPath(tool)
    // Cache the path
    toolPaths[tool] = path
    return path
  }

  private func lookupToolPath(_ tool: Tool) throws -> AbsolutePath {
    switch tool {
    case .swiftCompiler:
      return try lookup(executable: "swift-frontend")

    case .dynamicLinker:
      return try lookup(executable: "ld")

    case .staticLinker:
      return try lookup(executable: "libtool")

    case .dsymutil:
      return try lookup(executable: "dsymutil")

    case .clang:
      let result = try executor.checkNonZeroExit(
        args: "xcrun", "-toolchain", "default", "-f", "clang",
        environment: env
      ).spm_chomp()
      return AbsolutePath(result)
    case .swiftAutolinkExtract:
      return try lookup(executable: "swift-autolink-extract")
    case .lldb:
      return try lookup(executable: "lldb")
    case .dwarfdump:
      return try lookup(executable: "dwarfdump")
    case .swiftHelp:
      return try lookup(executable: "swift-help")
    case .jitStub:
      return try lookup(executable: "jit-stub")
    }
  }

  public func overrideToolPath(_ tool: Tool, path: AbsolutePath) {
    toolPaths[tool] = path
  }

  /// SDK path.
  public lazy var sdk: Result<AbsolutePath, Swift.Error> = Result {
    let result = try executor.checkNonZeroExit(
      args: "xcrun", "-sdk", "macosx", "--show-sdk-path",
      environment: env
    ).spm_chomp()
    return AbsolutePath(result)
  }

  /// Path to the StdLib inside the SDK.
  public func sdkStdlib(sdk: AbsolutePath) -> AbsolutePath {
    sdk.appending(RelativePath("usr/lib/swift"))
  }

  public var resourcesDirectory: Result<AbsolutePath, Swift.Error> {
    // FIXME: This will need to take -resource-dir and target triple into account.
    return Result {
      try getToolPath(.swiftCompiler).appending(RelativePath("../../lib/swift/macosx"))
    }
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return moduleName
    case .dynamicLibrary: return "lib\(moduleName).dylib"
    case .staticLibrary: return "lib\(moduleName).a"
    }
  }

  public var compatibility50: Result<AbsolutePath, Error> {
    resourcesDirectory.map { $0.appending(component: "libswiftCompatibility50.a") }
  }

  public var compatibilityDynamicReplacements: Result<AbsolutePath, Error> {
    resourcesDirectory.map { $0.appending(component: "libswiftCompatibilityDynamicReplacements.a") }
  }

  public var clangRT: Result<AbsolutePath, Error> {
    resourcesDirectory.map { $0.appending(RelativePath("../clang/lib/darwin/libclang_rt.osx.a")) }
  }

  public func defaultSDKPath(_ target: Triple?) throws -> AbsolutePath? {
    let hostIsMacOS: Bool
    #if os(macOS)
    hostIsMacOS = true
    #else
    hostIsMacOS = false
    #endif

    if target?.isMacOSX == true || hostIsMacOS {
      let result = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path",
        environment: env
      ).spm_chomp()
      return AbsolutePath(result)
    }

    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool {
    // This matches the behavior in Clang.
    !(env["RC_DEBUG_OPTIONS"]?.isEmpty ?? false)
  }

  public func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String {
    return """
    libclang_rt.\(sanitizer.libraryName)_\
    \(targetTriple.darwinPlatform!.libraryNameSuffix)\
    \(isShared ? "_dynamic.dylib" : ".a")
    """
  }

  public func getSymlinkInvocation(
    from input: VirtualPath, to output: VirtualPath
  ) throws -> CommandInvocation {
    CommandInvocation(.absolute(try lookup(executable: "ln")),
                      args: [.flag("-s"), .path(input), .path(output)])
  }

  public func getMkdirInvocation(for path: VirtualPath) throws -> CommandInvocation {
    CommandInvocation(.absolute(try lookup(executable: "mkdir")),
                      args: [.path(path)])
  }
}
