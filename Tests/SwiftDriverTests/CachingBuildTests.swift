//===------- CachingModuleBuildTests.swift - Swift Driver Tests -----------===//
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

private var testInputsPath: AbsolutePath {
  get throws {
    var root: AbsolutePath = try AbsolutePath(validating: #file)
    while root.basename != "Tests" {
      root = root.parentDirectory
    }
    return root.parentDirectory.appending(component: "TestInputs")
  }
}

private func checkCachingBuildJob(job: Job,
                                  moduleId: ModuleDependencyId,
                                  dependencyGraph: InterModuleDependencyGraph)
throws {
  let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
  switch moduleInfo.details {
    case .swift(let swiftModuleDetails):
      XCTAssertTrue(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
      XCTAssertTrue(job.commandLine.contains(.flag(String("-cache-compile-job"))))
      XCTAssertTrue(job.commandLine.contains(.flag(String("-cas-path"))))
      let moduleInterfacePath =
        TypedVirtualPath(file: swiftModuleDetails.moduleInterfacePath!.path,
                         type: .swiftInterface)
      XCTAssertEqual(job.kind, .compileModuleFromInterface)
      XCTAssertTrue(job.inputs.contains(moduleInterfacePath))
      if let compiledCandidateList = swiftModuleDetails.compiledModuleCandidates {
        for compiledCandidate in compiledCandidateList {
          let candidatePath = compiledCandidate.path
          let typedCandidatePath = TypedVirtualPath(file: candidatePath,
                                                    type: .swiftModule)
          XCTAssertTrue(job.inputs.contains(typedCandidatePath))
          XCTAssertTrue(job.commandLine.contains(.flag(VirtualPath.lookup(candidatePath).description)))
        }
        XCTAssertEqual(job.commandLine.filter { $0 == .flag("-candidate-module-file") }.count, compiledCandidateList.count)
      }
      // make sure command-line from dep-scanner are included.
      let extraCommandLine = try XCTUnwrap(swiftModuleDetails.commandLine)
      for command in extraCommandLine {
        XCTAssertTrue(job.commandLine.contains(.flag(command)))
      }
    case .clang(_):
      XCTAssertEqual(job.kind, .generatePCM)
      XCTAssertEqual(job.description, "Compiling Clang module \(moduleId.moduleName)")
    case .swiftPrebuiltExternal(_):
      XCTFail("Unexpected prebuilt external module dependency found.")
    case .swiftPlaceholder(_):
      XCTFail("Placeholder dependency found.")
  }
  // Ensure the frontend was prohibited from doing implicit module builds
  XCTAssertTrue(job.commandLine.contains(.flag(String("-fno-implicit-modules"))))
  try checkCachingBuildJobDependencies(job: job,
                                       moduleInfo: moduleInfo,
                                       dependencyGraph: dependencyGraph)
}

/// Checks that the output keys are in the action cache and also the output
/// can be replayed from CAS and identicial to the original output.
private func checkCASForResults(jobs: [Job], cas: SwiftScanCAS, fs: FileSystem) throws {
  let expectation = XCTestExpectation(description: "Check CAS for output")
  @Sendable
  func replayAndVerifyOutput(_ job: Job, _ compilations: [CachedCompilation]) async throws {
    func hashFile(_ file: VirtualPath) throws -> String {
      // store the content in the CAS as a hashing function.
      return try fs.readFileContents(file).withData {
        try cas.store(data: $0)
      }
    }
    let outputHashes = try job.outputs.map {
      let hash = try hashFile($0.file)
      // remove the original output after hashing the file.
      try fs.removeFileTree($0.file)
      return hash
    }
    let resolver = try ArgsResolver(fileSystem: fs)
    let arguments: [String] = try resolver.resolveArgumentList(for: job.commandLine)
    let instance = try cas.createReplayInstance(commandLine: arguments)
    for compilation in compilations {
      let _ = try cas.replayCompilation(instance: instance, compilation: compilation)
    }
    let replayHashes = try job.outputs.map {
      try hashFile($0.file)
    }
    XCTAssertEqual(outputHashes, replayHashes, "replayed output is not identical to original")
  }
  Task {
    defer {
      expectation.fulfill()
    }
    for job in jobs {
      if !job.kind.supportCaching {
        continue
      }
      var compilations = [CachedCompilation]()
      for (_, key) in job.outputCacheKeys {
        if let compilation = try await cas.queryCacheKey(key, globally: false) {
          for output in compilation {
            XCTAssertTrue(output.isMaterialized, "Cached output not founded in CAS")
            let success = try await output.load()
            XCTAssertTrue(success, "Cached output not founded in CAS")

            // Try async download. Download should succeed even on a local CAS.
            let casID = try output.getCASID()
            let downloaded = try await cas.download(with: casID)
            XCTAssertTrue(downloaded, "Cached output cannot be downloaded")
          }
          // Execise the uploading path.
          try await compilation.makeGlobal()
          // Execise call back uploading method.
          compilation.makeGlobal { error in
            XCTAssertNil(error, "Upload Error")
          }
          compilations.append(compilation)
        } else {
          XCTFail("Cached entry not found")
        }
      }
      try await replayAndVerifyOutput(job, compilations)
    }
  }
  let result = XCTWaiter.wait(for: [expectation], timeout: 10.0)
  XCTAssertEqual(result, .completed)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkCachingBuildJobDependencies(job: Job,
                                              moduleInfo : ModuleInfo,
                                              dependencyGraph: InterModuleDependencyGraph
) throws {
  let validateSwiftCommandLineDependency: (ModuleDependencyId, SwiftModuleDetails) throws -> Void = { dependencyId, dependencyDetails in
    let cacheKey = try XCTUnwrap(dependencyDetails.moduleCacheKey)
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-swift-module-file=\(dependencyId.moduleName)=\(cacheKey)"))))
  }

  let validateBinaryCommandLineDependency: (ModuleDependencyId, SwiftPrebuiltExternalModuleDetails) throws -> Void = { dependencyId, dependencyDetails in
    let cacheKey = try XCTUnwrap(dependencyDetails.moduleCacheKey)
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-swift-module-file=\(dependencyId.moduleName)=\(cacheKey)"))))
  }

  let validateClangCommandLineDependency: (ModuleDependencyId,
                                           ModuleInfo,
                                           ClangModuleDetails) throws -> Void = { dependencyId, dependencyInfo, clangDependencyDetails  in
    let clangDependencyModulePathString = dependencyInfo.modulePath.path
    let clangDependencyModulePath =
      TypedVirtualPath(file: clangDependencyModulePathString, type: .pcm)
    XCTAssertTrue(job.inputs.contains(clangDependencyModulePath))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-fmodule-file=\(dependencyId.moduleName)=\(clangDependencyModulePathString)"))))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-fmodule-file-cache-key"))))
    let cacheKey = try XCTUnwrap(clangDependencyDetails.moduleCacheKey)
    XCTAssertTrue(job.commandLine.contains(.flag(String(cacheKey))))
  }

  for dependencyId in moduleInfo.allDependencies {
    let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)
    switch dependencyInfo.details {
      case .swift(let swiftDependencyDetails):
        try validateSwiftCommandLineDependency(dependencyId, swiftDependencyDetails)
      case .swiftPrebuiltExternal(let swiftDependencyDetails):
        try validateBinaryCommandLineDependency(dependencyId, swiftDependencyDetails)
      case .clang(let clangDependencyDetails):
        try validateClangCommandLineDependency(dependencyId, dependencyInfo, clangDependencyDetails)
      case .swiftPlaceholder(_):
        XCTFail("Placeholder dependency found.")
    }

    // Ensure all transitive dependencies got added as well.
    for transitiveDependencyId in dependencyInfo.allDependencies {
      try checkCachingBuildJobDependencies(job: job,
                                           moduleInfo: try dependencyGraph.moduleInfo(of: transitiveDependencyId),
                                           dependencyGraph: dependencyGraph)

    }
  }
}


