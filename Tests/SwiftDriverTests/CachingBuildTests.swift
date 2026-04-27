//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(Testing) @preconcurrency import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TSCBasic
import Testing
import TestUtilities

private func checkCachingBuildJob(job: Job,
                                  moduleId: ModuleDependencyId,
                                  dependencyGraph: InterModuleDependencyGraph)
throws {
  let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
  switch moduleInfo.details {
    case .swift(let swiftModuleDetails):
      #expect(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
      #expect(job.commandLine.contains(.flag(String("-cache-compile-job"))))
      #expect(job.commandLine.contains(.flag(String("-cas-path"))))
      let moduleInterfacePath =
        TypedVirtualPath(file: swiftModuleDetails.moduleInterfacePath!.path,
                         type: .swiftInterface)
      #expect(job.kind == .compileModuleFromInterface)
      #expect(job.inputs.contains(moduleInterfacePath))
      if let compiledCandidateList = swiftModuleDetails.compiledModuleCandidates {
        for compiledCandidate in compiledCandidateList {
          let candidatePath = compiledCandidate.path
          let typedCandidatePath = TypedVirtualPath(file: candidatePath,
                                                    type: .swiftModule)
          #expect(job.inputs.contains(typedCandidatePath))
          #expect(job.commandLine.contains(.flag(VirtualPath.lookup(candidatePath).description)))
        }
        #expect(job.commandLine.filter { $0 == .flag("-candidate-module-file") }.count == compiledCandidateList.count)
      }
      // make sure command-line from dep-scanner are included.
      let extraCommandLine = try #require(swiftModuleDetails.commandLine)
      for command in extraCommandLine {
        #expect(job.commandLine.contains(.flag(command)))
      }
    case .clang(_):
      #expect(job.kind == .generatePCM)
      #expect(job.description == "Compiling Clang module \(moduleId.moduleName)")
    case .swiftPrebuiltExternal(_):
      Issue.record("Unexpected prebuilt external module dependency found.")
  }
  // Ensure the frontend was prohibited from doing implicit module builds
  #expect(job.commandLine.contains(.flag(String("-fno-implicit-modules"))))
  try checkCachingBuildJobDependencies(job: job,
                                       moduleInfo: moduleInfo,
                                       dependencyGraph: dependencyGraph)
}

/// Checks that the output keys are in the action cache and also the output
/// can be replayed from CAS and identicial to the original output.
private func checkCASForResults(jobs: [Job], cas: SwiftScanCAS, fs: FileSystem) async throws {
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
    #expect(outputHashes == replayHashes, "replayed output is not identical to original")
  }
  for job in jobs {
    if !job.kind.supportCaching {
      continue
    }
    var compilations = [CachedCompilation]()
    for (_, key) in job.outputCacheKeys {
      if let compilation = try await cas.queryCacheKey(key, globally: false) {
        for output in compilation {
          #expect(output.isMaterialized, "Cached output not founded in CAS")
          let success = try await output.load()
          #expect(success, "Cached output not founded in CAS")

          // Try async download. Download should succeed even on a local CAS.
          let casID = try output.getCASID()
          let downloaded = try await cas.download(with: casID)
          #expect(downloaded, "Cached output cannot be downloaded")
        }
        // Execise the uploading path.
        try await compilation.makeGlobal()
        // Execise call back uploading method.
        compilation.makeGlobal { error in
          #expect(error == nil, "Upload Error")
        }
        compilations.append(compilation)
      } else {
        Issue.record("Cached entry not found")
      }
    }
    try await replayAndVerifyOutput(job, compilations)
  }
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkCachingBuildJobDependencies(job: Job,
                                              moduleInfo : ModuleInfo,
                                              dependencyGraph: InterModuleDependencyGraph
) throws {
  let validateSwiftCommandLineDependency: (ModuleDependencyId, SwiftModuleDetails) throws -> Void = { dependencyId, dependencyDetails in
    let cacheKey = try #require(dependencyDetails.moduleCacheKey)
    #expect(job.commandLine.contains(
      .flag(String("-swift-module-file=\(dependencyId.moduleName)=\(cacheKey)"))))
  }

  let validateBinaryCommandLineDependency: (ModuleDependencyId, SwiftPrebuiltExternalModuleDetails) throws -> Void = { dependencyId, dependencyDetails in
    let cacheKey = try #require(dependencyDetails.moduleCacheKey)
    #expect(job.commandLine.contains(
      .flag(String("-swift-module-file=\(dependencyId.moduleName)=\(cacheKey)"))))
  }

  let validateClangCommandLineDependency: (ModuleDependencyId,
                                           ModuleInfo,
                                           ClangModuleDetails) throws -> Void = { dependencyId, dependencyInfo, clangDependencyDetails  in
    let clangDependencyModulePathString = dependencyInfo.modulePath.path
    let clangDependencyModulePath =
      TypedVirtualPath(file: clangDependencyModulePathString, type: .pcm)
    #expect(job.inputs.contains(clangDependencyModulePath))
    #expect(job.commandLine.contains(
      .flag(String("-fmodule-file-cache-key"))))
    let cacheKey = try #require(clangDependencyDetails.moduleCacheKey)
    #expect(job.commandLine.contains(.flag(String(cacheKey))))
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
    }
  }
}


