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
@_spi(Testing) import SwiftDriver
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
      if let compiledCandidateList = swiftModuleDetails.compiledModuleCandidates {
        for compiledCandidate in compiledCandidateList {
          let candidatePath = try VirtualPath(path: compiledCandidate)
          let typedCandidatePath = TypedVirtualPath(file: candidatePath,
                                                    type: .swiftModule)
          XCTAssertTrue(job.inputs.contains(typedCandidatePath))
          XCTAssertTrue(job.commandLine.contains(.path(candidatePath)))
        }
        XCTAssertTrue(job.commandLine.filter {$0 == .flag("-candidate-module-file")}.count == compiledCandidateList.count)
      }
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
    case .swiftPlaceholder(_):
      XCTFail("Placeholder dependency found.")
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
  for dependencyId in moduleInfo.directDependencies! {
    let dependencyInfo = moduleDependencyGraph.modules[dependencyId]!
    switch dependencyInfo.details {
      case .swift(let swiftDetails):
        // Load the dependency JSON and verify this dependency was encoded correctly
        let explicitDepsFlag =
          SwiftDriver.Job.ArgTemplate.flag(String("-explicit-swift-module-map-file"))
        XCTAssert(job.commandLine.contains(explicitDepsFlag))
        let jsonDepsPathIndex = job.commandLine.firstIndex(of: explicitDepsFlag)
        let jsonDepsPathArg = job.commandLine[jsonDepsPathIndex! + 1]
        guard case .path(let jsonDepsPath) = jsonDepsPathArg else {
          XCTFail("No JSON dependency file path found.")
          return
        }
        let contents =
          try localFileSystem.readFileContents(jsonDepsPath.absolutePath!)
        let dependencyInfoList = try JSONDecoder().decode(Array<SwiftModuleArtifactInfo>.self,
                                                      from: Data(contents.contents))
        let dependencyArtifacts =
          dependencyInfoList.first(where:{ $0.moduleName == dependencyId.moduleName })
        XCTAssertEqual(dependencyArtifacts!.modulePath, swiftDetails.explicitCompiledModulePath ?? dependencyInfo.modulePath)
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
      case .swiftPlaceholder(_):
        XCTFail("Placeholder dependency found.")
    }

    // Ensure all transitive dependencies got added as well.
    for transitiveDependencyId in dependencyInfo.directDependencies! {
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
                                                                         toolchain: driver.toolchain,
                                                                         fileSystem: localFileSystem,
                                                                         externalDependencyArtifactMap: [:])
      let modulePrebuildJobs =
        try driver.explicitModuleBuildHandler!.generateExplicitModuleDependenciesBuildJobs()
      XCTAssertEqual(modulePrebuildJobs.count, 4)
      for job in modulePrebuildJobs {
        XCTAssertEqual(job.outputs.count, 1)
        XCTAssertFalse(driver.isExplicitMainModuleJob(job: job))
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

  func testModuleDependencyWithExternalCommandGeneration() throws {
    do {
      // Construct a faux external dependency input for module B
      let inputDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.bPlaceHolderInput.data(using: .utf8)!)
      var targetDependencyMap :[ModuleDependencyId: (AbsolutePath, InterModuleDependencyGraph)] = [:]
      targetDependencyMap[ModuleDependencyId.swiftPlaceholder("B")] =
        (AbsolutePath("/Somewhere/B.swiftmodule"), inputDependencyGraph)

      // Construct a module dependency graph that will contain .swiftPlaceholder("B")
      let moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerPlaceholderOutput.data(using: .utf8)!)

      // Construct the driver with explicit external dependency input
      var commandLine = ["swiftc", "-driver-print-module-dependencies-jobs",
                         "test.swift", "-module-name", "A", "-g"]
      commandLine.append("-experimental-explicit-module-build")
      let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
                                             processSet: ProcessSet(),
                                             fileSystem: localFileSystem,
                                             env: ProcessEnv.vars)
      var driver = try Driver(args: commandLine, executor: executor,
                              externalModuleDependencies: targetDependencyMap)


      // Plan explicit dependency jobs, resolving placeholders to actual dependencies.
      driver.explicitModuleBuildHandler = try ExplicitModuleBuildHandler(dependencyGraph: moduleDependencyGraph,
                                                                         toolchain: driver.toolchain,
                                                                         fileSystem: localFileSystem,
                                                                         externalDependencyArtifactMap: targetDependencyMap)
      let modulePrebuildJobs =
        try driver.explicitModuleBuildHandler!.generateExplicitModuleDependenciesBuildJobs()

      // Verify that the dependency graph contains only 1 module to be built.
      for (moduleId, _) in driver.interModuleDependencyGraph!.modules {
        switch moduleId {
          case .swift(_):
            continue
          case .clang(_):
            continue
          case .swiftPlaceholder(_):
            XCTFail("Placeholder dependency found.")
        }
      }

      // After module resolution all the dependencies are already satisfied.
      XCTAssertEqual(modulePrebuildJobs.count, 0)
      let mainModuleJob = try driver.emitModuleJob()
      XCTAssertEqual(mainModuleJob.inputs.count, 5)
      for input in mainModuleJob.inputs {
        switch (input.file) {
          case .relative(RelativePath("M/Swift.swiftmodule")):
            continue
          case .relative(RelativePath("S/SwiftOnoneSupport.swiftmodule")):
            continue
          case .relative(RelativePath("test.swift")):
            continue
          case .absolute(AbsolutePath("/Somewhere/B.swiftmodule")):
            continue
          case .absolute(let filePath):
            XCTAssertEqual(filePath.basename, "A-dependencies.json")
            continue
          default:
            XCTFail("Unexpected module input: \(input.file)")
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
            XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
            guard case .swift(let mainModuleSwiftDetails) = dependencyGraph.mainModule.details else {
              XCTFail("Main module does not have Swift details field")
              return
            }
            let pcmArgs = mainModuleSwiftDetails.extraPcmArgs!
            try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: pcmArgs,
                                                        moduleInfo: dependencyGraph.mainModule,
                                                        moduleDependencyGraph: dependencyGraph)
          case .relative(RelativePath("main")):
            XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
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
                                     main.pathString],
                              env: ProcessEnv.vars)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
    }
    #endif
  }

  func testExplicitSwiftModuleMap() throws {
    let jsonExample : String = """
    [
      {
        "moduleName": "A",
        "modulePath": "A.swiftmodule",
        "docPath": "A.swiftdoc",
        "sourceInfoPath": "A.swiftsourceinfo"
      },
      {
        "moduleName": "B",
        "modulePath": "B.swiftmodule",
        "docPath": "B.swiftdoc",
        "sourceInfoPath": "B.swiftsourceinfo"
      }
    ]
    """
    let moduleMap = try JSONDecoder().decode(Array<SwiftModuleArtifactInfo>.self,
                                             from: jsonExample.data(using: .utf8)!)
    XCTAssertEqual(moduleMap.count, 2)
    XCTAssertEqual(moduleMap[0].moduleName, "A")
    XCTAssertEqual(moduleMap[0].modulePath, "A.swiftmodule")
    XCTAssertEqual(moduleMap[0].docPath, "A.swiftdoc")
    XCTAssertEqual(moduleMap[0].sourceInfoPath, "A.swiftsourceinfo")
    XCTAssertEqual(moduleMap[1].moduleName, "B")
    XCTAssertEqual(moduleMap[1].modulePath, "B.swiftmodule")
    XCTAssertEqual(moduleMap[1].docPath, "B.swiftdoc")
    XCTAssertEqual(moduleMap[1].sourceInfoPath, "B.swiftsourceinfo")
  }
}