final class CachingBuildTests: XCTestCase {
  let dependencyOracle = InterModuleDependencyOracle()

  override func setUpWithError() throws {
    try super.setUpWithError()

    // If the toolchain doesn't support caching, skip directly.
    let driver = try Driver(args: ["swiftc"])
#if os(Windows)
    throw XCTSkip("caching not supported on windows")
#else
    guard driver.isFeatureSupported(.compilation_caching) else {
      throw XCTSkip("caching not supported")
    }
#endif
  }

  private func pathMatchesSwiftModule(path: VirtualPath, _ name: String) -> Bool {
    return path.basenameWithoutExt.starts(with: "\(name)-") &&
           path.extension! == FileType.swiftModule.rawValue
  }

  func testCachingBuildJobs() throws {
    let (stdlibPath, shimsPath, _, hostTriple) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testCachingBuildJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;import E;import G;")
      }
      let casPath = path.appending(component: "cas")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testCachingBuildJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkCachingBuildJob(job: job, moduleId: .swift("A"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "E") {
            try checkCachingBuildJob(job: job, moduleId: .swift("E"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "G") {
            try checkCachingBuildJob(job: job, moduleId: .swift("G"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkCachingBuildJob(job: job, moduleId: .swift("Swift"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkCachingBuildJob(job: job, moduleId: .swift("_Concurrency"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_StringProcessing") {
            try checkCachingBuildJob(job: job, moduleId: .swift("_StringProcessing"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkCachingBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                     dependencyGraph: dependencyGraph)
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          let relativeOutputPathFileName = outputFilePath.basename
          if relativeOutputPathFileName.starts(with: "A-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("A"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "B-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("B"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "C-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("C"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "G-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("G"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "D-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("D"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "F-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("F"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "SwiftShims-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "_SwiftConcurrencyShims-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("_SwiftConcurrencyShims"),
                                     dependencyGraph: dependencyGraph)
          }
          else if hostTriple.isMacOSX,
             hostTriple.version(for: .macOS) < Triple.Version(11, 0, 0),
             relativeOutputPathFileName.starts(with: "X-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("X"),
                                     dependencyGraph: dependencyGraph)
          }
          else {
            XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try RelativePath(validating: "testCachingBuildJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .absolute(let path):
              XCTAssertEqual(path.basename, "testCachingBuildJobs")
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testCachingBuildJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink") ||
                            matchTemporary(outputFilePath, basename: "", fileExtension: "pch"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  func testModuleOnlyJob() throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testModuleOnlyJob.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;import E;")
      }
      let other = path.appending(component: "testModuleOnlyJob2.swift")
      try localFileSystem.writeFileContents(other) {
        $0.send("import G;")
      }
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let casPath = path.appending(component: "cas")
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let swiftInterfacePath: AbsolutePath = path.appending(component: "testModuleOnlyJob.swiftinterface")
      let privateSwiftInterfacePath: AbsolutePath = path.appending(component: "testModuleOnlyJob.private.swiftinterface")
      let modulePath: AbsolutePath = path.appending(component: "testModuleOnlyJob.swiftmodule")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-module-name", "ModuleOnly",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: true),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-emit-module-separately-wmo", "-disable-cmo", "-Rcache-compile-job",
                                     "-enable-library-evolution", "-O", "-whole-module-optimization",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-emit-module", "-o", modulePath.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true), other.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      for job in jobs {
          XCTAssertFalse(job.outputCacheKeys.isEmpty)
      }
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)

      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        XCTAssertEqual(cas, driverCAS, "CAS should only be created once")
      } else {
        XCTFail("Cached compilation doesn't have a CAS")
      }
      try checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  func testSeparateModuleJob() throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testSeparateModuleJob.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;import E;")
      }
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let casPath = path.appending(component: "cas")
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let swiftInterfacePath: AbsolutePath = path.appending(component: "testSeparateModuleJob.swiftinterface")
      let privateSwiftInterfacePath: AbsolutePath = path.appending(component: "testSeparateModuleJob.private.swiftinterface")
      let modulePath: AbsolutePath = path.appending(component: "testSeparateModuleJob.swiftmodule")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-module-name", "SeparateModuleJob",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-emit-module-path", modulePath.nativePathString(escaped: true),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: true),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-experimental-emit-module-separately", "-Rcache-compile-job",
                                     "-enable-library-evolution", "-O",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                     "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try driver.planBuild()
      for job in jobs {
          XCTAssertFalse(job.outputCacheKeys.isEmpty)
      }
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)

      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        XCTAssertEqual(cas, driverCAS, "CAS should only be created once")
      } else {
        XCTFail("Cached compilation doesn't have a CAS")
      }
      try checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build, -verify-emitted-module-interface and -enable-library-evolution.
  func testExplicitModuleVerifyInterfaceJobs() throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;import E;import G;")
      }

      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let casPath = path.appending(component: "cas")
      let swiftInterfacePath: AbsolutePath = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.swiftinterface")
      let privateSwiftInterfacePath: AbsolutePath = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.private.swiftinterface")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: true),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-verify-emitted-module-interface",
                                     "-enable-library-evolution",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      guard driver.supportExplicitModuleVerifyInterface() else {
        throw XCTSkip("-typecheck-module-from-interface doesn't support explicit build.")
      }

      let jobs = try driver.planBuild()
      // Figure out which Triples to use.
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleVerifyInterfaceJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        if (job.outputs.count == 0) {
          // This is the verify module job as it should be the only job scheduled to have no output.
          XCTAssertEqual(job.kind, .verifyModuleInterface)
          // Check the explicit module flags exists.
          XCTAssertTrue(job.commandLine.contains(.flag(String("-explicit-interface-module-build"))))
          XCTAssertTrue(job.commandLine.contains(.flag(String("-explicit-swift-module-map-file"))))
          XCTAssertTrue(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
          XCTAssertTrue(job.commandLine.contains(.flag(String("-input-file-key"))))
          continue
        }
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkCachingBuildJob(job: job, moduleId: .swift("A"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "E") {
            try checkCachingBuildJob(job: job, moduleId: .swift("E"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "G") {
            try checkCachingBuildJob(job: job, moduleId: .swift("G"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkCachingBuildJob(job: job, moduleId: .swift("Swift"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkCachingBuildJob(job: job, moduleId: .swift("_Concurrency"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_StringProcessing") {
            try checkCachingBuildJob(job: job, moduleId: .swift("_StringProcessing"),
                                     dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkCachingBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                     dependencyGraph: dependencyGraph)
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          let relativeOutputPathFileName = outputFilePath.basename
          if relativeOutputPathFileName.starts(with: "A-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("A"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "B-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("B"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "C-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("C"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "D-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("D"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "G-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("G"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "F-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("F"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "SwiftShims-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                     dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "_SwiftConcurrencyShims-") {
            try checkCachingBuildJob(job: job, moduleId: .clang("_SwiftConcurrencyShims"),
                                     dependencyGraph: dependencyGraph)
          }
          else {
            XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try RelativePath(validating: "testExplicitModuleVerifyInterfaceJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .absolute(let path):
              XCTAssertEqual(path.basename, "testExplicitModuleVerifyInterfaceJobs")
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testExplicitModuleVerifyInterfaceJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }


  func testCacheBuildEndToEndBuild() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      let casPath = path.appending(component: "cas")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testCachingBuild.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;import E;import G;")
      }

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-Rcache-compile-job",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)

      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        XCTAssertEqual(cas, driverCAS, "CAS should only be created once")
      } else {
        XCTFail("Cached compilation doesn't have a CAS")
      }
      try checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  func testCacheBuildEndToEndWithBinaryHeaderDeps() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let PCHPath = path.appending(component: "PCH")
      try localFileSystem.createDirectory(PCHPath)
      let FooInstallPath = path.appending(component: "Foo")
      try localFileSystem.createDirectory(FooInstallPath)
      let foo = path.appending(component: "foo.swift")
      let casPath = path.appending(component: "cas")
      try localFileSystem.writeFileContents(foo) {
        $0.send("extension Profiler {")
        $0.send("    public static let count: Int = 42")
        $0.send("}")
      }
      let fooHeader = path.appending(component: "foo.h")
      try localFileSystem.writeFileContents(fooHeader) {
        $0.send("struct Profiler { void* ptr; };")
      }
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import Foo")
      }
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      var fooBuildDriver = try Driver(args: ["swiftc",
                                             "-explicit-module-build",
                                             "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                             "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                             "-working-directory", path.nativePathString(escaped: true),
                                             foo.nativePathString(escaped: true),
                                             "-emit-module", "-wmo", "-module-name", "Foo",
                                             "-emit-module-path", FooInstallPath.nativePathString(escaped: true),
                                             "-import-objc-header", fooHeader.nativePathString(escaped: true),
                                             "-pch-output-dir", PCHPath.nativePathString(escaped: true),
                                             FooInstallPath.appending(component: "Foo.swiftmodule").nativePathString(escaped: true)]
                                      + sdkArgumentsForTesting,
                                      interModuleDependencyOracle: dependencyOracle)

      let scanLibPath = try XCTUnwrap(fooBuildDriver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      guard try dependencyOracle.supportsBinaryModuleHeaderDependencies() else {
        throw XCTSkip("libSwiftScan does not support binary module header dependencies.")
      }

      let fooJobs = try fooBuildDriver.planBuild()
      try fooBuildDriver.run(jobs: fooJobs)
      XCTAssertFalse(fooBuildDriver.diagnosticEngine.hasErrors)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = fooBuildDriver.cas {
        XCTAssertEqual(cas, driverCAS, "CAS should only be created once")
      } else {
        XCTFail("Cached compilation doesn't have a CAS")
      }
      try checkCASForResults(jobs: fooJobs, cas: cas, fs: fooBuildDriver.fileSystem)

      var driver = try Driver(args: ["swiftc",
                                     "-I", FooInstallPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-emit-module", "-emit-module-path",
                                     path.appending(component: "testEMBETEWBHD.swiftmodule").nativePathString(escaped: true),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try driver.planBuild()
      for job in jobs {
        XCTAssertFalse(job.outputCacheKeys.isEmpty)
      }
      if driver.isFrontendArgSupported(.autoBridgingHeaderChaining) {
        XCTAssertTrue(jobs.contains { $0.kind == .generatePCH })
        try driver.run(jobs: jobs)
        XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      }
    }
  }

  func testDependencyScanning() throws {
    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;import E;import G;")
      }
      let vfsoverlay = path.appending(component: "overlay.yaml")
      try localFileSystem.writeFileContents(vfsoverlay) {
        $0.send("{\"case-sensitive\":\"false\",\"roots\":[],\"version\":0}")
      }

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let casPath = path.appending(component: "cas")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "/tmp/Foo.o",
                                     "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-Xcc", "-ivfsoverlay", "-Xcc", vfsoverlay.nativePathString(escaped: true),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly via libSwiftScan.
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }

      // Ensure we do not propagate the usual PCH-handling arguments to the scanner invocation
      XCTAssertFalse(scannerCommand.contains("-pch-output-dir"))
      XCTAssertFalse(scannerCommand.contains("Foo.o"))

      // Xcc commands are used for scanner command.
      XCTAssertTrue(scannerCommand.contains("-Xcc"))
      XCTAssertTrue(scannerCommand.contains("-ivfsoverlay"))

      // Here purely to dump diagnostic output in a reasonable fashion when things go wrong.
      let lock = NSLock()

      // Module `X` is only imported on Darwin when:
      // #if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 110000
      let expectedNumberOfDependencies: Int
      if driver.hostTriple.isMacOSX,
         driver.hostTriple.version(for: .macOS) < Triple.Version(11, 0, 0) {
        expectedNumberOfDependencies = 13
      } else if driver.targetTriple.isWindows {
        expectedNumberOfDependencies = 15
      } else {
        expectedNumberOfDependencies = 12
      }

      // Dispatch several iterations in parallel
      DispatchQueue.concurrentPerform(iterations: 20) { index in
        // Give the main modules different names
        let iterationCommand = scannerCommand + ["-module-name",
                                                 "testDependencyScanning\(index)",
                                                 // FIXME: We need to differentiate the scanning action hash,
                                                 // though the module-name above should be sufficient.
                                                 "-I/tmp/foo/bar/\(index)"]
        do {
          var scanDiagnostics: [ScannerDiagnosticPayload] = []
          let dependencyGraph =
            try dependencyOracle.getDependencies(workingDirectory: path,
                                                 commandLine: iterationCommand,
                                                 diagnostics: &scanDiagnostics)

          // The _Concurrency and _StringProcessing modules are automatically
          // imported in newer versions of the Swift compiler. If they happened to
          // be provided, adjust our expectations accordingly.
          let hasConcurrencyModule = dependencyGraph.modules.keys.contains {
            $0.moduleName == "_Concurrency"
          }
          let hasConcurrencyShimsModule = dependencyGraph.modules.keys.contains {
            $0.moduleName == "_SwiftConcurrencyShims"
          }
          let hasStringProcessingModule = dependencyGraph.modules.keys.contains {
            $0.moduleName == "_StringProcessing"
          }
          let adjustedExpectedNumberOfDependencies =
              expectedNumberOfDependencies +
              (hasConcurrencyModule ? 1 : 0) +
              (hasConcurrencyShimsModule ? 1 : 0) +
              (hasStringProcessingModule ? 1 : 0)

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
        } catch {
          XCTFail("Unexpected error: \(error)")
        }
      }

      // Change CAS path is an error.
      let casPath2 = path.appending(component: "cas2")
      let command = scannerCommand + ["-module-name",
                                      "testDependencyScanningBad",
                                      // FIXME: We need to differentiate the scanning action hash,
                                      // though the module-name above should be sufficient.
                                      "-I/tmp/bad",
                                      "-cas-path", casPath2.nativePathString(escaped: true),
                                      ]
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      do {
        let _ = try dependencyOracle.getDependencies(workingDirectory: path,
                                                     commandLine: command,
                                                     diagnostics: &scanDiagnostics)
      } catch let error {
        XCTAssertTrue(error is DependencyScanningError)
      }

      let testDiagnostics: [ScannerDiagnosticPayload]
      if try dependencyOracle.supportsPerScanDiagnostics(),
         !scanDiagnostics.isEmpty {
        testDiagnostics = scanDiagnostics
        print("Using Per-Scan diagnostics")
      } else {
        testDiagnostics = try XCTUnwrap(dependencyOracle.getScannerDiagnostics())
        print("Using Scanner-Global diagnostics")
      }

      XCTAssertEqual(testDiagnostics.count, 1)
      XCTAssertEqual(testDiagnostics[0].severity, .error)
    }
  }

  func testDependencyScanningPathRemap() throws {
    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;")
        $0.send("import E;")
        $0.send("import G;")
      }

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let casPath = path.appending(component: "cas")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let mockBlocklistDir = try testInputsPath.appending(components: "Dummy.xctoolchain", "usr", "bin")
      var env = ProcessEnv.vars
      env["_SWIFT_DRIVER_MOCK_BLOCK_LIST_DIR"] = mockBlocklistDir.nativePathString(escaped: true)
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-g", "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-disable-clang-target", "-scanner-prefix-map-sdk", "/^sdk",
                                     "-scanner-prefix-map-toolchain", "/^toolchain",
                                     "-scanner-prefix-map", testInputsPath.description + "=/^src",
                                     "-scanner-prefix-map", path.description + "=/^tmp",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: env,
                              interModuleDependencyOracle: dependencyOracle)
      guard driver.isFrontendArgSupported(.scannerPrefixMap) else {
        throw XCTSkip("frontend doesn't support prefix map")
      }
      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }

      XCTAssertTrue(scannerCommand.contains("-scanner-prefix-map"))
      XCTAssertTrue(scannerCommand.contains(try testInputsPath.description + "=/^src"))

      let jobs = try driver.planBuild()
      for job in jobs {
        if !job.kind.supportCaching {
          continue
        }
        let command = try job.commandLine.map { try resolver.resolve($0) }
        // Check all the arguments that are in the temporary directory are remapped.
        // The only one that is not remapped should be the `-cas-path` that points to
        // `casPath`.
        XCTAssertFalse(command.contains {
          $0.starts(with: path.description) && $0 != casPath.description
        })
        /// All source location path should be remapped as well.
        XCTAssertFalse(try command.contains {
          $0.starts(with: try testInputsPath.description)
        })
        /// command-line that compiles swift should contains -cache-replay-prefix-map
        XCTAssertTrue(command.contains { $0 == "-cache-replay-prefix-map" })
        XCTAssertFalse(command.contains { $0 == "-plugin-path" || $0 == "-external-plugin-path" ||
                                          $0 == "-load-plugin-library" || $0 == "-load-plugin-executable" })
      }

      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
    }
  }

  func testCacheIncrementalBuildPlan() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      let casPath = path.appending(component: "cas")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testCachingBuild.swift")
      let mainFileContent = "import C;import E;import G;"
      try localFileSystem.writeFileContents(main) {
        $0.send(mainFileContent)
      }
      let ofm = path.appending(component: "ofm.json")
      let inputPathsAndContents: [(AbsolutePath, String)] = [(main, mainFileContent)]
      OutputFileMapCreator.write(
        module: "Test", inputPaths: inputPathsAndContents.map {$0.0},
        derivedData: path, to: ofm, excludeMainEntry: false)

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-Rcache-compile-job", "-incremental",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     "-output-file-map", ofm.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)

      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        XCTAssertEqual(cas, driverCAS, "CAS should only be created once")
      } else {
        XCTFail("Cached compilation doesn't have a CAS")
      }
      try checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  func testCacheBatchBuildPlan() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      let casPath = path.appending(component: "cas")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testCachingBuild.swift")
      let mainFileContent = "import C;import E;import G;"
      try localFileSystem.writeFileContents(main) {
        $0.send(mainFileContent)
      }
      let ofm = path.appending(component: "ofm.json")
      let inputPathsAndContents: [(AbsolutePath, String)] = [(main, mainFileContent)]
      OutputFileMapCreator.write(
        module: "Test", inputPaths: inputPathsAndContents.map {$0.0},
        derivedData: path, to: ofm, excludeMainEntry: false)

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-Rcache-compile-job", "-incremental",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     "-output-file-map", ofm.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)

      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        XCTAssertEqual(cas, driverCAS, "CAS should only be created once")
      } else {
        XCTFail("Cached compilation doesn't have a CAS")
      }
      try checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  func testDeterministicCheck() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      let casPath = path.appending(component: "cas")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testCachingBuild.swift")
      let mainFileContent = "import C;"
      try localFileSystem.writeFileContents(main) {
        $0.send(mainFileContent)
      }
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-enable-deterministic-check",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try driver.planBuild()
      jobs.forEach { job in
        guard job.kind == .compile else {
          return
        }
        XCTAssertJobInvocationMatches(job,
                                      .flag("-enable-deterministic-check"),
                                      .flag("-always-compile-output-files"),
                                      .flag("-cache-disable-replay"))
      }
    }

  }

  func testCASManagement() throws {
    try withTemporaryDirectory { path in
      let casPath = path.appending(component: "cas")
      let driver = try Driver(args: ["swiftc"])
      let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      guard cas.supportsSizeManagement else {
        throw XCTSkip("CAS size management is not supported")
      }
      let preSize = try XCTUnwrap(try cas.getStorageSize())
      let dataToStore = Data(count: 1000)
      _ = try cas.store(data: dataToStore)
      let postSize = try XCTUnwrap(try cas.getStorageSize())
      XCTAssertTrue(postSize > preSize)

      // Try prune.
      try cas.setSizeLimit(100)
      try cas.prune()
    }
  }

  func testCASSizeLimiting() throws {
    try withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      let casPath = path.appending(component: "cas")
      try localFileSystem.createDirectory(moduleCachePath)

      let main1 = path.appending(component: "testCachingBuild1.swift")
      try localFileSystem.writeFileContents(main1) { $0.send("let x = 1") }
      let main2 = path.appending(component: "testCachingBuild2.swift")
      try localFileSystem.writeFileContents(main2) { $0.send("let x = 1") }

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      func createDriver(main: AbsolutePath) throws -> Driver {
        return try Driver(args: ["swiftc",
                                 "-I", cHeadersPath.nativePathString(escaped: true),
                                 "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                 "-explicit-module-build", "-Rcache-compile-job",
                                 "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                 "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                 "-working-directory", path.nativePathString(escaped: true),
                                 main.nativePathString(escaped: true)] + sdkArgumentsForTesting)
      }

      func buildAndGetSwiftCASKeys(main: AbsolutePath, forceCASLimit: Bool) throws -> [String] {
        var driver = try createDriver(main: main)
        let cas = try XCTUnwrap(driver.cas)
        if forceCASLimit {
          try cas.setSizeLimit(10)
        }
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
        XCTAssertFalse(driver.diagnosticEngine.hasErrors)

        let dependencyOracle = driver.interModuleDependencyOracle

        let scanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
        try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

        var keys: [String] = []
        for job in jobs {
          guard job.kind.supportCaching else { continue }
          for (path, key) in job.outputCacheKeys {
            if path.type == .swift {
              keys.append(key)
            }
          }
        }
        return keys
      }

      func verifyKeys(exist: Bool, keys: [String], main: AbsolutePath, file: StaticString = #file, line: UInt = #line) throws {
        let driver = try createDriver(main: main)
        let cas = try XCTUnwrap(driver.cas)
        for key in keys {
          let comp = try cas.queryCacheKey(key, globally: false)
          if exist {
            XCTAssertNotNil(comp, file: file, line: line)
          } else {
            XCTAssertNil(comp, file: file, line: line)
          }
        }
      }

      do {
        // Without CAS size limitation the keys will be preserved.
        let keys = try buildAndGetSwiftCASKeys(main: main1, forceCASLimit: false)
        _ = try buildAndGetSwiftCASKeys(main: main2, forceCASLimit: false)
        try verifyKeys(exist: true, keys: keys, main: main1)
      }

      try localFileSystem.removeFileTree(casPath)

      do {
        // 2 separate builds with CAS size limiting, the keys of first build will not be preserved.
        let keys = try buildAndGetSwiftCASKeys(main: main1, forceCASLimit: true)
        _ = try buildAndGetSwiftCASKeys(main: main2, forceCASLimit: true)
        try verifyKeys(exist: false, keys: keys, main: main1)
      }
    }
  }
}
