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
import SwiftDriver
import TSCBasic
import XCTest

/// Check that an explicit module build job contains expected inputs and options
private func checkExplicitModuleBuildJob(job: Job,
                                         moduleId: ModuleDependencyId,
                                         moduleDependencyGraph: InterModuleDependencyGraph) throws {
  let moduleInfo = moduleDependencyGraph.modules[moduleId]!
  var pcmArgs: [String] = []
  switch moduleInfo.details {
    case .swift(let swiftModuleDetails):
      pcmArgs = swiftModuleDetails.extraPcmArgs!
      let moduleInterfacePath =
        TypedVirtualPath(file: try VirtualPath(path: swiftModuleDetails.moduleInterfacePath!),
                         type: .swiftInterface)
      XCTAssertEqual(job.kind, .emitModule)
      XCTAssertTrue(job.inputs.contains(moduleInterfacePath))
    case .clang(let clangModuleDetails):
      guard case .swift(let mainModuleSwiftDetails) = moduleDependencyGraph.mainModule.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }
      pcmArgs = mainModuleSwiftDetails.extraPcmArgs!
      let moduleMapPath =
        TypedVirtualPath(file: try VirtualPath(path: clangModuleDetails.moduleMapPath),
                         type: .clangModuleMap)
      XCTAssertEqual(job.kind, .generatePCM)
      XCTAssertTrue(job.inputs.contains(moduleMapPath))
  }
  // Ensure the frontend was prohibited from doing implicit module builds
  XCTAssertTrue(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
  XCTAssertTrue(job.commandLine.contains(.flag(String("-fno-implicit-modules"))))
  try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: pcmArgs, moduleInfo: moduleInfo,
                                              moduleDependencyGraph: moduleDependencyGraph)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkExplicitModuleBuildJobDependencies(job: Job,
                                                     pcmArgs: [String],
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
        let clangDependencyModulePathString =
          try ExplicitModuleBuildHandler.targetEncodedClangModuleFilePath(
          for: dependencyInfo, pcmArgs: pcmArgs)
        let clangDependencyModulePath =
          TypedVirtualPath(file: clangDependencyModulePathString, type: .pcm)
        let clangDependencyModuleMapPath =
          TypedVirtualPath(file: try VirtualPath(path: clangDependencyDetails.moduleMapPath),
                           type: .clangModuleMap)
        XCTAssertTrue(job.inputs.contains(clangDependencyModulePath))
        XCTAssertTrue(job.inputs.contains(clangDependencyModuleMapPath))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-fmodule-file=\(clangDependencyModulePathString)"))))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-fmodule-map-file=\(clangDependencyDetails.moduleMapPath)"))))
    }

    // Ensure all transitive dependencies got added as well.
    for transitiveDependencyId in dependencyInfo.directDependencies {
      try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: pcmArgs, 
                                                  moduleInfo: moduleDependencyGraph.modules[transitiveDependencyId]!,
                                                  moduleDependencyGraph: moduleDependencyGraph)

    }
  }
}

private func pcmArgsEncodedRelativeModulePath(for moduleName: String, with pcmArgs: [String]
) throws -> RelativePath {
  return RelativePath(
    try ExplicitModuleBuildHandler.targetEncodedClangModuleName(for: moduleName,
                                                                pcmArgs: pcmArgs) + ".pcm")
}

/// Test that for the given JSON module dependency graph, valid jobs are generated
final class ExplicitModuleBuildTests: XCTestCase {
  func testModuleDependencyBuildCommandGeneration() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-driver-print-module-dependencies-jobs",
                                     "test.swift"])
      let pcmArgs = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.15"]
      let moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerOutput.data(using: .utf8)!)
      driver.explicitModuleBuildHandler = try ExplicitModuleBuildHandler(dependencyGraph: moduleDependencyGraph,
                                                                         toolchain: driver.toolchain)
      let modulePrebuildJobs =
        try driver.explicitModuleBuildHandler!.generateExplicitModuleDependenciesBuildJobs()
      XCTAssertEqual(modulePrebuildJobs.count, 4)
      for job in modulePrebuildJobs {
        XCTAssertEqual(job.outputs.count, 1)
        switch (job.outputs[0].file) {

          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                            moduleDependencyGraph: moduleDependencyGraph)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "c_simd", with: pcmArgs)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("c_simd"),
                                            moduleDependencyGraph: moduleDependencyGraph)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("Swift"),
                                            moduleDependencyGraph: moduleDependencyGraph)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                            moduleDependencyGraph: moduleDependencyGraph)
          default:
            XCTFail("Unexpected module dependency build job output: \(job.outputs[0].file)")
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
      // Figure out which Triples to use.
      let dependencyGraph = driver.explicitModuleBuildHandler!.dependencyGraph
      guard case .swift(let mainModuleSwiftDetails) = dependencyGraph.mainModule.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }
      let pcmArgsCurrent = mainModuleSwiftDetails.extraPcmArgs!
      var pcmArgs9 = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.9"]
      if driver.targetTriple.isDarwin {
        pcmArgs9.append(contentsOf: ["-Xcc", "-fapinotes-swift-version=5"])
      }
      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        switch (job.outputs[0].file) {
          case .relative(RelativePath("A.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("A"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("E.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("E"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("G.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("G"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("Swift"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "A", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("A"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "B", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("B"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "C", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("C"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "G", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("G"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs9)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                            moduleDependencyGraph: dependencyGraph)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                            moduleDependencyGraph: dependencyGraph)
          case .temporary(RelativePath("main.o")):
            guard case .swift(let mainModuleSwiftDetails) = dependencyGraph.mainModule.details else {
              XCTFail("Main module does not have Swift details field")
              return
            }
            let pcmArgs = mainModuleSwiftDetails.extraPcmArgs!
            try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: pcmArgs,
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

  func testExplicitModuleBuildEndToEnd() throws {
    // The macOS-only restriction is temporary while Clang's dependency scanner
    // is gaining the ability to perform name-based module lookup.
    #if os(macOS)
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
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
                                     "-working-directory", path.pathString,
                                     main.pathString])
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
    }
    #endif
  }
}