@Suite(.enabled(if: cachingFeatureSupported, "caching not supported"))
struct CachingBuildTests {

  @Test func cachingBuildJobs() async throws {
    let (stdlibPath, shimsPath, _, hostTriple) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
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
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testCachingBuildJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        Issue.record("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        #expect(job.outputs.count == 1)
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if let outputExtension = outputFilePath.extension,
            outputExtension == FileType.swiftModule.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "E", "G"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .swift(String(module)),
                                     dependencyGraph: dependencyGraph)
          case let .some(module) where ["Swift", "_Concurrency", "_StringProcessing", "SwiftOnoneSupport"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .swift(String(module)),
                                     dependencyGraph: dependencyGraph)
          default:
            break
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "B", "C", "G", "D", "F"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .clang(String(module)),
                                     dependencyGraph: dependencyGraph)
          case let .some(module) where ["SwiftShims", "_SwiftConcurrencyShims"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .clang(String(module)),
                                     dependencyGraph: dependencyGraph)
          case let .some(module) where ["SAL", "_Builtin_intrinsics", "_Builtin_stddef", "_stdlib", "_malloc", "corecrt", "vcruntime"].contains(module):
            guard hostTriple.isWindows else {
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
              return
            }
            try checkCachingBuildJob(job: job, moduleId: .clang(String(module)),
                                     dependencyGraph: dependencyGraph)
          case "X":
            guard hostTriple.isMacOSX,
               hostTriple.version(for: .macOS) >= Triple.Version(11, 0, 0) else {
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
              return
            }
            try checkCachingBuildJob(job: job, moduleId: .clang("X"),
                                     dependencyGraph: dependencyGraph)
          default:
            Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try RelativePath(validating: "testCachingBuildJobs")),
                 .relative(try RelativePath(validating: "testCachingBuildJobs.exe")):
              #expect(driver.isExplicitMainModuleJob(job: job))
              #expect(job.kind == .link)
            case .absolute(let path):
              #expect(path.basename == "testCachingBuildJobs")
              #expect(job.kind == .link)
            case .temporary(_):
              let baseName = "testCachingBuildJobs"
              #expect(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink") ||
                            matchTemporary(outputFilePath, basename: "", fileExtension: "pch"))
            default:
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  @Test func moduleOnlyJob() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
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
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc",
                                     "-swift-version", "5",
                                     "-module-name", "ModuleOnly",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: false),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-emit-module-separately-wmo", "-disable-cmo", "-Rcache-compile-job",
                                     "-enable-library-evolution", "-O", "-whole-module-optimization",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-emit-module", "-o", modulePath.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false), other.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      for job in jobs {
          #expect(!job.outputCacheKeys.isEmpty)
      }
      #expect(!driver.diagnosticEngine.hasErrors)

      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        #expect(cas == driverCAS, "CAS should only be created once")
      } else {
        Issue.record("Cached compilation doesn't have a CAS")
      }
      try await checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  @Test func separateModuleJob() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
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
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc",
                                     "-swift-version", "5",
                                     "-module-name", "SeparateModuleJob",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-emit-module-path", modulePath.nativePathString(escaped: false),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: false),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-experimental-emit-module-separately", "-Rcache-compile-job",
                                     "-enable-library-evolution", "-O",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                     "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try await driver.planBuild()
      for job in jobs {
          #expect(!job.outputCacheKeys.isEmpty)
      }
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        #expect(cas == driverCAS, "CAS should only be created once")
      } else {
        Issue.record("Cached compilation doesn't have a CAS")
      }
      try await checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build, -verify-emitted-module-interface and -enable-library-evolution.
  @Test(.requireExplicitModuleVerifyInterface()) func explicitModuleVerifyInterfaceJobs() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
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
      var driver = try TestDriver(args: ["swiftc",
                                     "-swift-version", "5",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: false),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-verify-emitted-module-interface",
                                     "-enable-library-evolution",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)

      let jobs = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleVerifyInterfaceJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        Issue.record("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        if (job.outputs.count == 0) {
          // This is the verify module job as it should be the only job scheduled to have no output.
          #expect(job.kind == .verifyModuleInterface)
          // Check the explicit module flags exists.
          #expect(job.commandLine.contains(.flag(String("-explicit-interface-module-build"))))
          #expect(job.commandLine.contains(.flag(String("-explicit-swift-module-map-file"))))
          #expect(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
          #expect(job.commandLine.contains(.flag(String("-input-file-key"))))
          continue
        }
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if let outputExtension = outputFilePath.extension,
            outputExtension == FileType.swiftModule.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "E", "G"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .swift(String(module)),
                                     dependencyGraph: dependencyGraph)
          case let .some(module) where ["Swift", "_Concurrency", "_StringProcessing", "SwiftOnoneSupport"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .swift(String(module)),
                                     dependencyGraph: dependencyGraph)
          default:
            break
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "B", "C", "D", "G", "F"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .clang(String(module)),
                                     dependencyGraph: dependencyGraph)
          case let .some(module) where ["SwiftShims", "_SwiftConcurrencyShims"].contains(module):
            try checkCachingBuildJob(job: job, moduleId: .clang(String(module)),
                                     dependencyGraph: dependencyGraph)
          case let .some(module) where ["SAL", "_Builtin_intrinsics", "_Builtin_stddef", "_stdlib", "_malloc", "corecrt", "vcruntime"].contains(module):
            guard driver.hostTriple.isWindows else { fallthrough }
            try checkCachingBuildJob(job: job, moduleId: .clang(String(module)),
                                     dependencyGraph: dependencyGraph)
          default:
            Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try RelativePath(validating: "testExplicitModuleVerifyInterfaceJobs")),
                 .relative(try RelativePath(validating: "testExplicitModuleVerifyInterfaceJobs.exe")):
              #expect(driver.isExplicitMainModuleJob(job: job))
              #expect(job.kind == .link)
            case .absolute(let path):
              #expect(path.basename == "testExplicitModuleVerifyInterfaceJobs")
              #expect(job.kind == .link)
            case .temporary(_):
              let baseName = "testExplicitModuleVerifyInterfaceJobs"
              #expect(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }


  @Test func cacheBuildEndToEndBuild() async throws {
    try await withTemporaryDirectory { path in
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
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc", "-c",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-Rcache-compile-job",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        #expect(cas == driverCAS, "CAS should only be created once")
      } else {
        Issue.record("Cached compilation doesn't have a CAS")
      }
      try await checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  @Test(.requireScannerSupportsBinaryModuleHeaderDependencies()) func cacheBuildEndToEndWithBinaryHeaderDeps() async throws {
    try await withTemporaryDirectory { path in
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
      let dependencyOracle = InterModuleDependencyOracle()

      var fooBuildDriver = try TestDriver(args: ["swiftc",
                                             "-explicit-module-build",
                                             "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                             "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                             "-working-directory", path.nativePathString(escaped: false),
                                             foo.nativePathString(escaped: false),
                                             "-emit-module", "-wmo", "-module-name", "Foo",
                                             "-emit-module-path", FooInstallPath.appending(component: "Foo.swiftmodule").nativePathString(escaped: false),
                                             "-import-objc-header", fooHeader.nativePathString(escaped: false),
                                             "-pch-output-dir", PCHPath.nativePathString(escaped: false)]
                                      + sdkArgumentsForTesting,
                                      interModuleDependencyOracle: dependencyOracle)

      let scanLibPath = try #require(try fooBuildDriver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let fooJobs = try await fooBuildDriver.planBuild()
      try await fooBuildDriver.run(jobs: fooJobs)
      #expect(!fooBuildDriver.diagnosticEngine.hasErrors)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = fooBuildDriver.cas {
        #expect(cas == driverCAS, "CAS should only be created once")
      } else {
        Issue.record("Cached compilation doesn't have a CAS")
      }
      try await checkCASForResults(jobs: fooJobs, cas: cas, fs: fooBuildDriver.fileSystem)

      var driver = try TestDriver(args: ["swiftc",
                                     "-I", FooInstallPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-emit-module", "-emit-module-path",
                                     path.appending(component: "testEMBETEWBHD.swiftmodule").nativePathString(escaped: false),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try await driver.planBuild()
      for job in jobs {
        #expect(!job.outputCacheKeys.isEmpty)
      }
      if driver.isFrontendArgSupported(.autoBridgingHeaderChaining) {
        #expect(jobs.contains(where: { $0.kind == .generatePCH }))
        try await driver.run(jobs: jobs)
        #expect(!driver.diagnosticEngine.hasErrors)
      }
    }
  }

  @Test func dependencyScanning() async throws {
    // Create a simple test case.
    try await withTemporaryDirectory { path in
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
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "/tmp/Foo.o",
                                     "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-Xcc", "-ivfsoverlay", "-Xcc", vfsoverlay.nativePathString(escaped: false),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      // Plan a build to initialize the scanner and the CAS underneath.
      _ = try await driver.planBuild()
      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
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
      #expect(!scannerCommand.contains("-pch-output-dir"))
      #expect(!scannerCommand.contains("Foo.o"))

      // Xcc commands are used for scanner command.
      #expect(scannerCommand.contains("-Xcc"))
      #expect(scannerCommand.contains("-ivfsoverlay"))

      // Here purely to dump diagnostic output in a reasonable fashion when things go wrong.
      let lock = NSLock()

      // Module `X` is only imported on Darwin when:
      // #if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 110000
      let expectedNumberOfDependencies: Int
      if driver.hostTriple.isMacOSX,
         driver.hostTriple.version(for: .macOS) < Triple.Version(11, 0, 0) {
        expectedNumberOfDependencies = 13
      } else {
        expectedNumberOfDependencies = 12
      }

      let baseCommand = scannerCommand
      // Dispatch several iterations in parallel
      DispatchQueue.concurrentPerform(iterations: 20) { index in
        // Give the main modules different names
        let iterationCommand = baseCommand + ["-module-name",
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

          let adjustedExpectedNumberOfDependencies =
              expectedNumberOfDependencies +
              Set(dependencyGraph.modules.keys.map(\.moduleName))
                  .intersection(Set(
                    // The _Concurrency and _StringProcessing modules are automatically
                    // imported in newer versions of the Swift compiler. If they happened
                    // to be provided, adjust our expectations accordingly.
                    ["_Concurrency", "_SwiftConcurrencyShims", "_StringProcessing"] +
                    // Windows Specific - these are imported on Windows hosts through `SwiftShims`.
                    ["SAL", "_Builtin_intrinsics", "_Builtin_stddef", "_stdlib", "_malloc", "corecrt", "vcruntime"]
                  ))
                  .count

          if (dependencyGraph.modules.count != adjustedExpectedNumberOfDependencies) {
            lock.lock()
            print("Unexpected Dependency Scanning Result (\(dependencyGraph.modules.count) modules):")
            dependencyGraph.modules.forEach {
              print($0.key.moduleName)
            }
            lock.unlock()
          }
          #expect(dependencyGraph.modules.count == adjustedExpectedNumberOfDependencies)
        } catch {
          Issue.record("Unexpected error: \(error)")
        }
      }

      // Change CAS path is an error.
      let casPath2 = path.appending(component: "cas2")
      let command = scannerCommand + ["-module-name",
                                      "testDependencyScanningBad",
                                      // FIXME: We need to differentiate the scanning action hash,
                                      // though the module-name above should be sufficient.
                                      "-I/tmp/bad",
                                      "-cas-path", casPath2.nativePathString(escaped: false),
                                      ]
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      do {
        let _ = try dependencyOracle.getDependencies(workingDirectory: path,
                                                     commandLine: command,
                                                     diagnostics: &scanDiagnostics)
      } catch let error {
        #expect(error is DependencyScanningError)
      }

      #expect(scanDiagnostics.count == 1)
      #expect(scanDiagnostics[0].severity == .error)

    }
  }

  @Test(.skipHostOS(.win32, comment: "Skipping due to improper path mapping handling."),
        .requireFrontendArgSupport(.scannerPrefixMapPaths))
  func dependencyScanningPathRemap() async throws {

    // Create a simple test case.
    try await withTemporaryDirectory { path in
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
      var env = ProcessEnv.block
      env["_SWIFT_DRIVER_MOCK_BLOCK_LIST_DIR"] = mockBlocklistDir.nativePathString(escaped: false)
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-g", "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-clang-target", "-scanner-prefix-map-sdk", "/^sdk",
                                     "-scanner-prefix-map-toolchain", "/^toolchain",
                                     "-scanner-prefix-map", testInputsPath.description + "=/^src",
                                     "-scanner-prefix-map", path.description + "=/^tmp",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              env: env,
                              interModuleDependencyOracle: dependencyOracle)
      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }

      #expect(scannerCommand.contains("-scanner-prefix-map-paths"))
      #expect(scannerCommand.contains(try testInputsPath.description))
#if os(Windows)
      #expect(scannerCommand.contains("\\^src"))
#else
      #expect(scannerCommand.contains("/^src"))
#endif

      let jobs = try await driver.planBuild()
      for job in jobs {
        if !job.kind.supportCaching {
          continue
        }
        let command = try job.commandLine.map { try resolver.resolve($0) }
        for i in 0..<command.count {
          if i >= 2 && command[i - 2] == "-cache-replay-prefix-map" { continue }
          // Check all the arguments that are in the temporary directory are remapped.
          // The only one that is not remapped should be the `-cas-path` that points to
          // `casPath`.
          #expect(!(command[i] != casPath.description && command[i].starts(with: path.description)))
          /// All source location path should be remapped as well.
          #expect(!command[i].starts(with: try testInputsPath.description))
        }
        /// command-line that compiles swift should contains -cache-replay-prefix-map
        #expect(command.contains(where: { $0 == "-cache-replay-prefix-map" }))
        if job.kind == .compile {
          #expect(command.contains(where: { $0 == "-in-process-plugin-server-path" }))
        }
        let hasPath = !command.contains(where: { $0 == "-plugin-path" || $0 == "-external-plugin-path" ||
                                          $0 == "-load-plugin-library" || $0 == "-load-plugin-executable" })
        #expect(hasPath)
      }

      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)
    }
  }

  @Test(.skipHostOS(.win32, comment: "Skipping due to improper path mapping handling."),
        .requireFrontendArgSupport(.scannerPrefixMapPaths))
  func commaJoinedPathRemapping() async throws {

    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testCommaJoinedPathRemapping.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;")
        $0.send("import E;")
        $0.send("import G;")
      }

      // Create dummy profdata files so the driver doesn't emit missing data errors.
      let profdata1 = path.appending(component: "prof1.profdata")
      let profdata2 = path.appending(component: "prof2.profdata")
      try localFileSystem.writeFileContents(profdata1, bytes: .init())
      try localFileSystem.writeFileContents(profdata2, bytes: .init())

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let casPath = path.appending(component: "cas")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-g", "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-clang-target",
                                     "-scanner-prefix-map-paths", path.nativePathString(escaped: false), "/^tmp",
                                     "-profile-use=" + profdata1.nativePathString(escaped: false) + "," + profdata2.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)

      let jobs = try await driver.planBuild()
      for job in jobs {
        if !job.kind.supportCaching {
          continue
        }
        let command = try job.commandLine.map { try resolver.resolve($0) }
        // Check that -profile-use= paths are remapped and don't contain the original temp path.
        for arg in command {
          if arg.hasPrefix("-profile-use=") {
            let paths = String(arg.dropFirst("-profile-use=".count))
            for profilePath in paths.split(separator: ",") {
              #expect(profilePath.starts(with: "/^tmp"),
                            "Expected remapped profile path, got: \(profilePath)")
            }
          }
        }
        // Verify no unremapped temp paths appear (except -cas-path).
        for i in 0..<command.count {
          if i >= 2 && command[i - 2] == "-cache-replay-prefix-map" { continue }
          #expect(!(command[i] != casPath.description && command[i].starts(with: path.description)),
                         "Found unremapped path: \(command[i])")
        }
      }
      #expect(!driver.diagnosticEngine.hasErrors)
    }
  }

  @Test func cacheIncrementalBuildPlan() async throws {
    try await withTemporaryDirectory { path in
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
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc", "-c",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-Rcache-compile-job", "-incremental",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     "-output-file-map", ofm.nativePathString(escaped: false),
                                     "-pch-output-dir", path.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        #expect(cas == driverCAS, "CAS should only be created once")
      } else {
        Issue.record("Cached compilation doesn't have a CAS")
      }
      try await checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  @Test func cacheBatchBuildPlan() async throws {
    try await withTemporaryDirectory { path in
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
      let moduleOutputPath: AbsolutePath = moduleCachePath.appending(component: "Test.swiftmodule")
      let dependencyOracle = InterModuleDependencyOracle()
      var driver = try TestDriver(args: ["swiftc", "-g", "-c",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-Rcache-compile-job", "-incremental",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     "-output-file-map", ofm.nativePathString(escaped: false),
                                     "-pch-output-dir", path.nativePathString(escaped: false),
                                     "-emit-module-path", moduleOutputPath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              interModuleDependencyOracle: dependencyOracle)
      let jobs = try await driver.planBuild()

      if driver.isFeatureSupported(.debug_info_explicit_dependency) {
        let _ = jobs.filter{ $0.kind == .compile }.map {
          #expect($0.commandLine.contains("-debug-module-path"))
        }
      }

      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      if let driverCAS = driver.cas {
        #expect(cas == driverCAS, "CAS should only be created once")
      } else {
        Issue.record("Cached compilation doesn't have a CAS")
      }
      try await checkCASForResults(jobs: jobs, cas: cas, fs: driver.fileSystem)
    }
  }

  @Test(.requireFrontendArgSupport(.genReproducer)) func crashReproducer() async throws {
    try await withTemporaryDirectory { path in
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
      var env = ProcessEnv.block
      env["SWIFT_CRASH_DIAGNOSTICS_DIR"] = path.nativePathString(escaped: false)
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-enable-deterministic-check",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-Xfrontend", "-debug-crash-after-parse",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting,
                              env: env)
      let jobs = try await driver.planBuild()
      do {
        try await driver.run(jobs: jobs)
        Issue.record("Build should fail")
      } catch {
        #expect(driver.diagnosticEngine.hasErrors)
        #expect(driver.diagnosticEngine.diagnostics.contains(where: {
          $0.message.behavior == .note && $0.message.data.description.starts(with: "crash reproducer")
          }))
      }
    }
  }

  @Test func deterministicCheck() async throws {
    try await withTemporaryDirectory { path in
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
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-enable-deterministic-check",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      jobs.forEach { job in
        guard job.kind == .compile else {
          return
        }
        expectJobInvocationMatches(job,
                                      .flag("-enable-deterministic-check"),
                                      .flag("-always-compile-output-files"),
                                      .flag("-cache-disable-replay"))
      }
    }

  }

  @Test func casManagement() async throws {
    try withTemporaryDirectory { path in
      let casPath = path.appending(component: "cas")
      let driver = try TestDriver(args: ["swiftc"])
      let scanLibPath = try #require(try driver.getSwiftScanLibPath())
      let dependencyOracle = InterModuleDependencyOracle()
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      let cas = try dependencyOracle.getOrCreateCAS(pluginPath: nil, onDiskPath: casPath, pluginOptions: [])
      try #require(cas.supportsSizeManagement, "CAS size management is not supported")
      let preSize = try #require(try cas.getStorageSize())
      let dataToStore = Data(count: 1000)
      _ = try cas.store(data: dataToStore)
      let postSize = try #require(try cas.getStorageSize())
      #expect(postSize > preSize)

      // Try prune.
      try cas.setSizeLimit(100)
      try cas.prune()
    }
  }

  // Test not stable on platforms other than macOS.
  @Test(.requireHostOS(.macosx)) func casSizeLimiting() async throws {
    try await withTemporaryDirectory { path in
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

      func createDriver(main: AbsolutePath) throws -> TestDriver {
        return try TestDriver(args: ["swiftc",
                                 "-I", cHeadersPath.nativePathString(escaped: false),
                                 "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                 "-explicit-module-build", "-Rcache-compile-job",
                                 "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                 "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: false),
                                 "-working-directory", path.nativePathString(escaped: false),
                                 main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      }

      func buildAndGetSwiftCASKeys(main: AbsolutePath, forceCASLimit: Bool) async throws -> [String] {
        var driver = try createDriver(main: main)
        let cas = try #require(driver.cas)
        if forceCASLimit {
          try cas.setSizeLimit(10)
        }
        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
        #expect(!driver.diagnosticEngine.hasErrors)

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

      func verifyKeys(exist: Bool, keys: [String], main: AbsolutePath, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let driver = try createDriver(main: main)
        let cas = try #require(driver.cas)
        for key in keys {
          let comp = try cas.queryCacheKey(key, globally: false)
          if exist {
            #expect(comp != nil, sourceLocation: sourceLocation)
          } else {
            #expect(comp == nil, sourceLocation: sourceLocation)
          }
        }
      }

      do {
        // Without CAS size limitation the keys will be preserved.
        let keys = try await buildAndGetSwiftCASKeys(main: main1, forceCASLimit: false)
        _ = try await buildAndGetSwiftCASKeys(main: main2, forceCASLimit: false)
        try verifyKeys(exist: true, keys: keys, main: main1)
      }

      try localFileSystem.removeFileTree(casPath)

      do {
        // 2 separate builds with CAS size limiting, the keys of first build will not be preserved.
        let keys = try await buildAndGetSwiftCASKeys(main: main1, forceCASLimit: true)
        _ = try await buildAndGetSwiftCASKeys(main: main2, forceCASLimit: true)
        try verifyKeys(exist: false, keys: keys, main: main1)
      }
    }
  }
}
