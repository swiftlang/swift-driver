//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.AbsolutePath

/// Answers dependency scans with a graph holding only the main module, so driver tests plan without scanning sources.
@_spi(Testing) public final class TestHarnessInterModuleDependencyOracle: InterModuleDependencyOracle {
  @_spi(Testing) public override func getDependencies(workingDirectory: AbsolutePath,
                                                      moduleAliases: [String: String]? = nil,
                                                      commandLine: [String],
                                                      diagnostics: inout [ScannerDiagnosticPayload])
  throws -> InterModuleDependencyGraph {
    guard let flagIndex = commandLine.firstIndex(of: "-module-name"),
          flagIndex + 1 < commandLine.count else {
      throw DependencyScanningError.dependencyScanFailed(
        "TestHarnessInterModuleDependencyOracle: the scan command line has no -module-name")
    }
    let moduleName = commandLine[flagIndex + 1]
    let modulePath = try VirtualPath.intern(path: "\(moduleName).swiftmodule")
    let mainModule = ModuleInfo(modulePath: TextualVirtualPath(path: modulePath),
                                libraryLevel: nil,
                                sourceFiles: [],
                                directDependencies: [],
                                linkLibraries: [],
                                importInfos: [],
                                details: .swift(SwiftModuleDetails(bridgingPchCommandLine: nil)))
    return InterModuleDependencyGraph(mainModuleName: moduleName,
                                      modules: [.swift(moduleName): mainModule])
  }

  @_spi(Testing) public override func getImports(workingDirectory: AbsolutePath,
                                                 moduleAliases: [String: String]? = nil,
                                                 commandLine: [String],
                                                 diagnostics: inout [ScannerDiagnosticPayload])
  throws -> InterModuleDependencyImports {
    InterModuleDependencyImports(imports: [], moduleAliases: moduleAliases)
  }

  // With no scanner-built PCH command line in the graph, the driver must build the PCH command itself.
  @_spi(Testing) public override var supportsBridgingHeaderPCHCommand: Bool { false }

  public override func getOrCreateCAS(pluginPath: AbsolutePath?, onDiskPath: AbsolutePath?,
                                      pluginOptions: [(String, String)]) throws -> SwiftScanCAS {
    throw DependencyScanningError.casError(
      "TestHarnessInterModuleDependencyOracle does not support compilation caching; mark the test with .realDependencyScan")
  }
}
