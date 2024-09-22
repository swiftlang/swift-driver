//===--------------- GenericUnixToolchain.swift - Swift *nix Toolchain ----===//
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

import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem

internal enum AndroidNDK {
  internal static func getOSName() -> String? {
    // The NDK is only available on macOS, linux and windows hosts currently.
#if os(Windows)
    "windows"
#elseif os(Linux)
    "linux"
#elseif os(macOS)
    "darwin"
#else
    nil
#endif
  }

  internal static func getDefaultSysrootPath(in env: [String:String]) -> AbsolutePath? {
    // The NDK is only available on an x86_64 hosts currently.
#if arch(x86_64)
    guard let ndk = env["ANDROID_NDK_ROOT"], let os = getOSName() else { return nil }
    return try? AbsolutePath(validating: ndk)
      .appending(components: "toolchains", "llvm", "prebuilt")
      .appending(component: "\(os)-x86_64")
      .appending(component: "sysroot")
#else
    return nil
#endif
  }
}

/// Toolchain for Unix-like systems.
public final class GenericUnixToolchain: Toolchain {
  public let env: [String: String]

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for queries.
  public let fileSystem: FileSystem

  /// Doubles as path cache and point for overriding normal lookup
  private var toolPaths = [Tool: AbsolutePath]()

  // An externally provided path from where we should find compiler
  public let compilerExecutableDir: AbsolutePath?

  public let toolDirectory: AbsolutePath?

  public let dummyForTestingObjectFormat = Triple.ObjectFormat.elf

  public init(env: [String: String], executor: DriverExecutor, fileSystem: FileSystem = localFileSystem, compilerExecutableDir: AbsolutePath? = nil, toolDirectory: AbsolutePath? = nil) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
    self.compilerExecutableDir = compilerExecutableDir
    self.toolDirectory = toolDirectory
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return moduleName
    case .dynamicLibrary: return "lib\(moduleName).so"
    case .staticLibrary: return "lib\(moduleName).a"
    }
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
    case .staticLinker:
      return try lookup(executable: "llvm-ar")
    case .dynamicLinker:
      // FIXME: This needs to look in the tools_directory first.
      return try lookup(executable: "clang")
    case .clang:
      return try lookup(executable: "clang")
    case .clangxx:
      return try lookup(executable: "clang++")
    case .swiftAutolinkExtract:
      return try lookup(executable: "swift-autolink-extract")
    case .dsymutil:
      return try lookup(executable: "dsymutil")
    case .lldb:
      return try lookup(executable: "lldb")
    case .dwarfdump:
      return try lookup(executable: "dwarfdump")
    case .swiftHelp:
      return try lookup(executable: "swift-help")
    case .swiftAPIDigester:
      return try lookup(executable: "swift-api-digester")
    }
  }

  public func overrideToolPath(_ tool: Tool, path: AbsolutePath) {
    toolPaths[tool] = path
  }

  public func clearKnownToolPath(_ tool: Tool) {
    toolPaths.removeValue(forKey: tool)
  }

  public func defaultSDKPath(_ target: Triple?) throws -> AbsolutePath? {
    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool { false }

  public var globalDebugPathRemapping: String? { nil }

  public func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String {
    let environment = (targetTriple.environment == .android) ? "-android" : ""
    return "libclang_rt.\(sanitizer.libraryName)-\(targetTriple.archName)\(environment).a"
  }

  public func addPlatformSpecificCommonFrontendOptions(
    commandLine: inout [Job.ArgTemplate],
    inputs: inout [TypedVirtualPath],
    frontendTargetInfo: FrontendTargetInfo,
    driver: inout Driver
  ) throws {
    if driver.targetTriple.environment == .android {
      if let sysroot = driver.parsedOptions.getLastArgument(.sysroot)?.asSingle {
        commandLine.appendFlag("-sysroot")
        try commandLine.appendPath(VirtualPath(path: sysroot))
      } else if let sysroot = AndroidNDK.getDefaultSysrootPath(in: self.env) {
        commandLine.appendFlag("-sysroot")
        try commandLine.appendPath(VirtualPath(path: sysroot.pathString))
      }
    }
  }
}
