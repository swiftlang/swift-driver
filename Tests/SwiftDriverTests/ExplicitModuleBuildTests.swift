//===------- ExplicitModuleBuildTests.swift - Swift Driver Tests ----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@testable import SwiftDriver
import TSCBasic
import XCTest

/// Test that for the given JSON module dependency graph, valid jobs are generated
final class ExplicitModuleBuildTests: XCTestCase {
  func testModuleDependencyBuildCommandGeneration() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-driver-print-module-dependencies-jobs", "test.swift"])
      let moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerOutput.data(using: .utf8)!)
      let modulePrebuildJobs =
            try driver.planExplicitModuleDependenciesCompile(dependencyGraph: moduleDependencyGraph)
      XCTAssertEqual(modulePrebuildJobs.count, 4)
      for job in modulePrebuildJobs {
        XCTAssertEqual(job.outputs.count, 1)
        switch (job.outputs[0].file) {
          case .relative(RelativePath("SwiftShims.pcm")):
            XCTAssertEqual(job.kind, .generatePCM)
            XCTAssertEqual(job.inputs.count, 1)
            XCTAssertTrue(job.inputs[0].file.absolutePath!.pathString.contains("swift/shims/module.modulemap"))
          case .relative(RelativePath("c_simd.pcm")):
            XCTAssertEqual(job.kind, .generatePCM)
            XCTAssertEqual(job.inputs.count, 1)
            XCTAssertTrue(job.inputs[0].file.absolutePath!.pathString.contains("clang-importer-sdk/usr/include/module.map"))
          case .relative(RelativePath("Swift.swiftmodule")):
            XCTAssertEqual(job.kind, .emitModule)
            XCTAssertEqual(job.inputs.count, 1)
            XCTAssertTrue(job.inputs[0].file.absolutePath!.pathString.contains("Swift.swiftmodule/x86_64-apple-macos.swiftinterface"))
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            XCTAssertEqual(job.kind, .emitModule)
            XCTAssertEqual(job.inputs.count, 1)
            XCTAssertTrue(job.inputs[0].file.absolutePath!.pathString.contains("SwiftOnoneSupport.swiftmodule/x86_64-apple-macos.swiftinterface"))
          default:
            XCTFail("Unexpected module dependency build job output")
        }
      }
    }
  }


}
