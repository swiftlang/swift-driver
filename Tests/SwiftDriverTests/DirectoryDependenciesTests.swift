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

import Foundation
@_spi(Testing) import SwiftDriver
import TSCBasic
import TestUtilities
import Testing

@Suite struct DirectoryDependenciesTests {
  /// Write a Clang module with an umbrella directory, which gives it a directory
  /// dependency.
  private func writeUmbrellaDirModule(at root: AbsolutePath) throws {
    let include = root.appending(component: "include")
    try localFileSystem.createDirectory(include.appending(component: "sub"), recursive: true)
    try localFileSystem.writeFileContents(include.appending(component: "module.modulemap")) {
      $0.send("module UmbDir { umbrella \"sub\"  module * { export * } }\n")
    }
    try localFileSystem.writeFileContents(
      include.appending(components: "sub", "a.h")) { $0.send("void a(void);\n") }
    try localFileSystem.writeFileContents(
      root.appending(component: "test.swift")) { $0.send("import UmbDir\n") }
  }

  /// Scan UmbDir as a separate build, with a fresh oracle and `paths` reported
  /// first.
  private func scanBuild(root: AbsolutePath,
                         invalidating paths: [AbsolutePath] = []) throws
      -> ModuleInfo {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()
    let oracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try oracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
    try oracle.addInvalidatedPaths(paths)
    var diagnostics: [ScannerDiagnosticPayload] = []
    let graph = try oracle.getDependencies(
      workingDirectory: root,
      commandLine: [
        "-scan-dependencies",
        "-module-name", "DirDepTest",
        "-module-cache-path", root.appending(component: "mcp").pathString,
        "-I", stdlibPath.nativePathString(escaped: false),
        "-I", shimsPath.nativePathString(escaped: false),
        "-I", root.appending(component: "include").pathString,
        "-disable-implicit-concurrency-module-import",
        "-disable-implicit-string-processing-module-import",
        root.appending(component: "test.swift").pathString,
      ] + ((try? Driver.sdkArgumentsForTesting()) ?? []),
      diagnostics: &diagnostics)
    return try #require(graph.modules[.clang("UmbDir")])
  }

  /// The basenames of the headers `info` was built from.
  private func headers(_ info: ModuleInfo) -> Set<String> {
    Set((info.sourceFiles ?? []).filter { $0.hasSuffix(".h") }.map {
      (try? AbsolutePath(validating: $0))?.basename ?? $0
    })
  }

  @Test(.requireScannerSupportsDirectoryDependencies())
  func reportsDirectoryDependencies() throws {
    try withTemporaryDirectory { root in
      try writeUmbrellaDirModule(at: root)
      let info = try scanBuild(root: root)
      guard case .clang(let details) = info.details else {
        Issue.record("UmbDir is not a Clang module")
        return
      }
      let reported = (details.directoryDependencies ?? []).map {
        VirtualPath.lookup($0.path).description
      }
      #expect(reported == [root.appending(components: "include", "sub").pathString])
    }
  }

  @Test(.requireScannerSupportsDirectoryDependencies())
  func invalidatedDirectoryRebuildsModule() throws {
    try withTemporaryDirectory { root in
      try writeUmbrellaDirModule(at: root)
      let globbedDir = root.appending(components: "include", "sub")

      let first = try headers(scanBuild(root: root))
      #expect(first.contains("a.h"))
      #expect(!first.contains("b.h"))

      // Add a header. Without a report the stale module is reused. Modules
      // built in the same second a scan starts count as up to date, so wait.
      Thread.sleep(forTimeInterval: 1)
      try localFileSystem.writeFileContents(
        globbedDir.appending(component: "b.h")) { $0.send("void b(void);\n") }
      let stale = try headers(scanBuild(root: root))
      #expect(!stale.contains("b.h"),
              "expected the stale cached module to be reused without invalidation")

      // Reporting the directory picks up the header.
      let rebuilt = try headers(scanBuild(root: root, invalidating: [globbedDir]))
      #expect(rebuilt.contains("a.h"))
      #expect(rebuilt.contains("b.h"),
              "expected the added header after invalidating its directory")
    }
  }
}
