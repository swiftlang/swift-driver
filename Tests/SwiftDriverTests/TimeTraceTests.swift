//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
@testable @_spi(Testing) import SwiftDriver
import TSCBasic
import TestUtilities
import XCTest

private var testInputsPath: AbsolutePath {
  get throws {
    var root: AbsolutePath = try AbsolutePath(validating: #file)
    while root.basename != "Tests" {
      root = root.parentDirectory
    }
    return root.parentDirectory.appending(component: "TestInputs")
  }
}

final class TimeTraceTests: XCTestCase {
  func testTimeTraceJSONFormat() throws {
    let trace = TimeTrace()
    let _ = trace.measure("TestEvent") { 42 }
    try withTemporaryDirectory { dir in
      let path = dir.appending(component: "trace.json").pathString
      try trace.write(to: path)
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      XCTAssertNotNil(json["beginningOfTime"] as? Int)
      let events = json["traceEvents"] as! [[String: Any]]
      XCTAssertTrue(events.contains { $0["name"] as? String == "TestEvent" && $0["ph"] as? String == "X" })
      XCTAssertTrue(events.contains { $0["name"] as? String == "process_name" })
    }
  }

  func testTimeTraceDriverProperty() throws {
    var driver1 = try Driver(args: ["swiftc", "-c", "-ftime-trace", "foo.swift"])
    XCTAssertNotNil(driver1.timeTrace)
    var driver2 = try Driver(args: ["swiftc", "-c", "foo.swift"])
    XCTAssertNil(driver2.timeTrace)
  }

  func testTimeTracePlanBuild() throws {
    var driver = try Driver(args: ["swiftc", "-c", "-ftime-trace", "foo.swift"])
    let _ = try driver.planBuild()
    XCTAssertTrue(driver.timeTrace!.hasEvent(named: "Plan Build"))
  }

  func testTimeTracePlanSubPhases() throws {
    var driver = try Driver(args: ["swiftc", "-c", "-ftime-trace", "foo.swift"])
    let _ = try driver.planBuild()
    XCTAssertTrue(driver.timeTrace!.hasEvent(named: "Compute Jobs"))
  }

  func testTimeTraceFileWritten() throws {
    try withTemporaryDirectory { dir in
      let tracePath = dir.appending(component: "foo.time-trace.json")
      var driver = try Driver(args: [
        "swiftc", "-c", "-ftime-trace",
        "-ftime-trace-path", tracePath.pathString,
        "foo.swift"
      ])
      let jobs = try driver.planBuild()
      // We can't actually execute jobs without a real compiler, but we can
      // verify that writeDriverTimeTrace produces a file.
      try driver.writeDriverTimeTrace()

      let driverTracePath = dir.appending(component: "foo.driver.time-trace.json")
      XCTAssertTrue(localFileSystem.exists(driverTracePath),
                    "Driver time trace file should exist at \(driverTracePath)")
      let data = try localFileSystem.readFileContents(driverTracePath)
      try data.withData { data in
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["beginningOfTime"] as? Int)
        let events = json["traceEvents"] as! [[String: Any]]
        XCTAssertTrue(events.contains { $0["name"] as? String == "Plan Build" })
      }
    }
  }

  func testTimeTraceExplicitModuleJobs() throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testTimeTraceExplicitModuleJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;import E;import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-ftime-trace",
                                     "-disable-implicit-concurrency-module-import",
                                     "-disable-implicit-string-processing-module-import",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()
      let interfaceJobs = jobs.filter { $0.kind == .compileModuleFromInterface }
      XCTAssertFalse(interfaceJobs.isEmpty,
                     "Expected at least one .compileModuleFromInterface job")

      for job in interfaceJobs {
        XCTAssertTrue(
          job.commandLine.contains(.flag("-ftime-trace")),
          "Expected -ftime-trace in \(job.moduleName) compileModuleFromInterface job command line"
        )
      }
    }
  }
}
