//===----- APIDigesterTests.swift - API/ABI Digester Operation Tests ------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import TSCBasic
@_spi(Testing) import SwiftDriver

class APIDigesterTests: XCTestCase {
  func testBaselineGenerationRequiresTopLevelModule() throws {
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-emit-api-baseline"]) {
      $1.expect(.error("generating a baseline with '-emit-api-baseline' is only supported with '-emit-module' or '-emit-module-path"))
    }
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-emit-abi-baseline-path", "/output/path.abi.json"]) {
      $1.expect(.error("generating a baseline with '-emit-abi-baseline-path' is only supported with '-emit-module' or '-emit-module-path"))
    }
  }

  func testBaselineOutputPath() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-emit-api-baseline"])
      let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateAPIBaseline })
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.relative(.init("foo.api.json")))]))
    }
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-emit-abi-baseline"])
      let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateABIBaseline })
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.relative(.init("foo.abi.json")))]))
    }
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-emit-api-baseline-path", "bar.api.json"])
      let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateAPIBaseline })
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.relative(.init("bar.api.json")))]))
    }
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-emit-abi-baseline-path", "bar.abi.json"])
      let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateABIBaseline })
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.relative(.init("bar.abi.json")))]))
    }
    do {
      try withTemporaryDirectory { path in
        let projectDirPath = path.appending(component: "Project")
        try localFileSystem.createDirectory(projectDirPath)
        var driver = try Driver(args: ["swiftc", "-emit-module",
                                       path.appending(component: "foo.swift").pathString,
                                       "-emit-api-baseline",
                                       "-o", path.appending(component: "foo.swiftmodule").pathString])
        let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateAPIBaseline })
        XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.absolute(projectDirPath.appending(component: "foo.api.json")))]))
      }
    }
    do {
      try withTemporaryDirectory { path in
        let projectDirPath = path.appending(component: "Project")
        try localFileSystem.createDirectory(projectDirPath)
        var driver = try Driver(args: ["swiftc", "-emit-module",
                                       path.appending(component: "foo.swift").pathString,
                                       "-emit-abi-baseline",
                                       "-o", path.appending(component: "foo.swiftmodule").pathString])
        let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateABIBaseline })
        XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.absolute(projectDirPath.appending(component: "foo.abi.json")))]))
      }
    }

  }

  func testBaselineGenerationJobFlags() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-emit-api-baseline",
                                     "-sdk", "/path/to/sdk", "-I", "/some/path", "-F", "framework/path"])
      let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateAPIBaseline })
      XCTAssertTrue(digesterJob.commandLine.contains("-dump-sdk"))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-module", "foo"]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-I", .path(.relative(.init(".")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-sdk", .path(.absolute(.init("/path/to/sdk")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-I", .path(.absolute(.init("/some/path")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-F", .path(.relative(.init("framework/path")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.relative(.init("foo.api.json")))]))

      XCTAssertFalse(digesterJob.commandLine.contains("-abi"))
    }
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-emit-abi-baseline",
                                     "-sdk", "/path/to/sdk", "-I", "/some/path", "-F", "framework/path"])
      let digesterJob = try XCTUnwrap(driver.planBuild().first { $0.kind == .generateABIBaseline })
      XCTAssertTrue(digesterJob.commandLine.contains("-dump-sdk"))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-module", "foo"]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-I", .path(.relative(.init(".")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-sdk", .path(.absolute(.init("/path/to/sdk")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-I", .path(.absolute(.init("/some/path")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-F", .path(.relative(.init("framework/path")))]))
      XCTAssertTrue(digesterJob.commandLine.contains(subsequence: ["-o", .path(.relative(.init("foo.abi.json")))]))

      XCTAssertTrue(digesterJob.commandLine.contains("-abi"))
    }
  }

  func testBaselineGenerationEndToEnd() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let source = path.appending(component: "foo.swift")
      try localFileSystem.writeFileContents(source) {
        $0 <<< """
        import C
        import E
        import G

        public struct MyStruct {}
        """
      }

      let packageRootPath = URL(fileURLWithPath: #file).pathComponents
          .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
      let testInputsPath = packageRootPath + "/TestInputs"
      let cHeadersPath : String = testInputsPath + "/ExplicitModuleBuilds/CHeaders"
      let swiftModuleInterfacesPath : String = testInputsPath + "/ExplicitModuleBuilds/Swift"
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath,
                                     "-I", swiftModuleInterfacesPath,
                                     "-working-directory", path.pathString,
                                     source.pathString,
                                     "-emit-module",
                                     "-emit-api-baseline",
                                    ],
                              env: ProcessEnv.vars)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      let baseline = try localFileSystem.readFileContents(path.appending(component: "foo.api.json"))
      try baseline.withData {
        let json = try JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any]
        XCTAssertEqual((json?["children"] as? [Any])?.count, 1)
      }
    }
  }
}
