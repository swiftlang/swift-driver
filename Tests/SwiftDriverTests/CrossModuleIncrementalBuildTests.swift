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
import Foundation
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

  /// A breaking change to an
  /// imported module's interface must still be detected even when the rebuilt
  /// `.swiftmodule`'s modification time, once truncated to whole-second
  /// granularity, no longer looks newer than the importing module's own
  /// recorded build-start time.
  @Test func interfaceChangeSurvivesTimestampTruncation() async throws {
    let sdkArguments = try #require(try Driver.sdkArgumentsForTesting())
    try await withTemporaryDirectory { path in
      let a = path.appending(component: "a.swift")
      try localFileSystem.writeFileContents(a) {
        $0.send("public func callA() -> Int { 32 }")
      }
      let ofmA = path.appending(component: "ofmA.json")
      try localFileSystem.writeFileContents(ofmA) {
        $0.send(self.makeOutputFileMap(in: path, module: "A", for: [a]))
      }
      let aArgs = [
        "swiftc",
        "-incremental",
        "-emit-module",
        "-output-file-map", ofmA.pathString,
        "-module-name", "A",
        "-working-directory", path.pathString,
        "-c",
        a.pathString,
      ] + sdkArguments

      do {
        var driver = try TestDriver(args: aArgs)
        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
      }

      let b = path.appending(component: "b.swift")
      try localFileSystem.writeFileContents(b) {
        $0.send("import A\n")
        $0.send("public func callB() -> Int { callA() + 1 }")
      }
      let ofmB = path.appending(component: "ofmB.json")
      try localFileSystem.writeFileContents(ofmB) {
        $0.send(self.makeOutputFileMap(in: path, module: "B", for: [b]))
      }
      let bArgs = [
        "swiftc",
        "-incremental",
        "-emit-module",
        "-output-file-map", ofmB.pathString,
        "-module-name", "B",
        "-I", path.pathString,
        "-working-directory", path.pathString,
        "-c",
        b.pathString,
      ] + sdkArguments

      do {
        var driver = try TestDriver(args: bArgs)
        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
      }

      // Peek at the build-start time B just persisted, without re-running its
      // jobs (which would rewrite it). `planBuild()` alone only reads priors.
      var buildStartTime: TimePoint!
      do {
        var driver = try TestDriver(args: bArgs)
        _ = try await driver.planBuild()
        try driver.withModuleDependencyGraph { graph in
          buildStartTime = graph.buildRecord.buildStartTime
        }
      }

      // Break A's interface: `callA` no longer returns a value.
      try localFileSystem.writeFileContents(a) {
        $0.send("public func callA() {}")
      }
      do {
        var driver = try TestDriver(args: aArgs)
        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
      }

      // Simulate a coarse, whole-second-granularity filesystem: truncate A's
      // freshly rewritten swiftmodule down to the whole second containing B's
      // buildStartTime. This is <= buildStartTime whenever buildStartTime has
      // any sub-second component, i.e. virtually always.
      let aModule = path.appending(component: "A.swiftmodule")
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: TimeInterval(buildStartTime.seconds))],
        ofItemAtPath: aModule.pathString)

      // Rebuilding B must detect the now-mismatched signature and fail, not
      // silently skip recompilation because the dependency's mod time looked
      // stale.
      var driver = try TestDriver(args: bArgs)
      let jobs = try await driver.planBuild()
      await #expect(throws: (any Error).self) {
        try await driver.run(jobs: jobs)
      }
    }
  }
}
