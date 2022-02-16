//===----------- WindowsToolchain.swift - Swift Windows Toolchain ---------===//
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
import SwiftOptions

extension WindowsToolchain {
  public enum ToolchainValidationError: Error, DiagnosticData {
    case unsupportedSanitizer(Sanitizer)
  }
}

extension WindowsToolchain.ToolchainValidationError {
  public var description: String {
    switch self {
    case .unsupportedSanitizer(let sanitizer):
      return "unsupported sanitizer: \(sanitizer)"
    }
  }
}

@_spi(Testing) public final class WindowsToolchain: Toolchain {
  public let env: [String:String]
  public let executor: DriverExecutor
  public let fileSystem: FileSystem
  public let compilerExecutableDir: AbsolutePath?
  public let toolDirectory: AbsolutePath?

  public var dummyForTestingObjectFormat: Triple.ObjectFormat {
    .coff
  }

  private var toolPaths: [Tool:AbsolutePath] = [:]

  public init(env: [String:String], executor: DriverExecutor,
              fileSystem: FileSystem = localFileSystem,
              compilerExecutableDir: AbsolutePath? = nil,
              toolDirectory: AbsolutePath? = nil) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
    self.compilerExecutableDir = compilerExecutableDir
    self.toolDirectory = toolDirectory
  }

  public func getToolPath(_ tool: Tool) throws -> AbsolutePath {
    guard let toolPath = toolPaths[tool] else {
      let toolPath = try lookupToolPath(tool)
      toolPaths.updateValue(toolPath, forKey: tool)
      return toolPath
    }
    return toolPath
  }

  private func lookupToolPath(_ tool: Tool) throws -> AbsolutePath {
    switch tool {
    case .swiftAPIDigester:
      return try lookup(executable: "swift-api-digester.exe")
    case .swiftCompiler:
      return try lookup(executable: "swift-frontend.exe")
    case .staticLinker:
      return try lookup(executable: "lld-link.exe")
    case .dynamicLinker:
      return try lookup(executable: "clang.exe")
    case .clang:
      return try lookup(executable: "clang.exe")
    case .swiftAutolinkExtract:
      return try lookup(executable: "swift-autolink-extract.exe")
    case .lldb:
      return try lookup(executable: "lldb.exe")
    case .dsymutil:
      return try lookup(executable: "llvm-dsymutil.exe")
    case .dwarfdump:
      return try lookup(executable: "llvm-dwarfdump.exe")
    case .swiftHelp:
      return try lookup(executable: "swift-help.exe")
    }
  }

  public func overrideToolPath(_ tool: Tool, path: AbsolutePath) {
    toolPaths.updateValue(path, forKey: tool)
  }

  public func clearKnownToolPath(_ tool: Tool) {
    toolPaths.removeValue(forKey: tool)
  }

  public func sdkStdlib(sdk: AbsolutePath) -> AbsolutePath {
    sdk.appending(RelativePath("usr/lib/swift"))
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return "\(moduleName).exe"
    case .dynamicLibrary: return "\(moduleName).dll"
    case .staticLibrary: return "lib\(moduleName).lib"
    }
  }

  public func defaultSDKPath(_ target: Triple?) throws -> AbsolutePath? {
    // The SDKROOT environment always takes precedent.  If SDKROOT is undefined,
    // but we have DEVELOPER_DIR defined and a valid triple, compose the SDK
    // root relative to the DEVELOPER_DIR.  The SDKs are always laid out as
    // `[DeveloperDir]\Platforms\[OS].platform\Developer\SDKs\[OS].sdk`,
    // allowing us to locate it relative to the DEVELOPER_DIR environment
    // variable.

    // TODO(compnerd): replicate the SPM processing of the SDKInfo.plist
    if let SDKROOT = env["SDKROOT"] {
      return AbsolutePath(SDKROOT)
    } else if let DEVELOPER_DIR = env["DEVELOPER_DIR"], let os = target?.os?.rawValue {
      // FIXME(compnerd) we should capitalise the OS name, e.g. windows ->
      // Windows; we get away with this for now as Windows has a
      // case-insensitive file system.
      return AbsolutePath("\(DEVELOPER_DIR)\\Platforms\\\(os).platform\\Developer\\SDKs\\\(os).sdk")
    }
    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool {
    !env["RC_DEBUG_OPTIONS", default: ""].isEmpty
  }

  public var globalDebugPathRemapping: String? { nil }
    
  public func runtimeLibraryName(for sanitizer: Sanitizer, targetTriple: Triple,
                                 isShared: Bool) throws -> String {
    // TODO(compnerd) handle shared linking
    return "clang_rt.\(sanitizer.libraryName).lib"
  }

  public func validateArgs(_ parsedOptions: inout ParsedOptions,
                           targetTriple: Triple, targetVariantTriple: Triple?,
                           compilerOutputType: FileType?,
                           diagnosticEngine: DiagnosticsEngine) throws {
    // TODO(compnerd) validate any options we can
  }
}
