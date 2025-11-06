//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import SwiftOptions

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.DiagnosticData
import protocol TSCBasic.FileSystem
import var TSCBasic.localFileSystem
import typealias TSCBasic.ProcessEnvironmentBlock

/// Toolchain for WebAssembly-based systems.
public final class WebAssemblyToolchain: Toolchain {
  @_spi(Testing) public enum Error: Swift.Error, DiagnosticData {
    case interactiveModeUnsupportedForTarget(String)
    case dynamicLibrariesUnsupportedForTarget(String)
    case sanitizersUnsupportedForTarget(String)
    case profilingUnsupportedForTarget(String)
    case missingExternalDependency(String)

    public var description: String {
      switch self {
      case .interactiveModeUnsupportedForTarget(let triple):
        return "interactive mode is unsupported for target '\(triple)'; use 'swiftc' instead"
      case .dynamicLibrariesUnsupportedForTarget(let triple):
        return "dynamic libraries are unsupported for target '\(triple)'"
      case .sanitizersUnsupportedForTarget(let triple):
        return "sanitizers are unsupported for target '\(triple)'"
      case .profilingUnsupportedForTarget(let triple):
        return "profiling is unsupported for target '\(triple)'"
      case .missingExternalDependency(let dependency):
        return "missing external dependency '\(dependency)'"
      }
    }
  }

  public let env: ProcessEnvironmentBlock

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for queries.
  public let fileSystem: FileSystem

  /// Doubles as path cache and point for overriding normal lookup
  private var toolPaths = [Tool: AbsolutePath]()

  public let compilerExecutableDir: AbsolutePath?

  public let toolDirectory: AbsolutePath?

  public let dummyForTestingObjectFormat = Triple.ObjectFormat.wasm

  public init(env: ProcessEnvironmentBlock, executor: DriverExecutor, fileSystem: FileSystem = localFileSystem, compilerExecutableDir: AbsolutePath? = nil, toolDirectory: AbsolutePath? = nil) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
    self.compilerExecutableDir = compilerExecutableDir
    self.toolDirectory = toolDirectory
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable:
      return moduleName
    case .dynamicLibrary:
      // Wasm doesn't support dynamic libraries yet, but we'll report the error later.
      return ""
    case .staticLibrary:
      return "lib\(moduleName).a"
    }
  }

  public func addAutoLinkFlags(for linkLibraries: [LinkLibraryInfo], to commandLine: inout [Job.ArgTemplate]) {
    for linkLibrary in linkLibraries {
      commandLine.appendFlag("-l\(linkLibrary.linkName)")
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
    switch sanitizer {
    case .address:
      return "libclang_rt.\(sanitizer.libraryName)-\(targetTriple.archName).a"
    default:
      throw Error.sanitizersUnsupportedForTarget(targetTriple.triple)
    }
  }

  public func platformSpecificInterpreterEnvironmentVariables(env: ProcessEnvironmentBlock,
                                                              parsedOptions: inout ParsedOptions,
                                                              sdkPath: VirtualPath.Handle?,
                                                              targetInfo: FrontendTargetInfo) throws -> ProcessEnvironmentBlock {
    throw Error.interactiveModeUnsupportedForTarget(targetInfo.target.triple.triple)
  }
}
