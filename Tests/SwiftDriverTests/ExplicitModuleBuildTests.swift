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
import TestUtilities

/// Check that an explicit module build job contains expected inputs and options
private func checkExplicitModuleBuildJob(job: Job,
                                         pcmArgs: [String],
                                         moduleId: ModuleDependencyId,
                                         dependencyOracle: InterModuleDependencyOracle,
                                         pcmFileEncoder: (ModuleInfo, [String]) -> VirtualPath.Handle)
throws {
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
          XCTAssertTrue(job.commandLine.contains(.path(VirtualPath.lookup(candidatePath))))
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
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkExplicitModuleBuildJobDependencies(job: Job,
                                                     pcmArgs: [String],
                                                     moduleInfo : ModuleInfo,
                                                     dependencyOracle: InterModuleDependencyOracle,
                                                     pcmFileEncoder: (ModuleInfo, [String]) -> VirtualPath.Handle
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
        let clangDependencyModulePathString = pcmFileEncoder(dependencyInfo, pcmArgs)
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
                                                  dependencyOracle: dependencyOracle,
                                                  pcmFileEncoder: pcmFileEncoder)

    }
  }
}

private func pcmArgsEncodedRelativeModulePath(for moduleName: String, with pcmArgs: [String],
                                              pcmModuleNameEncoder: (String, [String]) -> String
) -> RelativePath {
  return RelativePath(pcmModuleNameEncoder(moduleName, pcmArgs) + ".pcm")
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
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try Driver.getScanLibPath(of: driver.toolchain,
                                                  hostTriple: driver.hostTriple,
                                                  env: ProcessEnv.vars)
      let _ = try dependencyOracle
        .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                       swiftScanLibPath: scanLibPath)
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
        let pcmFileEncoder = { (moduleInfo: ModuleInfo, hashParts: [String]) -> VirtualPath.Handle in
          try! driver.explicitDependencyBuildPlanner!.targetEncodedClangModuleFilePath(for: moduleInfo,
                                                                                       hashParts: hashParts)
        }
        let pcmModuleNameEncoder = { (moduleName: String, hashParts: [String]) -> String in
          try! driver.explicitDependencyBuildPlanner!.targetEncodedClangModuleName(for: moduleName,
                                                                                   hashParts: hashParts)
        }
        switch (job.outputs[0].file) {
          case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs,
                                                          pcmModuleNameEncoder: pcmModuleNameEncoder)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .clang("SwiftShims"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(pcmArgsEncodedRelativeModulePath(for: "c_simd", with: pcmArgs,
                                                          pcmModuleNameEncoder: pcmModuleNameEncoder)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .clang("c_simd"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("Swift"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(RelativePath("_Concurrency.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("_Concurrency"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
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
      let dependencyOracle = InterModuleDependencyOracle()
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
      let scanLibPath = try Driver.getScanLibPath(of: driver.toolchain,
                                                  hostTriple: driver.hostTriple,
                                                  env: ProcessEnv.vars)
      let _ = try dependencyOracle
        .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                       swiftScanLibPath: scanLibPath)

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
          case .relative(RelativePath("_Concurrency.swiftmodule")):
            continue
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            continue
          case .relative(RelativePath("test.swift")):
            continue
          case .absolute(AbsolutePath("/Somewhere/B.swiftmodule")):
            continue
          case .temporaryWithKnownContents(_, _):
            XCTAssertTrue(matchTemporary(input.file, "A-dependencies.json"))
            continue
          default:
            XCTFail("Unexpected module input: \(input.file)")
        }
      }
    }
  }

  private func pathMatchesSwiftModule(path: VirtualPath, _ name: String) -> Bool {
    return path.basenameWithoutExt.starts(with: "\(name)-") &&
           path.extension! == FileType.swiftModule.rawValue
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
      let pcmFileEncoder = { (moduleInfo: ModuleInfo, hashParts: [String]) -> VirtualPath.Handle in
        try! driver.explicitDependencyBuildPlanner!.targetEncodedClangModuleFilePath(for: moduleInfo,
                                                                                     hashParts: hashParts)
      }
      let pcmModuleNameEncoder = { (moduleName: String, hashParts: [String]) -> String in
        try! driver.explicitDependencyBuildPlanner!.targetEncodedClangModuleName(for: moduleName,
                                                                                 hashParts: hashParts)
      }

      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("A"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "E") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("E"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "G") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("G"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("Swift"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("_Concurrency"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          }
        // Clang Dependencies
        } else if outputFilePath.extension != nil,
                  outputFilePath.extension! == FileType.pcm.rawValue {
          switch (outputFilePath) {
            case .relative(pcmArgsEncodedRelativeModulePath(for: "A", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("A"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "B", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("B"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "C", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("C"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "G", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("G"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "G", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("G"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            // Module X is a dependency from Clang module "G" discovered only via versioned PCM
            // re-scan.
            case .relative(pcmArgsEncodedRelativeModulePath(for: "X", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("X"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "X", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("X"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("SwiftShims"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("SwiftShims"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(RelativePath("testExplicitModuleBuildJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
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
      let pcmFileEncoder = { (moduleInfo: ModuleInfo, hashParts: [String]) -> VirtualPath.Handle in
        try! driver.explicitDependencyBuildPlanner!.targetEncodedClangModuleFilePath(for: moduleInfo,
                                                                                     hashParts: hashParts)
      }
      let pcmModuleNameEncoder = { (moduleName: String, hashParts: [String]) -> String in
        try! driver.explicitDependencyBuildPlanner!.targetEncodedClangModuleName(for: moduleName,
                                                                                 hashParts: hashParts)
      }
      for job in jobs {
        guard job.kind != .interpret else { continue }
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file
        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("A"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("Swift"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("_Concurrency"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyOracle: dependencyOracle,
                                            pcmFileEncoder: pcmFileEncoder)
          }
        // Clang Dependencies
        } else if outputFilePath.extension != nil,
                  outputFilePath.extension! == FileType.pcm.rawValue {
          switch (outputFilePath) {
            case .relative(pcmArgsEncodedRelativeModulePath(for: "A", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("A"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "B", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("B"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "C", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("C"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("SwiftShims"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("SwiftShims"),
                                              dependencyOracle: dependencyOracle,
                                              pcmFileEncoder: pcmFileEncoder)
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(RelativePath("testExplicitModuleBuildJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
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

  func getStdlibShimsPaths(_ driver: Driver) throws -> (AbsolutePath, AbsolutePath) {
    let toolchainRootPath: AbsolutePath = try driver.toolchain.getToolPath(.swiftCompiler)
                                                            .parentDirectory // bin
                                                            .parentDirectory // toolchain root
    if driver.targetTriple.isDarwin {
      let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
                                             processSet: ProcessSet(),
                                             fileSystem: localFileSystem,
                                             env: ProcessEnv.vars)
      let sdkPath = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path").spm_chomp()
      let stdLibPath = AbsolutePath(sdkPath).appending(component: "usr")
        .appending(component: "lib")
        .appending(component: "swift")
      return (stdLibPath, stdLibPath.appending(component: "shims"))
    } else {
      return (toolchainRootPath.appending(component: "lib")
                .appending(component: "swift")
                .appending(component: driver.targetTriple.osNameUnversioned),
              toolchainRootPath.appending(component: "lib")
                .appending(component: "swift")
                .appending(component: "shims"))
    }
  }

  private func getDriverArtifactsForScanning() throws -> (stdLibPath: AbsolutePath,
                                                          shimsPath: AbsolutePath,
                                                          toolchain: Toolchain,
                                                          hostTriple: Triple) {
    // Just instantiating to get at the toolchain path
    let driver = try Driver(args: ["swiftc", "-experimental-explicit-module-build",
                                   "-module-name", "testDependencyScanning",
                                   "test.swift"])
    let (stdLibPath, shimsPath) = try getStdlibShimsPaths(driver)
    XCTAssertTrue(localFileSystem.exists(stdLibPath),
                  "expected Swift StdLib at: \(stdLibPath.description)")
    XCTAssertTrue(localFileSystem.exists(shimsPath),
                  "expected Swift Shims at: \(shimsPath.description)")
    return (stdLibPath, shimsPath, driver.toolchain, driver.hostTriple)
  }

  /// Test the libSwiftScan dependency scanning (import-prescan).
  func testDependencyImportPrescan() throws {
    let (stdLibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try Driver.getScanLibPath(of: toolchain,
                                                hostTriple: hostTriple,
                                                env: ProcessEnv.vars)
    guard try dependencyOracle
            .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                           swiftScanLibPath: scanLibPath) else {
      XCTFail("Dependency scanner library not found")
      return
    }

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
                            "-import-prescan",
                            "-I", cHeadersPath,
                            "-I", swiftModuleInterfacesPath,
                            "-I", stdLibPath.description,
                            "-I", shimsPath.description,
                            main.pathString]

      let imports =
        try! dependencyOracle.getImports(workingDirectory: path,
                                         commandLine: scannerCommand)
      let expectedImports = ["C", "E", "G", "Swift", "SwiftOnoneSupport"]
      // Dependnig on how recent the platform we are running on, the Concurrency module may or may not be present.
      let expectedImports2 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency"]
      XCTAssertTrue(Set(imports.imports) == Set(expectedImports) || Set(imports.imports) == Set(expectedImports2))
    }
  }

  /// Test the libSwiftScan dependency scanning.
  func testDependencyScanning() throws {
    let (stdLibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try Driver.getScanLibPath(of: toolchain,
                                                hostTriple: hostTriple,
                                                env: ProcessEnv.vars)
    guard try dependencyOracle
            .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                           swiftScanLibPath: scanLibPath) else {
      XCTFail("Dependency scanner library not found")
      return
    }
    
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

      // Here purely to dump diagnostic output in a reasonable fashion when things go wrong.
      let lock = NSLock()

      // Module `X` is only imported on Darwin when:
      // #if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 110000
      let expectedNumberOfDependencies: Int
      if hostTriple.isMacOSX,
         hostTriple.version(for: .macOS) >= Triple.Version(11, 0, 0) {
        expectedNumberOfDependencies = 11
      } else {
        expectedNumberOfDependencies = 12
      }

      // Dispatch several iterations in parallel
      DispatchQueue.concurrentPerform(iterations: 20) { index in
        // Give the main modules different names
        let iterationCommand = scannerCommand + ["-module-name",
                                                 "testDependencyScanning\(index)"]
        let dependencyGraph =
          try! dependencyOracle.getDependencies(workingDirectory: path,
                                                commandLine: iterationCommand)

        // The _Concurrency module is automatically imported in newer versions
        // of the Swift compiler. If it happened to be provided, adjust
        // our expectations accordingly.
        let hasConcurrencyModule = dependencyGraph.modules.keys.contains {
          $0.moduleName == "_Concurrency"
        }
        let adjustedExpectedNumberOfDependencies =
            expectedNumberOfDependencies + (hasConcurrencyModule ? 1 : 0)

        if (dependencyGraph.modules.count != adjustedExpectedNumberOfDependencies) {
          lock.lock()
          print("Unexpected Dependency Scanning Result (\(dependencyGraph.modules.count) modules):")
          dependencyGraph.modules.forEach {
            print($0.key.moduleName)
          }
          lock.unlock()
        }
        XCTAssertTrue(dependencyGraph.modules.count ==
                      adjustedExpectedNumberOfDependencies)
      }
    }
  }


  /// Test the libSwiftScan dependency scanning.
  func testDependencyScanReuseCache() throws {
    let (stdLibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let cacheSavePath = path.appending(component: "saved.moddepcache")
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

      let scanLibPath = try Driver.getScanLibPath(of: toolchain,
                                                  hostTriple: hostTriple,
                                                  env: ProcessEnv.vars)
      // Run the first scan and serialize the cache contents.
      let firstDependencyOracle = InterModuleDependencyOracle()
      guard try firstDependencyOracle
              .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                             swiftScanLibPath: scanLibPath) else {
        XCTFail("Dependency scanner library not found")
        return
      }

      let firstScanGraph =
        try! firstDependencyOracle.getDependencies(workingDirectory: path,
                                              commandLine: scannerCommand)
      firstDependencyOracle.serializeScannerCache(to: cacheSavePath)

      // Run the second scan, re-using the serialized cache contents.
      let secondDependencyOracle = InterModuleDependencyOracle()
      guard try secondDependencyOracle
              .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                             swiftScanLibPath: scanLibPath) else {
        XCTFail("Dependency scanner library not found")
        return
      }
      XCTAssertFalse(secondDependencyOracle.loadScannerCache(from: cacheSavePath))
      let secondScanGraph =
        try! secondDependencyOracle.getDependencies(workingDirectory: path,
                                                    commandLine: scannerCommand)

      XCTAssertTrue(firstScanGraph.modules.count == secondScanGraph.modules.count)
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
// We only care about prebuilt modules in macOS.
#if os(macOS)
  func testPrebuiltModuleGenerationJobs() throws {
    func getInputModules(_ job: Job) -> [String] {
      return job.inputs.map { input in
        return input.file.absolutePath!.parentDirectory.basenameWithoutExt
      }.sorted()
    }

    func getOutputName(_ job: Job) -> String {
      XCTAssertTrue(job.outputs.count == 1)
      return job.outputs[0].file.basename
    }

    func checkInputOutputIntegrity(_ job: Job) {
      let name = job.outputs[0].file.basenameWithoutExt
      XCTAssertTrue(job.outputs[0].file.extension == "swiftmodule")
      job.inputs.forEach { input in
        XCTAssertTrue(input.file.extension == "swiftmodule")
        let inputName = input.file.basenameWithoutExt
        // arm64 interface can depend on ar64e interface
        if inputName.starts(with: "arm64e-") && name.starts(with: "arm64-") {
          return
        }
        XCTAssertTrue(inputName == name)
      }
    }

    func findJob(_ jobs: [Job],_ module: String, _ basenameWithoutExt: String) -> Job? {
      return jobs.first { job in
        return job.moduleName == module &&
          job.outputs[0].file.basenameWithoutExt == basenameWithoutExt
      }
    }
    let packageRootPath = URL(fileURLWithPath: #file).pathComponents
      .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
    let testInputsPath = packageRootPath + "/TestInputs"
    let mockSDKPath : String = testInputsPath + "/mock-sdk.sdk"
    let diagnosticEnging = DiagnosticsEngine()
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPath).absolutePath!, diagnosticEnging)
    let interfaceMap = try collector.collectSwiftInterfaceMap()

    // Check interface map always contain everything
    XCTAssertTrue(interfaceMap["Swift"]!.count == 3)
    XCTAssertTrue(interfaceMap["A"]!.count == 3)
    XCTAssertTrue(interfaceMap["E"]!.count == 3)
    XCTAssertTrue(interfaceMap["F"]!.count == 3)
    XCTAssertTrue(interfaceMap["G"]!.count == 3)
    XCTAssertTrue(interfaceMap["H"]!.count == 3)

    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import A\n"
        $0 <<< "import E\n"
        $0 <<< "import F\n"
        $0 <<< "import G\n"
        $0 <<< "import H\n"
        $0 <<< "import Swift\n"
      }
      let moduleCachePath = "/tmp/module-cache"
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                     "-module-cache-path", moduleCachePath
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuitModuleGenerationJobs(with: interfaceMap,
                                                                                into: VirtualPath(path: "/tmp/").absolutePath!,
                                                                                exhaustive: true)

      XCTAssertTrue(danglingJobs.count == 2)
      XCTAssertTrue(danglingJobs.allSatisfy { job in
        job.moduleName == "MissingKit"
      })
      XCTAssertTrue(jobs.count == 18)
      XCTAssertTrue(jobs.allSatisfy {$0.outputs.count == 1})
      XCTAssertTrue(jobs.allSatisfy {$0.kind == .compile})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-compile-module-from-interface"))})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-module-cache-path"))})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-bad-file-descriptor-retry-count"))})
      XCTAssertTrue(try jobs.allSatisfy {$0.commandLine.contains(.path(try VirtualPath(path: moduleCachePath)))})
      let HJobs = jobs.filter { $0.moduleName == "H"}
      XCTAssertTrue(HJobs.count == 3)
      // arm64
      XCTAssertTrue(getInputModules(HJobs[0]) == ["A", "A", "E", "E", "F", "F", "G", "G", "Swift", "Swift"])
      // arm64e
      XCTAssertTrue(getInputModules(HJobs[1]) == ["A", "E", "F", "G", "Swift"])
      // x86_64
      XCTAssertTrue(getInputModules(HJobs[2]) == ["A", "E", "F", "G", "Swift"])
      XCTAssertTrue(getOutputName(HJobs[0]) != getOutputName(HJobs[1]))
      XCTAssertTrue(getOutputName(HJobs[1]) != getOutputName(HJobs[2]))
      checkInputOutputIntegrity(HJobs[0])
      checkInputOutputIntegrity(HJobs[1])
      checkInputOutputIntegrity(HJobs[2])
      let GJobs = jobs.filter { $0.moduleName == "G"}
      XCTAssertTrue(GJobs.count == 3)
      XCTAssertTrue(getInputModules(GJobs[0]) == ["E", "E", "Swift", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[1]) == ["E", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[2]) == ["E", "Swift"])
      XCTAssertTrue(getOutputName(GJobs[0]) != getOutputName(GJobs[1]))
      XCTAssertTrue(getOutputName(GJobs[1]) != getOutputName(GJobs[2]))
      checkInputOutputIntegrity(GJobs[0])
      checkInputOutputIntegrity(GJobs[1])
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import H\n"
      }
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuitModuleGenerationJobs(with: interfaceMap,
                                                                                into: VirtualPath(path: "/tmp/").absolutePath!,
                                                                                exhaustive: false)

      XCTAssertTrue(danglingJobs.isEmpty)
      XCTAssertTrue(jobs.count == 18)
      XCTAssertTrue(jobs.allSatisfy {$0.outputs.count == 1})
      XCTAssertTrue(jobs.allSatisfy {$0.kind == .compile})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-compile-module-from-interface"))})
      let HJobs = jobs.filter { $0.moduleName == "H"}
      XCTAssertTrue(HJobs.count == 3)
      // arm64
      XCTAssertTrue(getInputModules(HJobs[0]) == ["A", "A", "E", "E", "F", "F", "G", "G", "Swift", "Swift"])
      // arm64e
      XCTAssertTrue(getInputModules(HJobs[1]) == ["A", "E", "F", "G", "Swift"])
      // x86_64
      XCTAssertTrue(getInputModules(HJobs[2]) == ["A", "E", "F", "G", "Swift"])
      XCTAssertTrue(getOutputName(HJobs[0]) != getOutputName(HJobs[1]))
      checkInputOutputIntegrity(HJobs[0])
      checkInputOutputIntegrity(HJobs[1])
      let GJobs = jobs.filter { $0.moduleName == "G"}
      XCTAssertTrue(GJobs.count == 3)
      XCTAssertTrue(getInputModules(GJobs[0]) == ["E", "E", "Swift", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[1]) == ["E", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[2]) == ["E", "Swift"])
      XCTAssertTrue(getOutputName(GJobs[0]) != getOutputName(GJobs[1]))
      XCTAssertTrue(getOutputName(GJobs[1]) != getOutputName(GJobs[2]))
      checkInputOutputIntegrity(GJobs[0])
      checkInputOutputIntegrity(GJobs[1])
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import Swift\n"
      }
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuitModuleGenerationJobs(with: interfaceMap,
                                                                                into: VirtualPath(path: "/tmp/").absolutePath!,
                                                                                exhaustive: false)

      XCTAssertTrue(danglingJobs.isEmpty)
      XCTAssert(jobs.count == 3)
      XCTAssert(jobs.allSatisfy { $0.moduleName == "Swift" })
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import F\n"
      }
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuitModuleGenerationJobs(with: interfaceMap,
                                                                                into: VirtualPath(path: "/tmp/").absolutePath!,
                                                                                exhaustive: false)

      XCTAssertTrue(danglingJobs.isEmpty)
      XCTAssertTrue(jobs.count == 9)
      jobs.forEach({ job in
        // Check we don't pull in other modules than A, F and Swift
        XCTAssertTrue(["A", "F", "Swift"].contains(job.moduleName))
        checkInputOutputIntegrity(job)
      })
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import H\n"
      }
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, _) = try driver.generatePrebuitModuleGenerationJobs(with: interfaceMap,
                                                                                into: VirtualPath(path: "/tmp/").absolutePath!,
                                                                                exhaustive: false)
      let F = findJob(jobs, "F", "arm64-apple-macos")!
      let H = findJob(jobs, "H", "arm64e-apple-macos")!
      // Test arm64 interface requires arm64e interfaces as inputs
      XCTAssertTrue(F.inputs.contains { input in
        input.file.basenameWithoutExt == "arm64e-apple-macos"
      })
      // Test arm64e interface doesn't require arm64 interfaces as inputs
      XCTAssertTrue(!H.inputs.contains { input in
        input.file.basenameWithoutExt == "arm64-apple-macos"
      })
    }
  }
#endif
}
