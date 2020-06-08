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

/// Check that an explicit module build job contains expected inputs and options
private func checkExplicitModuleBuildJob(job: Job,
                                         moduleName: String,
                                         moduleKind: ModuleDependencyId.CodingKeys,
                                         moduleDependencyGraph: InterModuleDependencyGraph) throws {
  var moduleId : ModuleDependencyId
  switch moduleKind {
    case .swift: moduleId = .swift(moduleName)
    case .clang: moduleId = .clang(moduleName)
  }
  let moduleInfo = moduleDependencyGraph.modules[moduleId]!
  switch moduleInfo.details {
    case .swift(let swiftModuleDetails):
      let moduleInterfacePath =
        TypedVirtualPath(file: try VirtualPath(path: swiftModuleDetails.moduleInterfacePath!),
                         type: .swiftInterface)
      XCTAssertEqual(job.kind, .emitModule)
      XCTAssertTrue(job.inputs.contains(moduleInterfacePath))
    case .clang(let clangModuleDetails):
      let moduleMapPath =
        TypedVirtualPath(file: try VirtualPath(path: clangModuleDetails.moduleMapPath),
                         type: .clangModuleMap)
      XCTAssertEqual(job.kind, .generatePCM)
      XCTAssertTrue(job.inputs.contains(moduleMapPath))
  }
  // Ensure the frontend was prohibited from doing implicit module builds
  XCTAssertTrue(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
  XCTAssertTrue(job.commandLine.contains(.flag(String("-fno-implicit-modules"))))
  try checkExplicitModuleBuildJobDependencies(job: job, moduleInfo: moduleInfo,
                                              moduleDependencyGraph: moduleDependencyGraph)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkExplicitModuleBuildJobDependencies(job: Job,
                                                     moduleInfo : ModuleInfo,
                                                     moduleDependencyGraph: InterModuleDependencyGraph
) throws {
  for dependencyId in moduleInfo.directDependencies {
    let dependencyInfo = moduleDependencyGraph.modules[dependencyId]!
    switch dependencyInfo.details {
      case .swift:
        let swiftDependencyModulePath =
          TypedVirtualPath(file: try VirtualPath(path: dependencyInfo.modulePath),
                           type: .swiftModule)
        XCTAssertTrue(job.inputs.contains(swiftDependencyModulePath))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-swift-module-file"))))
        XCTAssertTrue(
          job.commandLine.contains(.path(try VirtualPath(path: dependencyInfo.modulePath))))
      case .clang(let clangDependencyDetails):
        let clangDependencyModulePath =
          TypedVirtualPath(file: try VirtualPath(path: dependencyInfo.modulePath),
                           type: .pcm)
        let clangDependencyModuleMapPath =
          TypedVirtualPath(file: try VirtualPath(path: clangDependencyDetails.moduleMapPath),
                           type: .pcm)
        XCTAssertTrue(job.inputs.contains(clangDependencyModulePath))
        XCTAssertTrue(job.inputs.contains(clangDependencyModuleMapPath))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-fmodule-file=\(dependencyInfo.modulePath)"))))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-fmodule-map-file=\(clangDependencyDetails.moduleMapPath)"))))
    }

    // Ensure all transitive dependencies got added as well.
    for transitiveDependencyId in dependencyInfo.directDependencies {
      try checkExplicitModuleBuildJobDependencies(job: job,
                                                  moduleInfo: moduleDependencyGraph.modules[transitiveDependencyId]!,
                                                  moduleDependencyGraph: moduleDependencyGraph)

    }
  }
}

/// Test that for the given JSON module dependency graph, valid jobs are generated
final class ExplicitModuleBuildTests: XCTestCase {
  func testModuleDependencyBuildCommandGeneration() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-driver-print-module-dependencies-jobs",
                                     "test.swift"])
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
            try checkExplicitModuleBuildJob(job: job, moduleName: "SwiftShims",
                                            moduleKind: ModuleDependencyId.CodingKeys.clang,
                                            moduleDependencyGraph: moduleDependencyGraph)
          case .relative(RelativePath("c_simd.pcm")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "c_simd",
                                            moduleKind: ModuleDependencyId.CodingKeys.clang,
                                            moduleDependencyGraph: moduleDependencyGraph)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "Swift",
                                            moduleKind: ModuleDependencyId.CodingKeys.swift,
                                            moduleDependencyGraph: moduleDependencyGraph)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "SwiftOnoneSupport",
                                            moduleKind: ModuleDependencyId.CodingKeys.swift,
                                            moduleDependencyGraph: moduleDependencyGraph)
          default:
            XCTFail("Unexpected module dependency build job output")
        }
      }
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -experimental-explicit-module-build
  func testExplicitModuleBuildJobs() throws {
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
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath,
                                     "-I", swiftModuleInterfacesPath,
                                     "-experimental-explicit-module-build",
                                     main.pathString])
      let jobs = try driver.planBuild()
      XCTAssertTrue(driver.parsedOptions.contains(.driverExplicitModuleBuild))
      let dependencyGraph = driver.interModuleDependencyGraph!
      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        switch (job.outputs[0].file) {
          case .relative(RelativePath("A.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "A",
                                            moduleKind: ModuleDependencyId.CodingKeys.swift,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("E.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "E",
                                            moduleKind: ModuleDependencyId.CodingKeys.swift,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("G.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "G",
                                            moduleKind: ModuleDependencyId.CodingKeys.swift,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("A.pcm")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "A",
                                            moduleKind: ModuleDependencyId.CodingKeys.clang,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("B.pcm")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "B",
                                            moduleKind: ModuleDependencyId.CodingKeys.clang,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("C.pcm")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "C",
                                            moduleKind: ModuleDependencyId.CodingKeys.clang,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("G.pcm")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "G",
                                            moduleKind: ModuleDependencyId.CodingKeys.clang,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "Swift",
                                            moduleKind: ModuleDependencyId.CodingKeys.swift,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "SwiftOnoneSupport",
                                            moduleKind: ModuleDependencyId.CodingKeys.swift,
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("SwiftShims.pcm")):
            try checkExplicitModuleBuildJob(job: job, moduleName: "SwiftShims",
                                            moduleKind: ModuleDependencyId.CodingKeys.clang,
                                            moduleDependencyGraph: dependencyGraph)
          case .temporary(RelativePath("main.o")):
            try checkExplicitModuleBuildJobDependencies(job: job,
                                                        moduleInfo: dependencyGraph.mainModule,
                                                        moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("main")):
            XCTAssertEqual(job.kind, .link)
          default:
            XCTFail("Unexpected module dependency build job output: \(job.outputs[0].file)")
        }
      }
    }
  }
}
