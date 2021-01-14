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
import SwiftDriverExecution
import TSCBasic
import XCTest

/// Check that an explicit module build job contains expected inputs and options
private func checkExplicitModuleBuildJob(job: Job,
                                         pcmArgs: [String],
                                         moduleId: ModuleDependencyId,
                                         dependencyOracle: InterModuleDependencyOracle) throws {
  let moduleInfo = dependencyOracle.getExternalModuleInfo(of: moduleId)!
  var downstreamPCMArgs = pcmArgs
  switch moduleInfo.details {
    case .swift(let swiftModuleDetails):
      downstreamPCMArgs = swiftModuleDetails.extraPcmArgs
      let moduleInterfacePath =
        TypedVirtualPath(file: swiftModuleDetails.moduleInterfacePath!.path,
                         type: .swiftInterface)
      XCTAssertEqual(job.kind, .emitModule)
      XCTAssertTrue(job.inputs.contains(moduleInterfacePath))
      if let compiledCandidateList = swiftModuleDetails.compiledModuleCandidates {
        for compiledCandidate in compiledCandidateList {
          let candidatePath = compiledCandidate.path
          let typedCandidatePath = TypedVirtualPath(file: candidatePath,
                                                    type: .swiftModule)
          XCTAssertTrue(job.inputs.contains(typedCandidatePath))
          XCTAssertTrue(job.commandLine.contains(.path(candidatePath)))
        }
        XCTAssertTrue(job.commandLine.filter {$0 == .flag("-candidate-module-file")}.count == compiledCandidateList.count)
      }
    case .clang(let clangModuleDetails):
      let moduleMapPath =
        TypedVirtualPath(file: clangModuleDetails.moduleMapPath.path,
                         type: .clangModuleMap)
      XCTAssertEqual(job.kind, .generatePCM)
      XCTAssertEqual(job.description, "Compiling Clang module \(moduleId.moduleName)")
      XCTAssertTrue(job.inputs.contains(moduleMapPath))
    case .swiftPrebuiltExternal(_):
      XCTFail("Unexpected prebuilt external module dependency found.")
    case .swiftPlaceholder(_):
      XCTFail("Placeholder dependency found.")
  }
  // Ensure the frontend was prohibited from doing implicit module builds
  XCTAssertTrue(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
  XCTAssertTrue(job.commandLine.contains(.flag(String("-fno-implicit-modules"))))
  try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: downstreamPCMArgs,
                                              moduleInfo: moduleInfo,
                                              dependencyOracle: dependencyOracle)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkExplicitModuleBuildJobDependencies(job: Job,
                                                     pcmArgs: [String],
                                                     moduleInfo : ModuleInfo,
                                                     dependencyOracle: InterModuleDependencyOracle
) throws {
  for dependencyId in moduleInfo.directDependencies! {
    let dependencyInfo = dependencyOracle.getExternalModuleInfo(of: dependencyId)!
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
        guard case let .temporaryWithKnownContents(_, contents) = jsonDepsPath else {
          XCTFail("Unexpected path type")
          return
        }
        let dependencyInfoList = try JSONDecoder().decode(Array<SwiftModuleArtifactInfo>.self,
                                                      from: contents)
        let dependencyArtifacts =
          dependencyInfoList.first(where:{ $0.moduleName == dependencyId.moduleName })
        XCTAssertEqual(dependencyArtifacts!.modulePath, dependencyInfo.modulePath)
        XCTAssertEqual(dependencyArtifacts!.isFramework, swiftDetails.isFramework)
      case .swiftPrebuiltExternal(let prebuiltModuleDetails):
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
        XCTAssertEqual(dependencyArtifacts!.modulePath,
                       prebuiltModuleDetails.compiledModulePath)
      case .clang(let clangDependencyDetails):
        let clangDependencyModulePathString =
          try ExplicitDependencyBuildPlanner.targetEncodedClangModuleFilePath(
          for: dependencyInfo, hashParts: pcmArgs)
        let clangDependencyModulePath =
          TypedVirtualPath(file: clangDependencyModulePathString, type: .pcm)
        let clangDependencyModuleMapPath =
          TypedVirtualPath(file: clangDependencyDetails.moduleMapPath.path,
                           type: .clangModuleMap)

        XCTAssertTrue(job.inputs.contains(clangDependencyModulePath))
        XCTAssertTrue(job.inputs.contains(clangDependencyModuleMapPath))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-fmodule-file=\(clangDependencyModulePathString)"))))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-fmodule-map-file=\(clangDependencyDetails.moduleMapPath.path.description)"))))
      case .swiftPlaceholder(_):
        XCTFail("Placeholder dependency found.")
    }

    // Ensure all transitive dependencies got added as well.
    for transitiveDependencyId in dependencyInfo.directDependencies! {
      try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: pcmArgs, 
                                                  moduleInfo: dependencyOracle.getExternalModuleInfo(of: transitiveDependencyId)!,
                                                  dependencyOracle: dependencyOracle)

    }
  }
}

