//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
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
import typealias TSCBasic.ProcessEnvironmentBlock

@_spi(Testing) public enum WebAssemblyToolchainError: Swift.Error, DiagnosticData {
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

/// Shared behavior for WebAssembly-based toolchains (`WASIToolchain` for
/// WASI, `EmscriptenToolchain` for wasm32-unknown-emscripten). Not part of the
/// public API — visible only within `SwiftDriver`.
protocol WebAssemblyToolchainProtocol: Toolchain, AnyObject {
  var toolPaths: [Tool: AbsolutePath] { get set }
}

extension WebAssemblyToolchainProtocol {
  public func addAutoLinkFlags(for linkLibraries: [LinkLibraryInfo], to commandLine: inout [Job.ArgTemplate]) {
    for linkLibrary in linkLibraries {
      commandLine.appendFlag("-l\(linkLibrary.linkName)")
    }
  }

  public func getToolPath(_ tool: Tool) throws -> AbsolutePath {
    if let toolPath = toolPaths[tool] {
      return toolPath
    }
    let path = try lookupWebAssemblyToolPath(tool)
    toolPaths[tool] = path
    return path
  }

  private func lookupWebAssemblyToolPath(_ tool: Tool) throws -> AbsolutePath {
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
    case .emcc:
      return try lookup(executable: "emcc")
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
  ) throws -> String? {
    switch sanitizer {
    case .address:
      return "libclang_rt.\(sanitizer.runtimeLibraryName!)-\(targetTriple.archName).a"
    default:
      throw WebAssemblyToolchainError.sanitizersUnsupportedForTarget(targetTriple.triple)
    }
  }

  public func platformSpecificInterpreterEnvironmentVariables(env: ProcessEnvironmentBlock,
                                                              parsedOptions: inout ParsedOptions,
                                                              sdkPath: VirtualPath.Handle?,
                                                              targetInfo: FrontendTargetInfo) throws -> ProcessEnvironmentBlock {
    throw WebAssemblyToolchainError.interactiveModeUnsupportedForTarget(targetInfo.target.triple.triple)
  }
}
