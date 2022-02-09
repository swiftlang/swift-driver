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

@_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import TSCBasic
import XCTest
import TestUtilities

private var testInputsPath: AbsolutePath = {
  var root: AbsolutePath = AbsolutePath(#file)
  while root.basename != "Tests" {
    root = root.parentDirectory
  }
  return root.parentDirectory.appending(component: "TestInputs")
}()

/// Check that an explicit module build job contains expected inputs and options
private func checkExplicitModuleBuildJob(job: Job,
                                         pcmArgs: [String],
                                         moduleId: ModuleDependencyId,
                                         dependencyGraph: InterModuleDependencyGraph,
                                         pcmFileEncoder: (ModuleInfo, [String]) -> VirtualPath.Handle)
throws {
  let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
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
  XCTAssertTrue(job.commandLine.contains(.flag(String("-fno-implicit-module-maps"))))

  try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: downstreamPCMArgs,
                                              moduleInfo: moduleInfo,
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkExplicitModuleBuildJobDependencies(job: Job,
                                                     pcmArgs: [String],
                                                     moduleInfo : ModuleInfo,
                                                     dependencyGraph: InterModuleDependencyGraph,
                                                     pcmFileEncoder: (ModuleInfo, [String]) -> VirtualPath.Handle
) throws {
  for dependencyId in moduleInfo.directDependencies! {
    let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)
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
          .flag(String("-fmodule-file=\(dependencyId.moduleName)=\(clangDependencyModulePathString)"))))
        XCTAssertTrue(job.commandLine.contains(
                        .flag(String("-fmodule-map-file=\(clangDependencyDetails.moduleMapPath.path.description)"))))
      case .swiftPlaceholder(_):
        XCTFail("Placeholder dependency found.")
    }

    // Ensure all transitive dependencies got added as well.
    for transitiveDependencyId in dependencyInfo.directDependencies! {
      try checkExplicitModuleBuildJobDependencies(job: job, pcmArgs: pcmArgs, 
                                                  moduleInfo: try dependencyGraph.moduleInfo(of: transitiveDependencyId),
                                                  dependencyGraph: dependencyGraph,
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
    #if os(macOS)
    do {
      var driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                     "-module-name", "testModuleDependencyBuildCommandGeneration",
                                     "test.swift"])
      let pcmArgs = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.15"]
      let moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerOutput.data(using: .utf8)!)
      driver.explicitDependencyBuildPlanner =
        try ExplicitDependencyBuildPlanner(dependencyGraph: moduleDependencyGraph,
                                           toolchain: driver.toolchain)
      let modulePrebuildJobs =
        try driver.explicitDependencyBuildPlanner!.generateExplicitModuleDependenciesBuildJobs()
      XCTAssertEqual(modulePrebuildJobs.count, 4)
      for job in modulePrebuildJobs {
        XCTAssertEqual(job.outputs.count, 1)
        XCTAssertFalse(driver.isExplicitMainModuleJob(job: job))

        let (pcmFileEncoder, pcmModuleNameEncoder) = pcmEncoderProducer(dependencyGraph: moduleDependencyGraph, driver: driver)
        switch (job.outputs[0].file) {
          case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs,
                                                          pcmModuleNameEncoder: pcmModuleNameEncoder)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .clang("SwiftShims"),
                                            dependencyGraph: moduleDependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(pcmArgsEncodedRelativeModulePath(for: "c_simd", with: pcmArgs,
                                                          pcmModuleNameEncoder: pcmModuleNameEncoder)):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .clang("c_simd"),
                                            dependencyGraph: moduleDependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(RelativePath("Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("Swift"),
                                            dependencyGraph: moduleDependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(RelativePath("_Concurrency.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("_Concurrency"),
                                            dependencyGraph: moduleDependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          case .relative(RelativePath("SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs,
                                            moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: moduleDependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          default:
            XCTFail("Unexpected module dependency build job output: \(job.outputs[0].file)")
        }
      }
    }
    #endif
  }

  func testModuleDependencyBuildCommandGenerationWithExternalFramework() throws {
    do {
      let externalDetails: ExternalTargetModuleDetailsMap =
            [.swiftPrebuiltExternal("A"): ExternalTargetModuleDetails(path: AbsolutePath("/tmp/A.swiftmodule"),
                                                      isFramework: true)]
      var driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                     "-module-name", "testModuleDependencyBuildCommandGenerationWithExternalFramework",
                                     "test.swift"])
      var moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.simpleDependencyGraphInput.data(using: .utf8)!)
      // Key part of this test, using the external info to generate dependency pre-build jobs
      try moduleDependencyGraph.resolveExternalDependencies(for: externalDetails)
      driver.explicitDependencyBuildPlanner =
        try ExplicitDependencyBuildPlanner(dependencyGraph: moduleDependencyGraph,
                                           toolchain: driver.toolchain)
      let modulePrebuildJobs =
        try driver.explicitDependencyBuildPlanner!.generateExplicitModuleDependenciesBuildJobs()

      XCTAssertEqual(modulePrebuildJobs.count, 1)
      let job = modulePrebuildJobs.first!
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
      XCTAssertEqual(dependencyInfoList.count, 1)
      let dependencyArtifacts =
        dependencyInfoList.first(where:{ $0.moduleName == "A" })!
      // Ensure this is a framework, as specified by the externalDetails above.
      XCTAssertEqual(dependencyArtifacts.isFramework, true)
    }
  }

  private func pathMatchesSwiftModule(path: VirtualPath, _ name: String) -> Bool {
    return path.basenameWithoutExt.starts(with: "\(name)-") &&
           path.extension! == FileType.swiftModule.rawValue
  }

  private func pcmEncoderProducer(dependencyGraph: InterModuleDependencyGraph,
                                  driver: Driver)
  -> ((ModuleInfo, [String]) -> VirtualPath.Handle, (String, [String]) -> String) {
    var driverCopy = driver
    let moduleMapIncludedHashParts = { (_ moduleName: String, _ hashParts: [String]) -> [String] in
      let moduleDetails = try? dependencyGraph.clangModuleDetails(of: .clang(moduleName))
      let lookupHashParts: [String]
      if let details = moduleDetails {
        let contextHash = details.contextHash
        lookupHashParts = [contextHash] + hashParts
      } else {
        // No such module found, no modulemap
        lookupHashParts = hashParts
      }
      return lookupHashParts
    }

    let pcmFileEncoder = { (moduleInfo: ModuleInfo, hashParts: [String]) -> VirtualPath.Handle in
      let plainModulePath = VirtualPath.lookup(moduleInfo.modulePath.path)
      let moduleName = plainModulePath.basenameWithoutExt
      let lookupHashParts = moduleMapIncludedHashParts(moduleName, hashParts)
      return try! driverCopy.explicitDependencyBuildPlanner!.targetEncodedClangModuleFilePath(for: moduleInfo,
                                                                                   hashParts: lookupHashParts)
    }

    let pcmModuleNameEncoder = { (moduleName: String, hashParts: [String]) -> String in
      let lookupHashParts = moduleMapIncludedHashParts(moduleName, hashParts)
      return try! driverCopy.explicitDependencyBuildPlanner!.targetEncodedClangModuleName(for: moduleName,
                                                                                      hashParts: lookupHashParts)
    }
    return (pcmFileEncoder, pcmModuleNameEncoder)
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build
  func testExplicitModuleBuildJobs() throws {
    #if os(macOS)
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import C;"
        $0 <<< "import E;"
        $0 <<< "import G;"
      }

      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()
      // Figure out which Triples to use.
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildJobs"))
      guard case .swift(let mainModuleSwiftDetails) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      let pcmArgsCurrent = mainModuleSwiftDetails.extraPcmArgs
      var pcmArgs9 = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.9"]
      var pcmArgs15 = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.15"]
      if driver.targetTriple.isDarwin {
        pcmArgs9.append(contentsOf: ["-Xcc", "-fapinotes-swift-version=5"])
        pcmArgs15.append(contentsOf: ["-Xcc", "-fapinotes-swift-version=5"])
      }

      let (pcmFileEncoder, pcmModuleNameEncoder) = pcmEncoderProducer(dependencyGraph: dependencyGraph, driver: driver)

      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("A"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "E") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("E"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "G") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("G"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("Swift"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("_Concurrency"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          }
        // Clang Dependencies
        } else if outputFilePath.extension != nil,
                  outputFilePath.extension! == FileType.pcm.rawValue {

          switch (outputFilePath) {
            case .relative(pcmArgsEncodedRelativeModulePath(for: "A", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("A"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "B", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("B"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "C", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("C"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "G", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("G"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "G", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("G"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            // Module X is a dependency from Clang module "G" discovered only via versioned PCM
            // re-scan.
            case .relative(pcmArgsEncodedRelativeModulePath(for: "X", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("X"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "X", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("X"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("SwiftShims"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs15,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs15, moduleId: .clang("SwiftShims"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("SwiftShims"),
                                              dependencyGraph: dependencyGraph,
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
    #endif
  }

  func testImmediateModeExplicitModuleBuild() throws {
    #if os(macOS)
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import C\n"
      }

      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swift",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()

      let interpretJobs = jobs.filter { $0.kind == .interpret }
      XCTAssertEqual(interpretJobs.count, 1)
      let interpretJob = interpretJobs[0]
      XCTAssertTrue(interpretJob.requiresInPlaceExecution)
      XCTAssertTrue(interpretJob.commandLine.contains(subsequence: ["-frontend", "-interpret"]))
      XCTAssertTrue(interpretJob.commandLine.contains("-disable-implicit-swift-modules"))
      XCTAssertTrue(interpretJob.commandLine.contains(subsequence: ["-Xcc", "-Xclang", "-Xcc", "-fno-implicit-modules"]))

      // Figure out which Triples to use.
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildJobs"))
      guard case .swift(let mainModuleSwiftDetails) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      let pcmArgsCurrent = mainModuleSwiftDetails.extraPcmArgs
      var pcmArgs9 = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.9"]
      var pcmArgs15 = ["-Xcc","-target","-Xcc","x86_64-apple-macosx10.15"]
      if driver.targetTriple.isDarwin {
        pcmArgs9.append(contentsOf: ["-Xcc", "-fapinotes-swift-version=5"])
        pcmArgs15.append(contentsOf: ["-Xcc", "-fapinotes-swift-version=5"])
      }

      let (pcmFileEncoder, pcmModuleNameEncoder) = pcmEncoderProducer(dependencyGraph: dependencyGraph, driver: driver)

      for job in jobs {
        guard job.kind != .interpret else { continue }
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file
        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("A"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("Swift"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("_Concurrency"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: dependencyGraph,
                                            pcmFileEncoder: pcmFileEncoder)
          }
        // Clang Dependencies
        } else if outputFilePath.extension != nil,
                  outputFilePath.extension! == FileType.pcm.rawValue {
          switch (outputFilePath) {
            case .relative(pcmArgsEncodedRelativeModulePath(for: "A", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("A"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "B", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("B"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "C", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("C"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs9,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs9, moduleId: .clang("SwiftShims"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgs15,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgs15, moduleId: .clang("SwiftShims"),
                                              dependencyGraph: dependencyGraph,
                                              pcmFileEncoder: pcmFileEncoder)
            case .relative(pcmArgsEncodedRelativeModulePath(for: "SwiftShims", with: pcmArgsCurrent,
                                                            pcmModuleNameEncoder: pcmModuleNameEncoder)):
              try checkExplicitModuleBuildJob(job: job, pcmArgs: pcmArgsCurrent, moduleId: .clang("SwiftShims"),
                                              dependencyGraph: dependencyGraph,
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
    #endif
  }

  
  func testModuleAliasingPrebuiltWithScanDeps() throws {
    // rdar://88073675
    throw XCTSkip("Skipping, known failure (rdar://88073675).")
    try withTemporaryDirectory { path in
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      let srcBar = path.appending(component: "bar.swift")
      let moduleBarPath = path.appending(component: "Bar.swiftmodule").nativePathString(escaped: true)
      try localFileSystem.writeFileContents(srcBar) {
        $0 <<< "public class KlassBar {}"
      }
      
      // Create Bar.swiftmodule
      var driver = try Driver(args: ["swiftc",
                                     "-explicit-module-build",
                                     "-working-directory",
                                     path.nativePathString(escaped: true),
                                     srcBar.nativePathString(escaped: true),
                                     "-module-name",
                                     "Bar",
                                     "-emit-module",
                                     "-emit-module-path", moduleBarPath,
                                     "-I", stdLibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                              ] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      guard driver.isFrontendArgSupported(.moduleAlias) else {
        throw XCTSkip("Skipping: compiler does not support '-module-alias'")
      }

      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      XCTAssertTrue(FileManager.default.fileExists(atPath: moduleBarPath))
      
      // Foo imports Car which is mapped to the real module Bar via
      // `-module-alias Car=Bar`; it allows Car (alias) to be referenced
      // in source files, while its contents are compiled as Bar (real
      // name on disk).
      let srcFoo = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(srcFoo) {
        $0 <<< "import Car\n"
        $0 <<< "func run() -> Car.KlassBar? { return nil }"
      }
      
      // Module alias with the fallback scanner (frontend scanner)
      var driverA = try Driver(args: ["swiftc",
                                      "-nonlib-dependency-scanner",
                                      "-explicit-module-build",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=Bar",
                                      "-I", path.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)
      
      // Resulting graph should contain the real module name Bar
      let dependencyGraphA = try driverA.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Bar"
      })
      XCTAssertFalse(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsA = try driverA.planBuild()
      XCTAssertTrue(plannedJobsA.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=Bar"))
      })

      // Module alias with the default scanner (driver scanner)
      var driverB = try Driver(args: ["swiftc",
                                      "-explicit-module-build",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=Bar",
                                      "-I", path.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)
      
      // Resulting graph should contain the real module name Bar
      let dependencyGraphB = try driverB.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Bar"
      })
      XCTAssertFalse(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsB = try driverB.planBuild()
      XCTAssertTrue(plannedJobsB.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=Bar"))
      })
    }
  }
  
  func testModuleAliasingInterfaceWithScanDeps() throws {
    try withTemporaryDirectory { path in
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")

      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      // Foo imports Car which is mapped to the real module Bar via
      // `-module-alias Car=E`; it allows Car (alias) to be referenced
      // in source files, while its contents are compiled as E (real
      // name on disk).
      let srcFoo = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(srcFoo) {
        $0 <<< "import Car\n"
      }

      // Module alias with the fallback scanner (frontend scanner)
      var driverA = try Driver(args: ["swiftc",
                                      "-nonlib-dependency-scanner",
                                      "-explicit-module-build",
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=E",
                                      "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)
      guard driverA.isFrontendArgSupported(.moduleAlias) else {
        throw XCTSkip("Skipping: compiler does not support '-module-alias'")
      }
      
      // Resulting graph should contain the real module name Bar
      let dependencyGraphA = try driverA.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "E"
      })
      XCTAssertFalse(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsA = try driverA.planBuild()
      XCTAssertTrue(plannedJobsA.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=E"))
      })

      // Module alias with the default scanner (driver scanner)
      var driverB = try Driver(args: ["swiftc",
                                      "-explicit-module-build",
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=E",
                                      "-working-directory", path.nativePathString(escaped: true),
                                      "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)
      
      // Resulting graph should contain the real module name Bar
      let dependencyGraphB = try driverB.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "E"
      })
      XCTAssertFalse(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsB = try driverB.planBuild()
      XCTAssertTrue(plannedJobsB.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=E"))
      })
    }
  }
  
  func testModuleAliasingWithImportPrescan() throws {
    let (_, _, toolchain, hostTriple) = try getDriverArtifactsForScanning()

    let dummyDriver = try Driver(args: ["swiftc", "-module-name", "dummyDriverCheck", "test.swift"])
    guard dummyDriver.isFrontendArgSupported(.moduleAlias) else {
      throw XCTSkip("Skipping: compiler does not support '-module-alias'")
    }

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

    try withTemporaryDirectory { path in
      let main = path.appending(component: "foo.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import Car;"
        $0 <<< "import Jet;"
      }
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let scannerCommand = ["-scan-dependencies",
                            "-import-prescan",
                            "-module-alias",
                            "Car=Bar",
                            main.nativePathString(escaped: true)] + sdkArgumentsForTesting

      let deps =
        try! dependencyOracle.getImports(workingDirectory: path,
                                         moduleAliases: ["Car": "Bar"],
                                         commandLine: scannerCommand)
      
      XCTAssertTrue(deps.imports.contains("Bar"))
      XCTAssertFalse(deps.imports.contains("Car"))
      XCTAssertTrue(deps.imports.contains("Jet"))
    }
  }
  
  func testModuleAliasingWithExplicitBuild() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let srcBar = path.appending(component: "bar.swift")
      let moduleBarPath = path.appending(component: "Bar.swiftmodule").nativePathString(escaped: true)
      try localFileSystem.writeFileContents(srcBar) {
        $0 <<< "public class KlassBar {}"
      }
      
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      var driver1 = try Driver(args: ["swiftc",
                                      "-explicit-module-build",
                                      "-module-name",
                                      "Bar",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      "-emit-module",
                                      "-emit-module-path", moduleBarPath,
                                      srcBar.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting,
                               env: ProcessEnv.vars)
      guard driver1.isFrontendArgSupported(.moduleAlias) else {
        throw XCTSkip("Skipping: compiler does not support '-module-alias'")
      }

      let jobs1 = try driver1.planBuild()
      try driver1.run(jobs: jobs1)
      XCTAssertFalse(driver1.diagnosticEngine.hasErrors)
      XCTAssertTrue(FileManager.default.fileExists(atPath: moduleBarPath))
      
      let srcFoo = path.appending(component: "foo.swift")
      let moduleFooPath = path.appending(component: "Foo.swiftmodule").nativePathString(escaped: true)

      // Module Foo imports Car but it's mapped to Bar (real name)
      // `-module-alias Car=Bar` allows Car (alias) to be referenced
      // in source files in Foo, but its contents will be compiled
      // as Bar (real name on-disk).
      try localFileSystem.writeFileContents(srcFoo) {
        $0 <<< "import Car\n"
        $0 <<< "func run() -> Car.KlassBar? { return nil }"
      }
      var driver2 = try Driver(args: ["swiftc",
                                      "-I", path.nativePathString(escaped: true),
                                      "-explicit-module-build",
                                      "-module-name",
                                      "Foo",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      "-emit-module",
                                      "-emit-module-path",
                                      moduleFooPath,
                                      "-module-alias",
                                      "Car=Bar",
                                      srcFoo.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                      ] + sdkArgumentsForTesting,
                               env: ProcessEnv.vars)
      let jobs2 = try driver2.planBuild()
      try driver2.run(jobs: jobs2)
      XCTAssertFalse(driver2.diagnosticEngine.hasErrors)
      XCTAssertTrue(FileManager.default.fileExists(atPath: moduleFooPath))
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

      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
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
    } else if driver.targetTriple.isWindows {
      if let sdkroot = try driver.toolchain.defaultSDKPath(driver.targetTriple) {
        return (sdkroot
                  .appending(component: "usr")
                  .appending(component: "lib")
                  .appending(component: "swift")
                  .appending(component: "windows")
                  // TODO(compnerd) this should be dropped, but we need to
                  // synchronize with the frontend and installer to ensure that
                  // everything is setup properly.  With the swiftmodule
                  // directory structure being supported, we no longer need to
                  // put the swiftmodules in the architecture directory, only
                  // the import libraries.
                  .appending(component: driver.targetTriple.archName),
                sdkroot
                  .appending(component: "usr")
                  .appending(component: "lib")
                  .appending(component: "swift")
                  .appending(component: "shims"))
      }
      return (toolchainRootPath
                .appending(component: "lib")
                .appending(component: "swift")
                .appending(component: driver.targetTriple.osNameUnversioned),
              toolchainRootPath
                .appending(component: "lib")
                .appending(component: "swift")
                .appending(component: "shims"))
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
    let driver = try Driver(args: ["swiftc", "-explicit-module-build",
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
      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let scannerCommand = ["-scan-dependencies",
                            "-import-prescan",
                            "-I", cHeadersPath.nativePathString(escaped: true),
                            "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                            "-I", stdLibPath.nativePathString(escaped: true),
                            "-I", shimsPath.nativePathString(escaped: true),
                            main.nativePathString(escaped: true)] + sdkArgumentsForTesting

      let imports =
        try! dependencyOracle.getImports(workingDirectory: path,
                                         commandLine: scannerCommand)
      let expectedImports = ["C", "E", "G", "Swift", "SwiftOnoneSupport"]
      // Dependnig on how recent the platform we are running on, the Concurrency module may or may not be present.
      let expectedImports2 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency"]
      XCTAssertTrue(Set(imports.imports) == Set(expectedImports) || Set(imports.imports) == Set(expectedImports2))
    }
  }


  /// Test that the scanner invocation does not rely in response files
  func testDependencyScanningNoResponse() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      // With a number of inputs this large, a response file should be generated
      // unless explicitly not supported, as should be the case for scan-deps.
      let lotsOfInputs = (0...700).map{"test\($0).swift"}
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + lotsOfInputs + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let scannerJob = try driver.dependencyScanningJob()

      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let (args, _) = try resolver.resolveArgumentList(for: scannerJob,
                                                       forceResponseFiles: false,
                                                       quotePaths: true)
      XCTAssertTrue(args.count > 1)
      XCTAssertFalse(args[0].hasSuffix(".resp"))
    }
  }

  /// Test the libSwiftScan dependency scanning.
  func testDependencyScanning() throws {
    let (stdlibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()

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

      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-import-objc-header",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly via libSwiftScan.
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }

      // Ensure we do not propagate the ususal PCH-handling arguments to the scanner invocation
      XCTAssertFalse(scannerCommand.contains("-pch-output-dir"))

      // Here purely to dump diagnostic output in a reasonable fashion when things go wrong.
      let lock = NSLock()

      // Module `X` is only imported on Darwin when:
      // #if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 110000
      let expectedNumberOfDependencies: Int
      if hostTriple.isMacOSX,
         hostTriple.version(for: .macOS) >= Triple.Version(11, 0, 0) {
        expectedNumberOfDependencies = 11
      } else if driver.targetTriple.isWindows {
        expectedNumberOfDependencies = 13
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
    let (stdlibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let cacheSavePath = path.appending(component: "saved.moddepcache")
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import C;"
        $0 <<< "import E;"
        $0 <<< "import G;"
      }

      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly via libSwiftScan.
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }

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
      return job.inputs.filter {$0.type == .swiftModule}.map { input in
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
        // Inputs include all the dependencies and the interface from where
        // the current module can be built.
        XCTAssertTrue(input.file.extension == "swiftmodule" ||
                      input.file.extension == "swiftinterface")
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

    let mockSDKPath: String =
        testInputsPath.appending(component: "mock-sdk.sdk").pathString
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
                                                                                into: path,
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
                                                                                into: path,
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
                                                                                into: path,
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
                                                                                into: path,
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
                                                                                into: path,
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

  func testABICheckWhileBuildingPrebuiltModule() throws {
    func checkABICheckingJob(_ job: Job) throws {
      XCTAssertTrue(job.kind == .compareABIBaseline)
      XCTAssertTrue(job.inputs.count == 2)
      let (baseline, current) = (job.inputs[0], job.inputs[1])
      XCTAssertTrue(baseline.type == .jsonABIBaseline)
      XCTAssertTrue(current.type == .jsonABIBaseline)
      XCTAssertTrue(current.file != baseline.file)
      XCTAssertTrue(current.file.basename == baseline.file.basename)
    }
    let mockSDKPath: String =
        testInputsPath.appending(component: "mock-sdk.sdk").pathString
    let baselineABIPath: String =
        testInputsPath.appending(component: "ABIBaselines").pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPath).absolutePath!, DiagnosticsEngine())
    let interfaceMap = try collector.collectSwiftInterfaceMap()
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import A\n"
      }
      let moduleCachePath = "/tmp/module-cache"
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                     "-module-cache-path", moduleCachePath
                                    ])
      let (jobs, _) = try driver.generatePrebuitModuleGenerationJobs(with: interfaceMap,
                                                                     into: path,
                                                                     exhaustive: true,
                                                                     currentABIDir: path.appending(component: "ABI"),
                                                                     baselineABIDir: VirtualPath(path: baselineABIPath).absolutePath)
      let compileJobs = jobs.filter {$0.kind == .compile}
      XCTAssertTrue(!compileJobs.isEmpty)
      XCTAssertTrue(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-compile-module-from-interface")) })
      XCTAssertTrue(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-emit-abi-descriptor-path")) })
      let abiCheckJobs = jobs.filter {$0.kind == .compareABIBaseline}
      try abiCheckJobs.forEach { try checkABICheckingJob($0) }
    }
  }
#endif
}
