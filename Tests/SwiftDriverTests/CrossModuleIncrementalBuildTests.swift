//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TSCBasic
import TestUtilities
import Testing

@Suite(.enabled(if: sdkArgumentsAvailable)) struct CrossModuleIncrementalBuildTests {
  func makeOutputFileMap(
    in workingDirectory: AbsolutePath,
    module: String,
    for files: [AbsolutePath],
    outputTransform transform: (String) -> String = { $0 }
  ) -> String {
    """
    {
      "": {
        "swift-dependencies": "\(workingDirectory.appending(component: "\(module).swiftdeps").nativePathString(escaped: true))"
      }
    """.appending(
      files.map { file in
        """
        ,
        "\(file.nativePathString(escaped: true))": {
          "dependencies": "\(transform(file.basenameWithoutExt) + ".d")",
          "object": "\(transform(file.nativePathString(escaped: true)) + ".o")",
          "swiftmodule": "\(transform(file.basenameWithoutExt) + "~partial.swiftmodule")",
          "swift-dependencies": "\(transform(file.basenameWithoutExt) + ".swiftdeps")"
          }
        """
      }.joined(separator: "\n").appending("\n}")
    )
  }

  @Test func changingOutputFileMap() async throws {
    let sdkArguments = try #require(try Driver.sdkArgumentsForTesting())
    try await withTemporaryDirectory { path in
      let magic = path.appending(component: "magic.swift")
      try localFileSystem.writeFileContents(magic) {
        $0.send("public func castASpell() {}")
      }

      let ofm = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofm) {
        $0.send(
          self.makeOutputFileMap(in: path, module: "MagicKit", for: [magic]) {
            $0 + "-some_suffix"
          }
        )
      }

      let driverArgs =
        [
          "swiftc",
          "-incremental",
          "-emit-module",
          "-output-file-map", ofm.pathString,
          "-module-name", "MagicKit",
          "-working-directory", path.pathString,
          "-c",
          magic.pathString,
        ] + sdkArguments
      do {
        var driver = try TestDriver(args: driverArgs)
        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
      }

      try localFileSystem.writeFileContents(ofm) {
        $0.send(
          self.makeOutputFileMap(in: path, module: "MagicKit", for: [magic]) {
            $0 + "-some_other_suffix"
          }
        )
      }

      do {
        var driver = try TestDriver(args: driverArgs)
        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
      }
    }
  }

  @Test func embeddedModuleDependencies() async throws {
    let sdkArguments = try #require(try Driver.sdkArgumentsForTesting())
    try await withTemporaryDirectory { path in
      do {
        let magic = path.appending(component: "magic.swift")
        try localFileSystem.writeFileContents(magic) {
          $0.send("public func castASpell() {}")
        }

        let ofm = path.appending(component: "ofm.json")
        try localFileSystem.writeFileContents(ofm) {
          $0.send(self.makeOutputFileMap(in: path, module: "MagicKit", for: [magic]))
        }

        var driver = try TestDriver(
          args: [
            "swiftc",
            "-incremental",
            "-emit-module",
            "-output-file-map", ofm.pathString,
            "-module-name", "MagicKit",
            "-working-directory", path.pathString,
            "-c",
            magic.pathString,
          ] + sdkArguments
        )
        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
      }

      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import MagicKit\n")
        $0.send("castASpell()")
      }

      let ofm = path.appending(component: "ofm2.json")
      try localFileSystem.writeFileContents(ofm) {
        $0.send(self.makeOutputFileMap(in: path, module: "theModule", for: [main]))
      }

      var driver = try TestDriver(
        args: [
          "swiftc",
          "-incremental",
          "-emit-module",
          "-output-file-map", ofm.pathString,
          "-module-name", "theModule",
          "-I", path.pathString,
          "-working-directory", path.pathString,
          "-c",
          main.pathString,
        ] + sdkArguments
      )

      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)

      let sourcePath = path.appending(component: "main.swiftdeps")
      let data = try localFileSystem.readFileContents(sourcePath)
      try driver.withModuleDependencyGraph { host in
        let testGraph = try #require(
          try SourceFileDependencyGraph(
            internedStringTable: host.internedStringTable,
            data: data,
            fromSwiftModule: false
          )
        )
        #expect(testGraph.majorVersion == 1)
        #expect(testGraph.minorVersion == 0)
        testGraph.verify()

        var foundNode = false
        let swiftmodulePath = ExternalDependency(
          fileName: path.appending(component: "MagicKit.swiftmodule")
            .pathString.intern(in: host),
          host.internedStringTable
        )
        testGraph.forEachNode { node in
          if case .externalDepend(swiftmodulePath) = node.key.designator {
            #expect(!foundNode)
            foundNode = true
            #expect(node.key.aspect == .interface)
            #expect(node.defsIDependUpon.isEmpty)
            #expect(node.definitionVsUse == .use)
          }
        }
        #expect(foundNode)
      }
    }
  }
}