private func pcmArgsEncodedRelativeModulePath(for moduleName: String, with pcmArgs: [String]
) throws -> RelativePath {
  return RelativePath(
    try ExplicitDependencyBuildPlanner.targetEncodedClangModuleName(for: moduleName,
                                                                hashParts: pcmArgs) + ".pcm")
}

/// Test that for the given JSON module dependency graph, valid jobs are generated
final class ExplicitModuleBuildTests: XCTestCase {
  func testModuleDependencyBuildCommandGeneration() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-experimental-explicit-module-build",
                                     "-module-name", "testModuleDependencyBuildCommandGeneration",
                                     "test.swift"])
      let pcmArgs = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.15"]
      let moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerOutput.data(using: .utf8)!)
      let toolchainRootPath: AbsolutePath = try driver.toolchain.getToolPath(.swiftCompiler)
                                                              .parentDirectory // bin
                                                              .parentDirectory // toolchain root
      let dependencyOracle = InterModuleDependencyOracle()
      try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                         toolchainPath: toolchainRootPath)
      try dependencyOracle.mergeModules(from: moduleDependencyGraph)
      driver.explicitDependencyBuildPlanner =
        try ExplicitDependencyBuildPlanner(dependencyGraph: moduleDependencyGraph,
                                           toolchain: driver.toolchain)
      let modulePrebuildJobs =
        try driver.explicitDependencyBuildPlanner!.generateExplicitModuleDependenciesBuildJobs()
      XCTAssertEqual(modulePrebuildJobs.count, 4)
      for job in modulePrebuildJobs {
        XCTAssertEqual(job.outputs.count, 1)
        XCTAssertFalse(driver.isExplicitMainModuleJob(job: job))
        switch (job.outputs[0].file) {

          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .clang("SwiftShims"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "c_simd", with: pcmArgs)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .clang("c_simd"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("Swift"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyOracle: dependencyOracle)
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
      let targetModulePathMap: ExternalTargetModulePathMap =
        [ModuleDependencyId.swiftPlaceholder("B"):AbsolutePath("/Somewhere/B.swiftmodule")]

      let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
                                             processSet: ProcessSet(),
                                             fileSystem: localFileSystem,
                                             env: ProcessEnv.vars)
      var toolchain: Toolchain
      #if os(macOS)
      toolchain = DarwinToolchain(env: ProcessEnv.vars, executor: executor)
      #else
      toolchain = GenericUnixToolchain(env: ProcessEnv.vars, executor: executor)
      #endif
      let toolchainRootPath: AbsolutePath = try toolchain.getToolPath(.swiftCompiler)
                                                              .parentDirectory // bin
                                                              .parentDirectory // toolchain root
      let dependencyOracle = InterModuleDependencyOracle()
      try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                         toolchainPath: toolchainRootPath)
      try dependencyOracle.mergeModules(from: inputDependencyGraph)

      // Construct a module dependency graph that will contain .swiftPlaceholder("B"),
      // .swiftPlaceholder("Swift"), .swiftPlaceholder("SwiftOnoneSupport")
      var moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerPlaceholderOutput.data(using: .utf8)!)

      // Construct the driver with explicit external dependency input
      let commandLine = ["swiftc", "-experimental-explicit-module-build",
                         "test.swift", "-module-name", "A", "-g"]

      var driver = try Driver(args: commandLine, executor: executor,
                              externalBuildArtifacts: (targetModulePathMap, [:]),
                              interModuleDependencyOracle: dependencyOracle)


      // Plan explicit dependency jobs, after resolving placeholders to actual dependencies.
      try moduleDependencyGraph.resolvePlaceholderDependencies(for: (targetModulePathMap, [:]),
                                                               using: dependencyOracle)

      // Ensure the graph no longer contains any placeholders
      XCTAssertFalse(moduleDependencyGraph.modules.keys.contains {
        if case .swiftPlaceholder(_) = $0 {
          return true
        }
        return false
      })

      // Merge the resolved version of the graph into the oracle
      try dependencyOracle.mergeModules(from: moduleDependencyGraph)
      driver.explicitDependencyBuildPlanner =
        try ExplicitDependencyBuildPlanner(dependencyGraph: moduleDependencyGraph,
                                           toolchain: driver.toolchain)
      let modulePrebuildJobs =
        try driver.explicitDependencyBuildPlanner!.generateExplicitModuleDependenciesBuildJobs()

      XCTAssertEqual(modulePrebuildJobs.count, 2)
      let mainModuleJob = try driver.emitModuleJob()
      XCTAssertEqual(mainModuleJob.inputs.count, 5)
      for input in mainModuleJob.inputs {
        switch (input.file) {
          case .relative(RelativePath("Swift.swiftmodule")):
            continue
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            continue
          case .relative(RelativePath("test.swift")):
            continue
          case .absolute(AbsolutePath("/Somewhere/B.swiftmodule")):
            continue
          case .temporaryWithKnownContents(let filePath, _):
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
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
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
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath,
                                     "-I", swiftModuleInterfacesPath,
                                     "-experimental-explicit-module-build",
                                     main.pathString])

      let jobs = try driver.planBuild()
      // Figure out which Triples to use.
      let dependencyOracle = driver.interModuleDependencyOracle
      let mainModuleInfo =
        dependencyOracle.getExternalModuleInfo(of: .swift("testExplicitModuleBuildJobs"))!
      guard case .swift(let mainModuleSwiftDetails) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      let pcmArgsCurrent = mainModuleSwiftDetails.extraPcmArgs
      var pcmArgs9 = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.9"]
      if driver.targetTriple.isDarwin {
        pcmArgs9.append(contentsOf: ["-Xcc", "-fapinotes-swift-version=5"])
      }
      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        switch (job.outputs[0].file) {
          case .relative(RelativePath("A.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("A"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("E.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("E"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("G.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("G"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("Swift"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "A", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("A"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "B", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("B"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "C", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("C"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "G", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("G"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "G", with: pcmArgs9)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("G"),
                                            dependencyOracle: dependencyOracle)
          // Module X is a dependency from Clang module "G" discovered only via versioned PCM
          // re-scan. 
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "X", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("X"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "X", with: pcmArgs9)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("X"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs9)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("SwiftShims"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("SwiftShims"),
                                            dependencyOracle: dependencyOracle)
          case .temporary(RelativePath("testExplicitModuleBuildJobs.o")):
            XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
            let pcmArgs = mainModuleSwiftDetails.extraPcmArgs
            try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: pcmArgs,
                                                        moduleInfo: mainModuleInfo,
                                                        dependencyOracle: dependencyOracle)
          case .relative(RelativePath("testExplicitModuleBuildJobs")):
            XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
            XCTAssertEqual(job.kind, .link)

          case .temporary(RelativePath("testExplicitModuleBuildJobs.autolink")):
            XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
            XCTAssertEqual(job.kind, .autolinkExtract)

          default:
            XCTFail("Unexpected module dependency build job output: \(job.outputs[0].file)")
        }
      }
    }
  }

  func testImmediateModeExplicitModuleBuild() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import C\n"
      }

      let packageRootPath = URL(fileURLWithPath: #file).pathComponents
          .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
      let testInputsPath = packageRootPath + "/TestInputs"
      let cHeadersPath : String = testInputsPath + "/ExplicitModuleBuilds/CHeaders"
      let swiftModuleInterfacesPath : String = testInputsPath + "/ExplicitModuleBuilds/Swift"
      var driver = try Driver(args: ["swift",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath,
                                     "-I", swiftModuleInterfacesPath,
                                     "-experimental-explicit-module-build",
                                     main.pathString])

      let jobs = try driver.planBuild()

      let interpretJobs = jobs.filter { $0.kind == .interpret }
      XCTAssertEqual(interpretJobs.count, 1)
      let interpretJob = interpretJobs[0]
      XCTAssertTrue(interpretJob.requiresInPlaceExecution)
      XCTAssertTrue(interpretJob.commandLine.contains(subsequence: ["-frontend", "-interpret"]))
      XCTAssertTrue(interpretJob.commandLine.contains("-disable-implicit-swift-modules"))
      XCTAssertTrue(interpretJob.commandLine.contains(subsequence: ["-Xcc", "-Xclang", "-Xcc", "-fno-implicit-modules"]))

      // Figure out which Triples to use.
      let dependencyOracle = driver.interModuleDependencyOracle
      let mainModuleInfo =
        dependencyOracle.getExternalModuleInfo(of: .swift("testExplicitModuleBuildJobs"))!
      guard case .swift(let mainModuleSwiftDetails) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      let pcmArgsCurrent = mainModuleSwiftDetails.extraPcmArgs
      var pcmArgs9 = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.9"]
      if driver.targetTriple.isDarwin {
        pcmArgs9.append(contentsOf: ["-Xcc", "-fapinotes-swift-version=5"])
      }

      for job in jobs {
        guard job.kind != .interpret else { continue }
        XCTAssertEqual(job.outputs.count, 1)
        switch (job.outputs[0].file) {
          case .relative(RelativePath("A.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("A"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("Swift"),
                                            dependencyOracle: dependencyOracle)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "A", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("A"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "B", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("B"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "C", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("C"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs9)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("SwiftShims"),
                                            dependencyOracle: dependencyOracle)
          case .relative(try pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgsCurrent)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("SwiftShims"),
                                            dependencyOracle: dependencyOracle)
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
      let main = path.appending(component: "testExplicitModuleBuildEndToEnd.swift")
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

  /// Test the libSwiftScan dependency scanning.
  func testDependencyScanning() throws {
    // Just instantiating to get at the toolchain path
    let driver = try Driver(args: ["swiftc", "-experimental-explicit-module-build",
                                   "-module-name", "testDependencyScanning",
                                   "test.swift"])
    let toolchainRootPath: AbsolutePath = try driver.toolchain.getToolPath(.swiftCompiler)
                                                            .parentDirectory // bin
                                                            .parentDirectory // toolchain root
    let stdLibPath = toolchainRootPath.appending(component: "lib")
                                      .appending(component: "swift")
                                      .appending(component: "macosx")
    let shimsPath = toolchainRootPath.appending(component: "lib")
                                     .appending(component: "swift")
                                     .appending(component: "shims")
    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                       toolchainPath: toolchainRootPath)

    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
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
      let scannerCommand = ["-scan-dependencies",
                            "-I", cHeadersPath,
                            "-I", swiftModuleInterfacesPath,
                            "-I", stdLibPath.description,
                            "-I", shimsPath.description,
                            main.pathString]

      // Dispatch several iterations in parallel
      DispatchQueue.concurrentPerform(iterations: 20) { index in
        // Give the main modules different names
        let iterationCommand = scannerCommand + ["-module-name",
                                                 "testDependencyScanning\(index)"]
        let dependencyGraph =
          try! dependencyOracle.getDependencies(workingDirectory: path,
                                                commandLine: iterationCommand)
        XCTAssertTrue(dependencyGraph.modules.count == 11)
      }
    }
  }

  func testDependencyGraphMerge() throws {
    let moduleDependencyGraph1 =
          try JSONDecoder().decode(
            InterModuleDependencyGraph.self,
            from: ModuleDependenciesInputs.mergeGraphInput1.data(using: .utf8)!)
    let moduleDependencyGraph2 =
          try JSONDecoder().decode(
            InterModuleDependencyGraph.self,
            from: ModuleDependenciesInputs.mergeGraphInput2.data(using: .utf8)!)

    var accumulatingModuleInfoMap: [ModuleDependencyId: ModuleInfo] = [:]

    try InterModuleDependencyGraph.mergeModules(from: moduleDependencyGraph1,
                                                into: &accumulatingModuleInfoMap)
    try InterModuleDependencyGraph.mergeModules(from: moduleDependencyGraph2,
                                                into: &accumulatingModuleInfoMap)

    // Ensure the dependencies of the diplicate clang "B" module are merged
    let clangIDs = accumulatingModuleInfoMap.keys.filter { $0.moduleName == "B" }
    XCTAssertTrue(clangIDs.count == 1)
    let clangBInfo = accumulatingModuleInfoMap[clangIDs[0]]!
    XCTAssertTrue(clangBInfo.directDependencies!.count == 2)
    XCTAssertTrue(clangBInfo.directDependencies!.contains(ModuleDependencyId.clang("D")))
    XCTAssertTrue(clangBInfo.directDependencies!.contains(ModuleDependencyId.clang("C")))
  }

  func testExplicitSwiftModuleMap() throws {
    let jsonExample : String = """
    [
      {
        "moduleName": "A",
        "modulePath": "A.swiftmodule",
        "docPath": "A.swiftdoc",
        "sourceInfoPath": "A.swiftsourceinfo",
        "isFramework": true
      },
      {
        "moduleName": "B",
        "modulePath": "B.swiftmodule",
        "docPath": "B.swiftdoc",
        "sourceInfoPath": "B.swiftsourceinfo",
        "isFramework": false
      }
    ]
    """
    let moduleMap = try JSONDecoder().decode(Array<SwiftModuleArtifactInfo>.self,
                                             from: jsonExample.data(using: .utf8)!)
    XCTAssertEqual(moduleMap.count, 2)
    XCTAssertEqual(moduleMap[0].moduleName, "A")
    XCTAssertEqual(moduleMap[0].modulePath.path.description, "A.swiftmodule")
    XCTAssertEqual(moduleMap[0].docPath!.path.description, "A.swiftdoc")
    XCTAssertEqual(moduleMap[0].sourceInfoPath!.path.description, "A.swiftsourceinfo")
    XCTAssertEqual(moduleMap[0].isFramework, true)
    XCTAssertEqual(moduleMap[1].moduleName, "B")
    XCTAssertEqual(moduleMap[1].modulePath.path.description, "B.swiftmodule")
    XCTAssertEqual(moduleMap[1].docPath!.path.description, "B.swiftdoc")
    XCTAssertEqual(moduleMap[1].sourceInfoPath!.path.description, "B.swiftsourceinfo")
    XCTAssertEqual(moduleMap[1].isFramework, false)
  }
}
