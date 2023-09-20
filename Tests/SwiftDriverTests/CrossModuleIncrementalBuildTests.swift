//===---------- CrossModuleIncrementalBuildTests.swift - Swift Testing ----===//
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
import XCTest
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

class CrossModuleIncrementalBuildTests: XCTestCase {
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
    """.appending(files.map { file in
      """
      ,
      "\(file.nativePathString(escaped: true))": {
        "dependencies": "\(transform(file.basenameWithoutExt) + ".d")",
        "object": "\(transform(file.nativePathString(escaped: true)) + ".o")",
        "swiftmodule": "\(transform(file.basenameWithoutExt) + "~partial.swiftmodule")",
        "swift-dependencies": "\(transform(file.basenameWithoutExt) + ".swiftdeps")"
        }
      """
    }.joined(separator: "\n").appending("\n}"))
  }

  func testChangingOutputFileMap() throws {
    guard let sdkArguments = try Driver.sdkArgumentsForTesting() else {
      throw XCTSkip()
    }
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let magic = path.appending(component: "magic.swift")
      try localFileSystem.writeFileContents(magic) {
        $0.send("public func castASpell() {}")
      }

      let ofm = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofm) {
        $0.send(self.makeOutputFileMap(in: path, module: "MagicKit", for: [ magic ]) {
          $0 + "-some_suffix"
        })
      }

      let driverArgs = [
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
        var driver = try Driver(args: driverArgs)
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }

      try localFileSystem.writeFileContents(ofm) {
        $0.send(self.makeOutputFileMap(in: path, module: "MagicKit", for: [ magic ]) {
          $0 + "-some_other_suffix"
        })
      }

      do {
        var driver = try Driver(args: driverArgs)
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }
    }
  }

  func testEmbeddedModuleDependencies() throws {
    guard let sdkArguments = try Driver.sdkArgumentsForTesting() else {
      throw XCTSkip()
    }
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      do {
        let magic = path.appending(component: "magic.swift")
        try localFileSystem.writeFileContents(magic) {
          $0.send("public func castASpell() {}")
        }

        let ofm = path.appending(component: "ofm.json")
        try localFileSystem.writeFileContents(ofm) {
          $0.send(self.makeOutputFileMap(in: path, module: "MagicKit", for: [ magic ]))
        }

        var driver = try Driver(args: [
          "swiftc",
          "-incremental",
          "-emit-module",
          "-output-file-map", ofm.pathString,
          "-module-name", "MagicKit",
          "-working-directory", path.pathString,
          "-c",
          magic.pathString,
        ] + sdkArguments)
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }

      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import MagicKit\n")
        $0.send("castASpell()")
      }

      let ofm = path.appending(component: "ofm2.json")
      try localFileSystem.writeFileContents(ofm) {
        $0.send(self.makeOutputFileMap(in: path, module: "theModule", for: [ main ]))
      }

      var driver = try Driver(args: [
        "swiftc",
        "-incremental",
        "-emit-module",
        "-output-file-map", ofm.pathString,
        "-module-name", "theModule",
        "-I", path.pathString,
        "-working-directory", path.pathString,
        "-c",
        main.pathString,
      ] + sdkArguments)

      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)

      let sourcePath = path.appending(component: "main.swiftdeps")
      let data = try localFileSystem.readFileContents(sourcePath)
      try driver.withModuleDependencyGraph { host in
        let testGraph = try XCTUnwrap(SourceFileDependencyGraph(
          internedStringTable: host.internedStringTable,
          data: data,
          fromSwiftModule: false))
        XCTAssertEqual(testGraph.majorVersion, 1)
        XCTAssertEqual(testGraph.minorVersion, 0)
        testGraph.verify()

        var foundNode = false
        let swiftmodulePath = ExternalDependency(
          fileName: path.appending(component: "MagicKit.swiftmodule")
            .pathString.intern(in: host),
          host.internedStringTable)
        testGraph.forEachNode { node in
          if case .externalDepend(swiftmodulePath) = node.key.designator {
            XCTAssertFalse(foundNode)
            foundNode = true
            XCTAssertEqual(node.key.aspect, .interface)
            XCTAssertTrue(node.defsIDependUpon.isEmpty)
            XCTAssertEqual(node.definitionVsUse, .use)
          }
        }
        XCTAssertTrue(foundNode)
      }
    }
  }
}
