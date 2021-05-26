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
    for files: [AbsolutePath],
    outputTransform transform: (String) -> String = { $0 }
  ) -> String {
    """
    {
      "": {
        "swift-dependencies": "\(workingDirectory.appending(component: "module.swiftdeps"))"
      }
    """.appending(files.map { file in
      """
      ,
      "\(file)": {
        "dependencies": "\(transform(file.basenameWithoutExt) + ".d")",
        "object": "\(transform(file.pathString) + ".o")",
        "swiftmodule": "\(transform(file.basenameWithoutExt) + "~partial.swiftmodule")",
        "swift-dependencies": "\(transform(file.basenameWithoutExt) + ".swiftdeps")"
        }
      """
    }.joined(separator: "\n").appending("\n}"))
  }

  func testChangingOutputFileMap() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let magic = path.appending(component: "magic.swift")
      try localFileSystem.writeFileContents(magic) {
        $0 <<< "public func castASpell() {}"
      }

      let ofm = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofm) {
        $0 <<< self.makeOutputFileMap(in: path, for: [ magic ]) {
          $0 + "-some_suffix"
        }
      }

      do {
        var driver = try Driver(args: [
          "swiftc",
          "-incremental",
          "-emit-module",
          "-output-file-map", ofm.pathString,
          "-module-name", "MagicKit",
          "-working-directory", path.pathString,
          "-c",
          magic.pathString,
        ])
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }

      try localFileSystem.writeFileContents(ofm) {
        $0 <<< self.makeOutputFileMap(in: path, for: [ magic ]) {
          $0 + "-some_other_suffix"
        }
      }

      do {
        var driver = try Driver(args: [
          "swiftc",
          "-incremental",
          "-emit-module",
          "-output-file-map", ofm.pathString,
          "-module-name", "MagicKit",
          "-working-directory", path.pathString,
          "-c",
          magic.pathString,
        ])
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }
    }
  }

  func testEmbeddedModuleDependencies() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      do {
        let magic = path.appending(component: "magic.swift")
        try localFileSystem.writeFileContents(magic) {
          $0 <<< "public func castASpell() {}"
        }

        let ofm = path.appending(component: "ofm.json")
        try localFileSystem.writeFileContents(ofm) {
          $0 <<< self.makeOutputFileMap(in: path, for: [ magic ])
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
        ])
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }

      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import MagicKit\n"
        $0 <<< "castASpell()"
      }

      let ofm = path.appending(component: "ofm2.json")
      try localFileSystem.writeFileContents(ofm) {
        $0 <<< self.makeOutputFileMap(in: path, for: [ main ])
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
      ])

      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)

      let sourcePath = path.appending(component: "main.swiftdeps")
      let data = try localFileSystem.readFileContents(sourcePath)
      let graph = try XCTUnwrap(SourceFileDependencyGraph(data: data,
                                                          from: DependencySource(VirtualPath.absolute(sourcePath).intern())!,
                                                          fromSwiftModule: false))
      XCTAssertEqual(graph.majorVersion, 1)
      XCTAssertEqual(graph.minorVersion, 0)
      graph.verify()

      var foundNode = false
      let swiftmodulePath = ExternalDependency(fileName: path.appending(component: "MagicKit.swiftmodule").pathString)
      graph.forEachNode { node in
        if case .externalDepend(swiftmodulePath) = node.key.designator {
          XCTAssertFalse(foundNode)
          foundNode = true
          XCTAssertEqual(node.key.aspect, .interface)
          XCTAssertTrue(node.defsIDependUpon.isEmpty)
          XCTAssertFalse(node.isProvides)
        }
      }
      XCTAssertTrue(foundNode)
    }
  }
}
