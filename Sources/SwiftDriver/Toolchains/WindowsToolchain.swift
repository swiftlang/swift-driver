//===--------- WindowsToolchain.swift - Swift Windows Toolchain -----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic

/// Toolchain for Windows.
public final class WindowsToolchain: Toolchain {
  public let env: [String: String]

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for queries.
  public let fileSystem: FileSystem

  /// Doubles as path cache and point for overriding normal lookup
  private var toolPaths = [Tool: AbsolutePath]()

  public init(env: [String: String], executor: DriverExecutor, fileSystem: FileSystem = localFileSystem) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return "\(moduleName).exe"
    case .dynamicLibrary: return "\(moduleName).dll"
    case .staticLibrary: return "\(moduleName).lib"
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
      return try lookup(executable: "swift-frontend.exe")
    case .staticLinker:
      return try lookup(executable: "lib.exe")
    case .dynamicLinker:
      // FIXME: This needs to look in the tools_directory first.
      return try lookup(executable: "link.exe")
    case .clang:
      return try lookup(executable: "clang.exe")
    case .swiftAutolinkExtract:
      fatalError("Trying to look up \"swift-autolink-extract\" on Windows")
    case .dsymutil:
      fatalError("Trying to look up \"dsymutil\" on Windows")
    case .lldb:
      return try lookup(executable: "lldb.exe")
    case .dwarfdump:
      return try lookup(executable: "llvm-dwarfdump.exe")
    case .swiftHelp:
      return try lookup(executable: "swift-help.exe")
    }
  }

  public func overrideToolPath(_ tool: Tool, path: AbsolutePath) {
    toolPaths[tool] = path
  }

  public func defaultSDKPath(_ target: Triple?) throws -> AbsolutePath? {
    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool { false }

  public func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String {
    let archName: String = {
      switch targetTriple.arch {
      case .aarch64: return "aarch64"
      case .arm: return "armv7"
      case .x86: return "i386"
      case nil, .x86_64: return "x86_64"
      default: fatalError("unknown arch \(targetTriple.archName) on Windows")
      }
    }()
    return "clang_rt.\(sanitizer.libraryName)-\(archName).lib"
  }
}
