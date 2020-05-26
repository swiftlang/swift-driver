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

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -driver-print-module-dependencies-jobs
  func testModuleDependencyBuildEndToEnd() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import C;"
        $0 <<< "import E;"
        $0 <<< "import G;"
      }

      let packageRootPath = URL(fileURLWithPath: #file).pathComponents
          .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
      let testInputsPath = packageRootPath + "/TestInputs"
      let cHeadersPath : String = testInputsPath + "/ExplicitModuleBuilds/CHeaders"
      let swiftModuleInterfacesPath : String = testInputsPath + "/ExplicitModuleBuilds/Swift"
      var driver = try Driver(args: ["swift",
                                     "-I", cHeadersPath,
                                     "-I", swiftModuleInterfacesPath,
                                     "-driver-print-module-dependencies-jobs",
                                     main.pathString])
      let jobs = try driver.generateExplicitModuleBuildJobs()
      XCTAssertEqual(jobs.count, 10)
      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        switch (job.outputs[0].file) {
          case .relative(RelativePath("A.swiftmodule")):
            XCTAssertEqual(job.kind, .emitModule)
          case .relative(RelativePath("E.swiftmodule")):
            XCTAssertEqual(job.kind, .emitModule)
          case .relative(RelativePath("G.swiftmodule")):
            XCTAssertEqual(job.kind, .emitModule)
          case .relative(RelativePath("A.pcm")):
            XCTAssertEqual(job.kind, .generatePCM)
          case .relative(RelativePath("B.pcm")):
            XCTAssertEqual(job.kind, .generatePCM)
          case .relative(RelativePath("C.pcm")):
            XCTAssertEqual(job.kind, .generatePCM)
          case .relative(RelativePath("G.pcm")):
            XCTAssertEqual(job.kind, .generatePCM)
          case .relative(RelativePath("Swift.swiftmodule")):
            XCTAssertEqual(job.kind, .emitModule)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            XCTAssertEqual(job.kind, .emitModule)
          case .relative(RelativePath("SwiftShims.pcm")):
            XCTAssertEqual(job.kind, .generatePCM)
          default:
            XCTFail("Unexpected module dependency build job output: \(job.outputs[0].file)")
        }
      }
    }
  }
}
