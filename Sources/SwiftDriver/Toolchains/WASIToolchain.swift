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
import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.FileSystem
import var TSCBasic.localFileSystem
import typealias TSCBasic.ProcessEnvironmentBlock

/// Toolchain for WASI (`wasm32-unknown-wasi` / `wasm64-unknown-wasi`).
public final class WASIToolchain: WebAssemblyToolchainProtocol {
  @_spi(Testing) public typealias Error = WebAssemblyToolchainError

  public let env: ProcessEnvironmentBlock

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for queries.
  public let fileSystem: FileSystem

  /// Doubles as path cache and point for overriding normal lookup
  var toolPaths = [Tool: AbsolutePath]()

  public let compilerExecutableDir: AbsolutePath?

  public let toolDirectory: AbsolutePath?

  public let dummyForTestingObjectFormat = Triple.ObjectFormat.wasm

  public init(
    env: ProcessEnvironmentBlock,
    executor: DriverExecutor,
    fileSystem: FileSystem = localFileSystem,
    compilerExecutableDir: AbsolutePath? = nil,
    toolDirectory: AbsolutePath? = nil
  ) {
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
      // Wasm doesn't support dynamic libraries yet; `addPlatformSpecificLinkerArgs`
      // throws `dynamicLibrariesUnsupportedForTarget` for the `.dynamicLibrary` case
      // when the link job is built.
      return ""
    case .staticLibrary:
      return "lib\(moduleName).a"
    }
  }

  public func validateArgs(
    _ parsedOptions: inout ParsedOptions,
    targetTriple: Triple,
    targetVariantTriple: Triple?,
    compilerOutputType: FileType?,
    diagnosticsEngine: DiagnosticsEngine
  ) throws {
    warnIfEmccLinkerArgs(&parsedOptions, diagnosticsEngine: diagnosticsEngine)
  }
}
