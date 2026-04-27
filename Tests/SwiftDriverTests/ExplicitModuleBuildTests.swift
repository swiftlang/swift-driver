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

import CSwiftScan
import Foundation
@_spi(Testing) @preconcurrency import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TSCBasic
import Testing
import TestUtilities

/// Check that an explicit module build job contains expected inputs and options
private func checkExplicitModuleBuildJob(job: Job,
                                         moduleId: ModuleDependencyId,
                                         dependencyGraph: InterModuleDependencyGraph)
throws {
  let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
  switch moduleInfo.details {
    case .swift(let swiftModuleDetails):
      expectJobInvocationMatches(job, .flag("-disable-implicit-swift-modules"))

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
    case .clang(_):
      #expect(job.kind == .generatePCM)
      #expect(job.description == "Compiling Clang module \(moduleId.moduleName)")
    case .swiftPrebuiltExternal(_):
      Issue.record("Unexpected prebuilt external module dependency found.")
  }
  // Ensure the frontend was prohibited from doing implicit module builds
  expectJobInvocationMatches(job, .flag("-fno-implicit-modules"))
  try checkExplicitModuleBuildJobDependencies(job: job,
                                              moduleInfo: moduleInfo,
                                              dependencyGraph: dependencyGraph)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkExplicitModuleBuildJobDependencies(job: Job,
                                                     moduleInfo : ModuleInfo,
                                                     dependencyGraph: InterModuleDependencyGraph
) throws {
  let validateSwiftCommandLineDependency: (ModuleDependencyId, ModuleInfo) -> Void = { dependencyId, dependencyInfo in
    let inputModulePath = dependencyInfo.modulePath.path
    #expect(job.inputs.contains(TypedVirtualPath(file: inputModulePath, type: .swiftModule)))
    expectJobInvocationMatches(job, .flag("-swift-module-file=\(dependencyId.moduleName)=\(inputModulePath.description)"))
  }

  let validateClangCommandLineDependency: (ModuleDependencyId,
                                           ModuleInfo,
                                           ClangModuleDetails) -> Void = { dependencyId, dependencyInfo, clangDependencyDetails  in
    let clangDependencyModulePathString = dependencyInfo.modulePath.path
    let clangDependencyModulePath =
      TypedVirtualPath(file: clangDependencyModulePathString, type: .pcm)
    #expect(job.inputs.contains(clangDependencyModulePath))
    expectJobInvocationMatches(job, .flag("-fmodule-file=\(dependencyId.moduleName)=\(clangDependencyModulePathString)"))
  }

  for dependencyId in moduleInfo.allDependencies {
    let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)
    switch dependencyInfo.details {
      case .swift(_):
        fallthrough
      case .swiftPrebuiltExternal(_):
        validateSwiftCommandLineDependency(dependencyId, dependencyInfo)
      case .clang(let clangDependencyDetails):
        validateClangCommandLineDependency(dependencyId, dependencyInfo, clangDependencyDetails)
    }
  }
}

internal func getDriverArtifactsForScanning() throws -> (stdLibPath: AbsolutePath,
                                                         shimsPath: AbsolutePath,
                                                         toolchain: Toolchain,
                                                         hostTriple: Triple) {
  // Just instantiating to get at the toolchain path
  let driver = try TestDriver(args: ["swiftc", "-explicit-module-build",
                                 "-module-name", "testDependencyScanning",
                                 "test.swift"])
  let (stdLibPath, shimsPath) = try driver.unwrap {
    try getStdlibShimsPaths($0)
  }
  #expect(localFileSystem.exists(stdLibPath),
                "expected Swift StdLib at: \(stdLibPath.description)")
  #expect(localFileSystem.exists(shimsPath),
                "expected Swift Shims at: \(shimsPath.description)")
  return (stdLibPath, shimsPath, driver.toolchain, driver.hostTriple)
}

func getStdlibShimsPaths(_ driver: Driver) throws -> (AbsolutePath, AbsolutePath) {
  let toolchainRootPath: AbsolutePath = try driver.toolchain.getToolPath(.swiftCompiler)
                                                          .parentDirectory // bin
                                                          .parentDirectory // toolchain root
  if driver.targetTriple.isDarwin {
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.block)
    let sdkPath = try executor.checkNonZeroExit(
      args: "xcrun", "-sdk", "macosx", "--show-sdk-path", environmentBlock: ProcessEnv.block).spm_chomp()
    let stdLibPath = try AbsolutePath(validating: sdkPath).appending(component: "usr")
      .appending(component: "lib")
      .appending(component: "swift")
    return (stdLibPath, stdLibPath.appending(component: "shims"))
  } else if driver.targetTriple.isWindows {
    if let sdkroot = try driver.toolchain.defaultSDKPath(driver.targetTriple) {
      return (sdkroot.appending(components: "usr", "lib", "swift", "windows"),
              sdkroot.appending(components: "usr", "lib", "swift", "shims"))
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

/// Test that for the given JSON module dependency graph, valid jobs are generated
@Suite struct ExplicitModuleBuildTests {
  @Test func moduleDependencyBuildCommandGeneration() async throws {
    do {
      let driver = try TestDriver(args: ["swiftc", "-explicit-module-build",
                                     "-module-name", "testModuleDependencyBuildCommandGeneration",
                                     "test.swift"])
      let moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerOutput.data(using: .utf8)!)
      var explicitDependencyBuildPlanner =
        try ExplicitDependencyBuildPlanner(dependencyGraph: moduleDependencyGraph,
                                           toolchain: driver.toolchain,
                                           supportsScannerPrefixMapPaths: driver.isFrontendArgSupported(.scannerPrefixMapPaths))
      let modulePrebuildJobs =
        try explicitDependencyBuildPlanner.generateExplicitModuleDependenciesBuildJobs()
      #expect(modulePrebuildJobs.count == 4)
      for job in modulePrebuildJobs {
        #expect(job.outputs.count == 1)
        #expect(!driver.isExplicitMainModuleJob(job: job))

        switch (job.outputs[0].file) {
          case .relative(try .init(validating: "SwiftShims.pcm")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .clang("SwiftShims"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "c_simd.pcm")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .clang("c_simd"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("Swift"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "_Concurrency.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("_Concurrency"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "_StringProcessing.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("_StringProcessing"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: moduleDependencyGraph)
          default:
            Issue.record("Unexpected module dependency build job output: \(job.outputs[0].file)")
        }
      }
    }
  }

  @Test func moduleDependencyBuildCommandUniqueDepFile() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
      let source0 = path.appending(component: "testModuleDependencyBuildCommandUniqueDepFile1.swift")
      let source1 = path.appending(component: "testModuleDependencyBuildCommandUniqueDepFile2.swift")
      try localFileSystem.writeFileContents(source0, bytes:
        """
        import C;
        """
      )
      try localFileSystem.writeFileContents(source1, bytes:
        """
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     source0.nativePathString(escaped: false),
                                     source1.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      let compileJobs = jobs.filter({ $0.kind == .compile })
      #expect(compileJobs.count == 2)
      let compileJob0 = compileJobs[0]
      let compileJob1 = compileJobs[1]
      let explicitDepsFlag = SwiftDriver.Job.ArgTemplate.flag(String("-explicit-swift-module-map-file"))
      expectJobInvocationMatches(compileJob0, explicitDepsFlag)
      expectJobInvocationMatches(compileJob1, explicitDepsFlag)
      let jsonDeps0PathIndex = try #require(compileJob0.commandLine.firstIndex(of: explicitDepsFlag))
      let jsonDeps0PathArg = compileJob0.commandLine[jsonDeps0PathIndex + 1]
      let jsonDeps1PathIndex = try #require(compileJob1.commandLine.firstIndex(of: explicitDepsFlag))
      let jsonDeps1PathArg = compileJob1.commandLine[jsonDeps1PathIndex + 1]
      #expect(jsonDeps0PathArg == jsonDeps1PathArg)
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build
  @Test func bridgingHeaderDeps() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )
      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
      cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      let compileJob = try #require(jobs.first(where: { $0.kind == .compile }))

      // Load the dependency JSON and verify this dependency was encoded correctly
      let explicitDepsFlag =
        SwiftDriver.Job.ArgTemplate.flag(String("-explicit-swift-module-map-file"))
      expectJobInvocationMatches(compileJob, explicitDepsFlag)
      let jsonDepsPathIndex = try #require(compileJob.commandLine.firstIndex(of: explicitDepsFlag))
      let jsonDepsPathArg = compileJob.commandLine[jsonDepsPathIndex + 1]
      guard case .path(let jsonDepsPath) = jsonDepsPathArg else {
        Issue.record("No JSON dependency file path found.")
        return
      }
      guard case let .temporaryWithKnownContents(_, contents) = jsonDepsPath else {
        Issue.record("Unexpected path type")
        return
      }
      let jsonDepsDecoded = try JSONDecoder().decode(Array<ModuleDependencyArtifactInfo>.self, from: contents)

      // Ensure that "F" is specified as a bridging dependency
      #expect(jsonDepsDecoded.contains { artifactInfo in
        if case .clang(let details) = artifactInfo {
          return details.moduleName == "F" && details.isBridgingHeaderDependency == true
        } else {
          return false
        }
      })

      // If the scanner supports the feature, ensure that "C" is reported as *not* a bridging
      // header dependency
      if try driver.interModuleDependencyOracle.supportsBinaryModuleHeaderModuleDependencies() {
        let result = jsonDepsDecoded.contains { artifactInfo in
          if case .clang(let details) = artifactInfo {
            return details.moduleName == "C" && details.isBridgingHeaderDependency == false
          } else {
            return false
          }
        }
        #expect(result)
      }
    }
  }

  @Test func explicitBuildEndToEndWithBinaryHeaderDeps() async throws {
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let PCHPath = path.appending(component: "PCH")
      try localFileSystem.createDirectory(PCHPath)
      let FooInstallPath = path.appending(component: "Foo")
      try localFileSystem.createDirectory(FooInstallPath)
      let foo = path.appending(component: "foo.swift")
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
      let userHeader = path.appending(component: "user.h")
      try localFileSystem.writeFileContents(userHeader) {
        $0.send("struct User { void* ptr; };")
      }
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      var fooBuildDriver = try TestDriver(args: ["swiftc",
                                             "-explicit-module-build", "-auto-bridging-header-chaining",
                                             "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                             "-working-directory", path.nativePathString(escaped: false),
                                             foo.nativePathString(escaped: false),
                                             "-emit-module", "-wmo", "-module-name", "Foo",
                                             "-emit-module-path", FooInstallPath.appending(component: "Foo.swiftmodule").nativePathString(escaped: false),
                                             "-import-objc-header", fooHeader.nativePathString(escaped: false),
                                             "-pch-output-dir", PCHPath.nativePathString(escaped: false)]
                                      + sdkArgumentsForTesting)

      let fooJobs = try await fooBuildDriver.planBuild()
      try await fooBuildDriver.run(jobs: fooJobs)
      #expect(!fooBuildDriver.diagnosticEngine.hasErrors)

      // If no chained bridging header is used, always pass pch through -import-objc-header
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", FooInstallPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-no-auto-bridging-header-chaining",
                                     "-pch-output-dir", FooInstallPath.nativePathString(escaped: false),
                                     "-import-objc-header", userHeader.nativePathString(escaped: false),
                                     "-emit-module", "-emit-module-path",
                                     path.appending(component: "testEMBETEWBHD.swiftmodule").nativePathString(escaped: false),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      var jobs = try await driver.planBuild()
      #expect(jobs.contains { $0.kind == .generatePCH })
      #expect(jobs.allSatisfy {
        !$0.kind.isCompile || $0.commandLine.contains(.flag("-import-objc-header"))
      })
      #expect(jobs.allSatisfy {
        !$0.kind.isCompile || !$0.commandLine.contains(.flag("-import-pch"))
      })

      // Remaining tests require a compiler supporting auto chaining.
      guard driver.isFrontendArgSupported(.autoBridgingHeaderChaining) else { return }

      // Warn if -disable-bridging-pch is used with auto bridging header chaining.
      driver = try TestDriver(args: ["swiftc",
                                 "-I", FooInstallPath.nativePathString(escaped: false),
                                 "-explicit-module-build", "-auto-bridging-header-chaining", "-disable-bridging-pch",
                                 "-pch-output-dir", FooInstallPath.nativePathString(escaped: false),
                                 "-emit-module", "-emit-module-path",
                                 path.appending(component: "testEMBETEWBHD.swiftmodule").nativePathString(escaped: false),
                                 "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                 "-working-directory", path.nativePathString(escaped: false),
                                 main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      jobs = try await driver.planBuild()
      #expect(driver.diagnosticEngine.diagnostics.contains {
        $0.behavior == .warning && $0.message.text == "-auto-bridging-header-chaining requires generatePCH job, no chaining will be performed"
      })
      #expect(!jobs.contains { $0.kind == .generatePCH })

      driver = try TestDriver(args: ["swiftc",
                                 "-I", FooInstallPath.nativePathString(escaped: false),
                                 "-explicit-module-build", "-auto-bridging-header-chaining",
                                 "-pch-output-dir", FooInstallPath.nativePathString(escaped: false),
                                 "-emit-module", "-emit-module-path",
                                 path.appending(component: "testEMBETEWBHD.swiftmodule").nativePathString(escaped: false),
                                 "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                 "-working-directory", path.nativePathString(escaped: false),
                                 main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      jobs = try await driver.planBuild()
      #expect(jobs.contains { $0.kind == .generatePCH })
      #expect(jobs.allSatisfy {
        !$0.kind.isCompile || $0.commandLine.contains(.flag("-import-pch"))
      })
      #expect(jobs.allSatisfy {
        !$0.kind.isCompile || !$0.commandLine.contains(.flag("-import-objc-header"))
      })
      #expect(!driver.diagnosticEngine.hasErrors)
    }
  }

  @Test(.requireScannerSupportsLinkLibraries()) func explicitLinkFlags() async throws {
    try await withTemporaryDirectory { path in
      let (_, _, _, _) = try getDriverArtifactsForScanning()

      let main = path.appending(component: "testExplicitLinkLibraries.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;import E;import G;
        """
      )

      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
      cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-explicit-module-build", "-explicit-auto-linking",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()

      let linkJob = try jobs.findJob(.link)
      if driver.targetTriple.isDarwin {
        expectCommandLineContains(linkJob.commandLine, .flag("-possible-lswiftCore"))
        expectCommandLineContains(linkJob.commandLine, .flag("-possible-lswift_StringProcessing"))
        expectCommandLineContains(linkJob.commandLine, .flag("-possible-lobjc"))
        expectCommandLineContains(linkJob.commandLine, .flag("-possible-lswift_Concurrency"))
        expectCommandLineContains(linkJob.commandLine, .flag("-possible-lswiftSwiftOnoneSupport"))
      } else if driver.targetTriple.isWindows {
        expectCommandLineContains(linkJob.commandLine, .flag("-lswiftCore"))
      } else {
        expectCommandLineContains(linkJob.commandLine, .flag("-lswiftCore"))
        expectCommandLineContains(linkJob.commandLine, .flag("-lswift_StringProcessing"))
        expectCommandLineContains(linkJob.commandLine, .flag("-lswift_Concurrency"))
        expectCommandLineContains(linkJob.commandLine, .flag("-lswiftSwiftOnoneSupport"))
      }
    }
  }

  @Test(.requireScannerSupportsImportInfos()) func explicitImportDetails() async throws {
    try await withTemporaryDirectory { path in
      let (_, _, _, _) = try getDriverArtifactsForScanning()

      let main = path.appending(component: "testExplicitLinkLibraries.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        public import C;
        internal import E;
        private import G;
        internal import C;
        """
      )

      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      let args = ["swiftc",
                  "-I", cHeadersPath.nativePathString(escaped: false),
                  "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                  "-explicit-module-build",
                  "-Xfrontend", "-disable-implicit-concurrency-module-import",
                  "-Xfrontend", "-disable-implicit-string-processing-module-import",
                  main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var driver = try TestDriver(args: args)
      let _ = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)
      let mainModuleImports = try #require(dependencyGraph.mainModule.importInfos)
      #expect(mainModuleImports.count == 5)
      #expect(mainModuleImports.contains(ImportInfo(importIdentifier: "Swift",
                                                          accessLevel: ImportInfo.ImportAccessLevel.Public,
                                                          sourceLocations: [])))
      #expect(mainModuleImports.contains(ImportInfo(importIdentifier: "SwiftOnoneSupport",
                                                          accessLevel: ImportInfo.ImportAccessLevel.Public,
                                                          sourceLocations: [])))
      #expect(mainModuleImports.contains(ImportInfo(importIdentifier: "C",
                                                          accessLevel: ImportInfo.ImportAccessLevel.Public,
                                                          sourceLocations: [ScannerDiagnosticSourceLocation(bufferIdentifier: main.nativePathString(escaped: false),
                                                                                                            lineNumber: 1,
                                                                                                            columnNumber: 15),
                                                                            ScannerDiagnosticSourceLocation(bufferIdentifier: main.nativePathString(escaped: false),
                                                                                                            lineNumber: 4,
                                                                                                            columnNumber: 17)])))
      #expect(mainModuleImports.contains(ImportInfo(importIdentifier: "E",
                                                          accessLevel: ImportInfo.ImportAccessLevel.Internal,
                                                          sourceLocations: [ScannerDiagnosticSourceLocation(bufferIdentifier: main.nativePathString(escaped: false),
                                                                                                            lineNumber: 2,
                                                                                                            columnNumber: 17)])))
      #expect(mainModuleImports.contains(ImportInfo(importIdentifier: "G",
                                                          accessLevel: ImportInfo.ImportAccessLevel.Private,
                                                          sourceLocations: [ScannerDiagnosticSourceLocation(bufferIdentifier: main.nativePathString(escaped: false),
                                                                                                            lineNumber: 3,
                                                                                                            columnNumber: 16)])))
    }
  }

  @Test(.requireScannerSupportsLinkLibraries()) func explicitLinkLibraries() async throws {
    try await withTemporaryDirectory { path in
      let (_, _, _, _) = try getDriverArtifactsForScanning()

      let main = path.appending(component: "testExplicitLinkLibraries.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;import E;import G;
        """
      )

      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
      cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      let args = ["swiftc",
                  "-I", cHeadersPath.nativePathString(escaped: false),
                  "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                  "-explicit-module-build",
                  "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                  main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var driver = try TestDriver(args: args)
      // If this is a supported flow, then it is currently required for this test
      if driver.isFrontendArgSupported(.scannerModuleValidation) {
        driver = try TestDriver(args: args + ["-scanner-module-validation"])
      }
      let _ = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)

      let checkForLinkLibrary = { (info: ModuleInfo, linkName: String, isFramework: Bool, shouldForceLoad: Bool) in
        if driver.targetTriple.isWindows && linkName != "swiftCore" {
          // Windows only links swiftCore.
          return
        }
        let linkLibraries = try #require(info.linkLibraries)
        let linkLibrary = try #require(linkLibraries.first { $0.linkName == linkName })
        #expect(linkLibrary.isFramework == isFramework)
        #expect(linkLibrary.shouldForceLoad == shouldForceLoad)
      }

      for (depId, depInfo) in dependencyGraph.modules {
        switch depId {
        case .swiftPrebuiltExternal("Swift"):
          fallthrough
        case .swift("Swift"):
          try checkForLinkLibrary(depInfo, "swiftCore", false, false)
          break

        case .swiftPrebuiltExternal("_StringProcessing"):
          fallthrough
        case .swift("_StringProcessing"):
          try checkForLinkLibrary(depInfo, "swift_StringProcessing", false, false)
          break

        case .swiftPrebuiltExternal("SwiftOnoneSupport"):
          fallthrough
        case .swift("SwiftOnoneSupport"):
          try checkForLinkLibrary(depInfo, "swiftSwiftOnoneSupport", false, false)
          break

        case .swiftPrebuiltExternal("_Concurrency"):
          fallthrough
        case .swift("_Concurrency"):
          try checkForLinkLibrary(depInfo, "swift_Concurrency", false, false)
          break

        case .swift("testExplicitLinkLibraries"):
          let linkLibraries = try #require(depInfo.linkLibraries)
          if driver.targetTriple.isDarwin {
            #expect(!linkLibraries.isEmpty)
            #expect(linkLibraries.contains { $0.linkName == "objc" })
          }
        default:
          continue
        }
      }
    }
  }

  @Test(.requireScannerSupportsLibraryLevel()) func explicitLibraryLevel() async throws {
    try await withTemporaryDirectory { path in
      let (_, _, _, _) = try getDriverArtifactsForScanning()

      let main = path.appending(component: "testExplicitLibraryLevel.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import E;
        """
      )

      let swiftModuleInterfacesPath: AbsolutePath =
        try testInputsPath.appending(component: "ExplicitModuleBuilds")
          .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      let args = ["swiftc",
                  "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                  "-explicit-module-build",
                  "-Xfrontend", "-disable-implicit-concurrency-module-import",
                  "-Xfrontend", "-disable-implicit-string-processing-module-import",
                  main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var driver = try TestDriver(args: args)
      let _ = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)

      // The main module should have a library level reported.
      #expect(dependencyGraph.mainModule.libraryLevel != nil)

      // All modules in the graph should have a non-nil library level.
      for (_, moduleInfo) in dependencyGraph.modules {
        #expect(moduleInfo.libraryLevel != nil)
      }
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build
  @Test func explicitModuleBuildJobs() async throws {
    let (stdlibPath, shimsPath, _, hostTriple) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-disable-implicit-concurrency-module-import",
                                     "-disable-implicit-string-processing-module-import",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)

      let jobs = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildJobs"))

      guard case .swift(let mainModuleDetails) = mainModuleInfo.details else {
        Issue.record("Main module does not have Swift details field")
        return
      }

      if try driver.interModuleDependencyOracle.supportsSeparateImportOnlyDependencies() {
          let directImportedDependencies = try #require(mainModuleDetails.sourceImportDependencies)
        #expect(!directImportedDependencies.contains(.swift("A")))
        #expect(!directImportedDependencies.contains(.clang("D")))
        #expect(!directImportedDependencies.contains(.clang("F")))
        #expect(!directImportedDependencies.contains(.clang("G")))

        #expect(directImportedDependencies.contains(.swift("Swift")) ||
                      directImportedDependencies.contains(.swiftPrebuiltExternal("Swift")))
        #expect(directImportedDependencies.contains(.swift("SwiftOnoneSupport")) ||
                      directImportedDependencies.contains(.swiftPrebuiltExternal("SwiftOnoneSupport")))
        #expect(directImportedDependencies.contains(.swift("E")))
        #expect(directImportedDependencies.contains(.clang("C")))
        #expect(directImportedDependencies.contains(.swift("G")))
      }

      for job in jobs {
        #expect(job.outputs.count == 1)
        let outputFilePath = job.outputs[0].file
        if job.kind == .compile && driver.isFeatureSupported(.debug_info_explicit_dependency) {
          #expect(job.commandLine.contains(subsequence: ["-debug-module-path", try toPathOption("testExplicitModuleBuildJobs.swiftmodule")]))
        }

        // Swift dependencies
        if let outputFileExtension = outputFilePath.extension,
           outputFileExtension == FileType.swiftModule.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "E", "G"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["Swift", "SwiftOnoneSupport"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            break
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "B", "C", "D", "G", "F"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SwiftShims", "_SwiftConcurrencyShims", "_Builtin_stdint"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SAL", "_Builtin_intrinsics", "_Builtin_stddef", "_stdlib", "_malloc", "corecrt", "vcruntime"].contains(module):
            guard hostTriple.isWindows else {
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
              return
            }
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where module == "X":
            guard hostTriple.isMacOSX,
                  hostTriple.version(for: .macOS) < Triple.Version(11, 0, 0) else {
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
              return
            }
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleBuildJobs")),
                .relative(try .init(validating: "testExplicitModuleBuildJobs.exe")):
              #expect(driver.isExplicitMainModuleJob(job: job))
              #expect(job.kind == .link)
            case .absolute(let path):
              #expect(path.basename == "testExplicitModuleBuildJobs")
              #expect(job.kind == .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildJobs"
              #expect(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink") ||
                            matchTemporary(outputFilePath, basename: "Bridging", fileExtension: "pch"))
            default:
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  @Test func registerModuleDependencyFlag() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testRegisterModuleDependency.swift")
      // Note: We're NOT importing module E in the source code
      try localFileSystem.writeFileContents(main, bytes:
        """
        import A;
        """
      )
      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let traceFile = path.appending(component: "testRegisterModuleDependency.trace.json")

      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-implicit-concurrency-module-import",
                                     "-disable-implicit-string-processing-module-import",
                                     "-register-module-dependency", "E",
                                     "-register-module-dependency", "G",
                                     "-emit-loaded-module-trace",
                                     "-emit-loaded-module-trace-path", traceFile.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)
      // E and G SHOULD be in the dependency graph (registered for scanning)
      #expect(dependencyGraph.modules.keys.contains(.swift("E")),
                    "Module E should be in dependency graph when registered via -register-module-dependency")
      #expect(dependencyGraph.modules.keys.contains(.swift("G")),
                    "Module G should be in dependency graph when registered via -register-module-dependency")
      // Checking that registered module compiled
      let moduleEJobs = jobs.filter { job in
        job.outputs.contains { output in
          output.file.basename.contains("E") && output.file.extension == "swiftmodule"
        }
      }
      #expect(!moduleEJobs.isEmpty,
                    "Module E should have a build job when registered via -register-module-dependency")
      let moduleGJobs = jobs.filter { job in
        job.outputs.contains { output in
          output.file.basename.contains("G") && output.file.extension == "swiftmodule"
        }
      }
      #expect(!moduleGJobs.isEmpty,
                    "Module G should have a build job when registered via -register-module-dependency")
      // Checking that registered module is not loaded for the main compilation
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)
      // Checking the output given by the -emit-loaded-module-trace flag
      #expect(localFileSystem.exists(traceFile), "Module trace file should exist")
      let traceData = try localFileSystem.readFileContents(traceFile)
      let _ = try traceData.withData { data in
        try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
      }
      let jsonString = String(decoding: traceData.contents, as: UTF8.self)
      #expect(!jsonString.contains("\"name\":\"E\""),
                     "Module E should not be loaded in the final compilation since it's not imported")
      #expect(!jsonString.contains("\"name\":\"G\""),
                     "Module G should not be loaded in the final compilation since it's not imported")

    }
  }

  @Test func invalidUTF8InStringRef() throws {
    let (_, _, toolchain, _) = try getDriverArtifactsForScanning()
    let invalidBytes: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x80, 0xFF]  // "Hello" + invalid UTF8
    let swiftScanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    if localFileSystem.exists(swiftScanLibPath) {
      let swiftScanInstance = try SwiftScan(dylib: swiftScanLibPath)
      let result = try swiftScanInstance.roundTripBytesToSwiftScanStringRef(bytes: invalidBytes)
      #expect(result == "Hello��")
    }
  }

  // Ensure invalid UTF-8 content in diagnostic text does not crash the driver
  @Test(.requireScannerSupportsPerScanDiagnostics()) func invalidUTF8PathDiagnostic() async throws {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

    try withTemporaryDirectory { path in
      let main = path.appending(component: "testInvalidUTF8PathDiagnostic.swift")
      // "import " + invalid UTF-8 + "Module"
      let bytes: [UInt8] = [
          0x69, 0x6D, 0x70, 0x6F, 0x72, 0x74, 0x20,   // "import "
          0x80, 0x81, 0x82,                           // invalid UTF-8
          0x4D, 0x6F, 0x64, 0x75, 0x6C, 0x65,         // "Module"
          0x0A                                        // newline
      ]
      try localFileSystem.writeFileContents(main, bytes: ByteString(bytes))
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }
      // Verify scanning completes without crashing on invalid UTF-8 input.
      // Diagnostic count and messages vary across compiler versions.
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let _ = try dependencyOracle.getDependencies(workingDirectory: path,
                                                            commandLine: scannerCommand,
                                                            diagnostics: &scanDiagnostics)

    }
  }

  // Ensure that (even when not in '-incremental' mode) up-to-date module dependencies
  // do not get re-built
  @Test func explicitModuleBuildIncrementalEndToEnd() async throws {
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testExplicitModuleBuildEndToEnd.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;
        import E;
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let invocationArguments = ["swiftc",
                                 "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
                                 "-I", cHeadersPath.nativePathString(escaped: false),
                                 "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                 "-explicit-module-build",
                                 "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                 "-working-directory", path.nativePathString(escaped: false),
                                 main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var driver = try TestDriver(args: invocationArguments)
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      // Plan the same build one more time and ensure it does not contain dependency compilation jobs
      var incrementalDriver = try TestDriver(args: invocationArguments)
      let incrementalJobs = try await incrementalDriver.planBuild()
      #expect(!incrementalJobs.contains { $0.kind == .generatePCM })
      #expect(!incrementalJobs.contains { $0.kind == .compileModuleFromInterface })

      // Ensure that passing '-always-rebuild-module-dependencies' results in re-building module dependencies
      // even when up-to-date.
      var incrementalAlwaysRebuildDriver = try TestDriver(args: invocationArguments + ["-always-rebuild-module-dependencies"])
      let incrementalAlwaysRebuildJobs = try await incrementalAlwaysRebuildDriver.planBuild()
      #expect(!incrementalAlwaysRebuildDriver.diagnosticEngine.hasErrors)
      #expect(incrementalAlwaysRebuildJobs.contains { $0.kind == .generatePCM })
      #expect(incrementalAlwaysRebuildJobs.contains { $0.kind == .compileModuleFromInterface })
    }
  }

  // This is a regression test for the following scenario:
  // 1. The user does a clean build of their project with explicit modules
  // 2. The user starts a subsequent build using changed flags/environment which do not affect incremental builds (e.g. color diagnostics)
  // 3. That flag/environment change does affect PCM hashes returned by the clang dependency scanner.
  // 4. The driver determines that modules need to rebuild, sources don't need to rebuild, and verification needs to re-run.
  // 5. The driver decides it's safe to skip the pre-compile jobs (the module builds) because the only post-compile jobs are for verification.
  // 6. Verification fails because the modules with the new PCM hashes are missing.
  // Ideally, this should never happen. If a flag doesn't invalidate Swift compilation, it shouldn;t be impacting module hashes either. But I
  // think we should be resilient to this by rebuilding the modules in this scenario.
  //
  // The below test is somewhat fragile in that it will be redundant if we canonicalize away -fcolor-diagnostics in clang, but it's useful to ensure
  // end to end behavior does not regress again.
  @Test func explicitModuleBuildDoesNotSkipPrecompiledModulesWhenOnlyVerificationIsInvalidated() async throws {
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testExplicitModuleBuildEndToEnd.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;
        import E;
        import G;

        func foo() {
          funcE()
        }
        """
      )
      // Touch timestamp file, which in process ensures the file system timestamp changed.
      try! localFileSystem.touch(path.appending(component: "timestamp"))
      let outputFileMap = path.appending(component: "output-file-map.json")
      try localFileSystem.writeFileContents(outputFileMap, bytes: ByteString(encodingAsUTF8: """
      {
        "": {
          "swift-dependencies": "\(path.appending(component: "main.swiftdeps").nativePathString(escaped: true))"
        },
        "\(path.appending(component: "testExplicitModuleBuildEndToEnd.swift").nativePathString(escaped: true))": {
          "swift-dependencies": "\(path.appending(component: "testExplicitModuleBuildEndToEnd.swiftdeps").nativePathString(escaped: true))",
          "object": "\(path.appending(component: "testExplicitModuleBuildEndToEnd.o").nativePathString(escaped: true))"
        }
      }
      """))

      let swiftInterfaceOutput = path.appending(component: "Test.swiftinterface")
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let invocationArguments = ["swiftc",
                                 "-swift-version", "5",
                                 "-incremental", "-c",
                                 "-emit-module",
                                 "-enable-library-evolution", "-emit-module-interface", "-driver-show-incremental",
                                 "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
                                 "-I", cHeadersPath.nativePathString(escaped: false),
                                 "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                 "-explicit-module-build",
                                 "-emit-module-interface-path", swiftInterfaceOutput.nativePathString(escaped: false),
                                 "-output-file-map", outputFileMap.nativePathString(escaped: false),
                                 "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                 "-working-directory", path.nativePathString(escaped: false),
                                 main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var driver = try TestDriver(args: invocationArguments)
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      var incrementalDriver = try TestDriver(args: invocationArguments + ["-color-diagnostics"])
      let incrementalJobs = try await incrementalDriver.planBuild()
      try await incrementalDriver.run(jobs: incrementalJobs)
      #expect(!incrementalDriver.diagnosticEngine.hasErrors)
      let state = try #require(incrementalDriver.incrementalCompilationState)
      #expect(state.mandatoryJobsInOrder.contains { $0.kind == .emitModule })
      #expect(state.jobsAfterCompiles.contains { $0.kind == .verifyModuleInterface })

      // TODO: emitModule job should run again if interface is deleted.
      // try localFileSystem.removeFileTree(swiftInterfaceOutput)

      // This should be a null build but it is actually building the main module due to the previous build of all the modules.
      var reDriver = try TestDriver(args: invocationArguments + ["-color-diagnostics"])
      let _ = try await reDriver.planBuild()
      let reState = try #require(reDriver.incrementalCompilationState)
      #expect(!reState.mandatoryJobsInOrder.contains { $0.kind == .emitModule })
      #expect(!reState.jobsAfterCompiles.contains { $0.kind == .verifyModuleInterface })
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
          expectJobInvocationMatches(job, .flag("-explicit-interface-module-build"))
          expectJobInvocationMatches(job, .flag("-explicit-swift-module-map-file"))
          expectJobInvocationMatches(job, .flag("-disable-implicit-swift-modules"))
          continue
        }
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if let outputFileExtension = outputFilePath.extension,
            outputFileExtension == FileType.swiftModule.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "E", "G"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["Swift", "_Concurrency", "_StringProcessing", "SwiftOnoneSupport"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            break
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "B", "C", "D", "G", "F"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SwiftShims", "_SwiftConcurrencyShims", "_Builtin_stdint"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SAL", "_Builtin_intrinsics", "_Builtin_stddef", "_stdlib", "_malloc", "corecrt", "vcruntime"].contains(module):
            guard driver.targetTriple.isWindows else { fallthrough }
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleVerifyInterfaceJobs")),
                .relative(try .init(validating: "testExplicitModuleVerifyInterfaceJobs.exe")):
              #expect(driver.isExplicitMainModuleJob(job: job))
              #expect(job.kind == .link)
            case .absolute(let path):
              #expect(path.basename == "testExplicitModuleVerifyInterfaceJobs")
              #expect(job.kind == .link)
            case .temporary(_):
              let baseName = "testExplicitModuleVerifyInterfaceJobs"
              #expect(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            if outputFilePath.extension == FileType.object.rawValue && driver.isFeatureSupported(.debug_info_explicit_dependency) {
              // Check that this is an absolute path pointing to the temporary directory.
              var found : Bool = false
              for arg in job.commandLine {
                if !found && arg == "-debug-module-path" {
                  found = true
                } else if found {
                  if case let .path(vpath) = arg {
                    #expect(vpath.isTemporary)
                    #expect(vpath.extension == FileType.swiftModule.rawValue)
                  } else {
                    Issue.record("argument is not a path")
                  }
                    break
                }
              }
              #expect(found)
            }
            default:
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build and -pch-output-dir
  @Test func explicitModuleBuildPCHOutputJobs() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildPCHOutputJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let pchOutputDir: AbsolutePath = path
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: false),
                                     "-pch-output-dir", pchOutputDir.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      let dependencyGraph = try #require(driver.intermoduleDependencyGraph)
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildPCHOutputJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        Issue.record("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        #expect(job.outputs.count == 1)
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if let outputFileExtension = outputFilePath.extension,
            outputFileExtension == FileType.swiftModule.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "E", "G"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["Swift", "_Concurrency", "_StringProcessing", "SwiftOnoneSupport"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            break
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "B", "C", "D", "G", "F"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SwiftShims", "_SwiftConcurrencyShims", "_Builtin_stdint"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SAL", "_Builtin_intrinsics", "_Builtin_stddef", "_stdlib", "_malloc", "corecrt", "vcruntime"].contains(module):
            guard driver.targetTriple.isWindows else { fallthrough }
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        // Bridging header
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pch.rawValue {
          switch (outputFilePath) {
            case .absolute:
              // pch output is a computed absolute path.
              #expect(!job.commandLine.contains("-pch-output-dir"))
            default:
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          // Check we don't use `-pch-output-dir` anymore during main module job.
          #expect(!job.commandLine.contains("-pch-output-dir"))
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleBuildPCHOutputJobs")),
                .relative(try .init(validating: "testExplicitModuleBuildPCHOutputJobs.exe")):
              #expect(driver.isExplicitMainModuleJob(job: job))
              #expect(job.kind == .link)
            case .absolute(let path):
              #expect(path.basename == "testExplicitModuleBuildPCHOutputJobs")
              #expect(job.kind == .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildPCHOutputJobs"
              #expect(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  @Test func immediateModeExplicitModuleBuild() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import C\n")

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swift",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)

      let jobs = try await driver.planBuild()

      let interpretJobs = jobs.filter { $0.kind == .interpret }
      #expect(interpretJobs.count == 1)
      let interpretJob = interpretJobs[0]
      #expect(interpretJob.requiresInPlaceExecution)
      expectJobInvocationMatches(interpretJob, .flag("-frontend"), .flag("-interpret"))
      // expectJobInvocationMatches(interpretJob, .flag("-disable-implicit-swift-modules"))
      expectJobInvocationMatches(interpretJob, .flag("-Xcc"), .flag("-fno-implicit-modules"))

      let dependencyGraph = try driver.scanModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        Issue.record("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        guard job.kind != .interpret else { continue }
        #expect(job.outputs.count == 1)
        let outputFilePath = job.outputs[0].file
        // Swift dependencies
        if let outputFileExtension = outputFilePath.extension,
            outputFileExtension == FileType.swiftModule.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["Swift", "_Concurrency", "_StringProcessing", "SwiftOnoneSupport"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            break
          }
        // Clang Dependencies
        } else if let outputFileExtension = outputFilePath.extension,
                  outputFileExtension == FileType.pcm.rawValue {
          switch outputFilePath.basename.split(separator: "-").first {
          case let .some(module) where ["A", "B", "C"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SwiftShims", "_SwiftConcurrencyShims", "_Builtin_stdint"].contains(module):
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          case let .some(module) where ["SAL", "_Builtin_intrinsics", "_Builtin_stddef", "_stdlib", "_malloc", "corecrt", "vcruntime"].contains(module):
            guard driver.targetTriple.isWindows else { fallthrough }
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang(String(module)),
                                            dependencyGraph: dependencyGraph)
          default:
            Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleBuildJobs")):
              #expect(driver.isExplicitMainModuleJob(job: job))
              #expect(job.kind == .link)
            case .absolute(let path):
              #expect(path.basename == "testExplicitModuleBuildJobs")
              #expect(job.kind == .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildJobs"
              #expect(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              Issue.record("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }


  @Test(.requireFrontendArgSupport(.moduleAlias)) func moduleAliasingPrebuiltWithScanDeps() async throws {
    try await withTemporaryDirectory { path in
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      let srcBar = path.appending(component: "bar.swift")
      let moduleBarPath = path.appending(component: "Bar.swiftmodule").nativePathString(escaped: false)
      try localFileSystem.writeFileContents(srcBar, bytes: "public class KlassBar {}")

      // Create Bar.swiftmodule
      var driver = try TestDriver(args: ["swiftc",
                                     "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     srcBar.nativePathString(escaped: false),
                                     "-module-name", "Bar",
                                     "-emit-module",
                                     "-emit-module-path", moduleBarPath,
                                     "-module-cache-path", path.nativePathString(escaped: false),
                                     "-I", stdLibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                              ] + sdkArgumentsForTesting)

      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)
      #expect(FileManager.default.fileExists(atPath: moduleBarPath))

      // Foo imports Car which is mapped to the real module Bar via
      // `-module-alias Car=Bar`; it allows Car (alias) to be referenced
      // in source files, while its contents are compiled as Bar (real
      // name on disk).
      let srcFoo = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(srcFoo, bytes:
        """
        import Car
        func run() -> Car.KlassBar? { return nil }
        """
      )

      // Module alias with the fallback scanner (frontend scanner)
      var driverA = try TestDriver(args: ["swiftc",
                                      "-nonlib-dependency-scanner",
                                      "-explicit-module-build",
                                      "-working-directory",
                                      path.nativePathString(escaped: false),
                                      srcFoo.nativePathString(escaped: false),
                                      "-module-alias", "Car=Bar",
                                      "-I", path.nativePathString(escaped: false),
                                      "-I", stdLibPath.nativePathString(escaped: false),
                                      "-I", shimsPath.nativePathString(escaped: false),
                                     ] + sdkArgumentsForTesting)

      // Resulting graph should contain the real module name Bar
      let dependencyGraphA = try driverA.scanModuleDependencies()
      #expect(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Bar"
      })
      #expect(!dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsA = try await driverA.planBuild()
      #expect(plannedJobsA.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=Bar"))
      })

      // Module alias with the default scanner (driver scanner)
      var driverB = try TestDriver(args: ["swiftc",
                                      "-explicit-module-build",
                                      "-working-directory",
                                      path.nativePathString(escaped: false),
                                      srcFoo.nativePathString(escaped: false),
                                      "-module-alias", "Car=Bar",
                                      "-I", path.nativePathString(escaped: false),
                                      "-I", stdLibPath.nativePathString(escaped: false),
                                      "-I", shimsPath.nativePathString(escaped: false),
                                     ] + sdkArgumentsForTesting)

      // Resulting graph should contain the real module name Bar
      let dependencyGraphB = try driverB.scanModuleDependencies()
      #expect(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Bar"
      })
      #expect(!dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsB = try await driverB.planBuild()
      #expect(plannedJobsB.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=Bar"))
      })
    }
  }

  @Test(.requireFrontendArgSupport(.moduleAlias)) func moduleAliasingInterfaceWithScanDeps() async throws {
    try await withTemporaryDirectory { path in
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")

      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      // Foo imports Car which is mapped to the real module Bar via
      // `-module-alias Car=E`; it allows Car (alias) to be referenced
      // in source files, while its contents are compiled as E (real
      // name on disk).
      let srcFoo = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(srcFoo, bytes: "import Car\n")

      // Module alias with the fallback scanner (frontend scanner)
      var driverA = try TestDriver(args: ["swiftc",
                                      "-nonlib-dependency-scanner",
                                      "-explicit-module-build",
                                      srcFoo.nativePathString(escaped: false),
                                      "-module-alias", "Car=E",
                                      "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                      "-I", stdLibPath.nativePathString(escaped: false),
                                      "-I", shimsPath.nativePathString(escaped: false),
                                     ] + sdkArgumentsForTesting)

      // Resulting graph should contain the real module name Bar
      let dependencyGraphA = try driverA.scanModuleDependencies()
      #expect(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "E"
      })
      #expect(!dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsA = try await driverA.planBuild()
      #expect(plannedJobsA.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=E"))
      })

      // Module alias with the default scanner (driver scanner)
      var driverB = try TestDriver(args: ["swiftc",
                                      "-explicit-module-build",
                                      srcFoo.nativePathString(escaped: false),
                                      "-module-alias", "Car=E",
                                      "-working-directory", path.nativePathString(escaped: false),
                                      "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                      "-I", stdLibPath.nativePathString(escaped: false),
                                      "-I", shimsPath.nativePathString(escaped: false),
                                     ] + sdkArgumentsForTesting)

      // Resulting graph should contain the real module name Bar
      let dependencyGraphB = try driverB.scanModuleDependencies()
      #expect(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "E"
      })
      #expect(!dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsB = try await driverB.planBuild()
      #expect(plannedJobsB.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=E"))
      })
    }
  }

  @Test(.requireFrontendArgSupport(.moduleAlias)) func moduleAliasingWithImportPrescan() async throws {
    let (_, _, toolchain, _) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

    try withTemporaryDirectory { path in
      let main = path.appending(component: "foo.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import Car;\
        import Jet;
        """
      )
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let scannerCommand = ["-scan-dependencies",
                            "-import-prescan",
                            "-module-alias",
                            "Car=Bar",
                            main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let deps =
        try dependencyOracle.getImports(workingDirectory: path,
                                        moduleAliases: ["Car": "Bar"],
                                        commandLine: scannerCommand,
                                        diagnostics: &scanDiagnostics)

      #expect(deps.imports.contains("Bar"))
      #expect(!deps.imports.contains("Car"))
      #expect(deps.imports.contains("Jet"))
    }
  }

  @Test(.requireFrontendArgSupport(.moduleAlias)) func moduleAliasingWithExplicitBuild() async throws {
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let srcBar = path.appending(component: "bar.swift")
      let moduleBarPath = path.appending(component: "Bar.swiftmodule").nativePathString(escaped: false)
      try localFileSystem.writeFileContents(srcBar, bytes: "public class KlassBar {}")

      // Explicitly use an output file map to avoid an in-place job.
      let outputFileMap = path.appending(component: "output-file-map.json")
      try localFileSystem.writeFileContents(outputFileMap, bytes: """
      {
        "": {
          "swift-dependencies": "Bar.swiftdeps"
        }
      }
      """)

      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      var driver1 = try TestDriver(args: ["swiftc",
                                      "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
                                      "-explicit-module-build",
                                      "-module-name", "Bar",
                                      "-working-directory", path.nativePathString(escaped: false),
                                      "-output-file-map", outputFileMap.nativePathString(escaped: false),
                                      "-emit-module",
                                      "-emit-module-path", moduleBarPath,
                                      "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                      srcBar.nativePathString(escaped: false),
                                      "-I", stdLibPath.nativePathString(escaped: false),
                                      "-I", shimsPath.nativePathString(escaped: false),
                                     ] + sdkArgumentsForTesting)

      let jobs1 = try await driver1.planBuild()
      try await driver1.run(jobs: jobs1)
      #expect(!driver1.diagnosticEngine.hasErrors)
      #expect(FileManager.default.fileExists(atPath: moduleBarPath))

      let srcFoo = path.appending(component: "foo.swift")
      let moduleFooPath = path.appending(component: "Foo.swiftmodule").nativePathString(escaped: false)

      // Module Foo imports Car but it's mapped to Bar (real name)
      // `-module-alias Car=Bar` allows Car (alias) to be referenced
      // in source files in Foo, but its contents will be compiled
      // as Bar (real name on-disk).
      try localFileSystem.writeFileContents(srcFoo, bytes:
        """
        import Car
        func run() -> Car.KlassBar? { return nil }
        """
      )
      var driver2 = try TestDriver(args: ["swiftc",
                                      "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
                                      "-I", path.nativePathString(escaped: false),
                                      "-explicit-module-build",
                                      "-module-name", "Foo",
                                      "-working-directory", path.nativePathString(escaped: false),
                                      "-output-file-map", outputFileMap.nativePathString(escaped: false),
                                      "-emit-module",
                                      "-emit-module-path", moduleFooPath,
                                      "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                      "-module-alias", "Car=Bar",
                                      srcFoo.nativePathString(escaped: false),
                                      "-I", stdLibPath.nativePathString(escaped: false),
                                      "-I", shimsPath.nativePathString(escaped: false),
                                      ] + sdkArgumentsForTesting)
      let jobs2 = try await driver2.planBuild()
      try await driver2.run(jobs: jobs2)
      #expect(!driver2.diagnosticEngine.hasErrors)
      #expect(FileManager.default.fileExists(atPath: moduleFooPath))
    }
  }

  @Test func explicitModuleBuildEndToEnd() async throws {
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testExplicitModuleBuildEndToEnd.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;
        import E;
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)
    }
  }

  @Test func inMemoryScanWithSerializedDiagnostics() async throws {
    try withTemporaryDirectory { path in
      let (stdLibPath, shimsPath, _, hostTriple) = try getDriverArtifactsForScanning()
      let scannerCachePath: AbsolutePath = path.appending(component: "ClangScannerCache")
      let moduleCachePath = path.appending(component: "ModuleCache")
      let serializedDiagnosticsOutputPath = path.appending(component: "ScanDiags.dia")

      // Setup our main test module
      let mainSourcePath = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(mainSourcePath, bytes: "import Swift")

      // Setup the build plan
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", stdLibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-dependency-scan-serialize-diagnostics-path",
                                     serializedDiagnosticsOutputPath.nativePathString(escaped: false),
                                     "-module-name", "main",
                                     "-target", hostTriple.triple,
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-clang-scanner-module-cache-path",
                                     scannerCachePath.nativePathString(escaped: false),
                                     "-module-cache-path",
                                     moduleCachePath.nativePathString(escaped: false),
                                     mainSourcePath.nativePathString(escaped: false)] + sdkArgumentsForTesting)

      // Set up the in-memory dependency scan using the dependency oracle
      let dependencyOracle = driver.interModuleDependencyOracle
      let scanLibPath = try #require(try driver.toolchain.lookupSwiftScanLib())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      #expect(scannerCommand.contains(subsequence: ["-serialize-diagnostics-path", serializedDiagnosticsOutputPath.pathString]))

      // Perform the scan
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let _ = try dependencyOracle.getDependencies(workingDirectory: path,
                                                   commandLine: scannerCommand,
                                                   diagnostics: &scanDiagnostics)

      // TODO: Ensure the serialized diagnostics output got written out
      // This requires an ability to confirm first whether the compiler we're using
      // has this capability.
      // #expect(localFileSystem.exists(serializedDiagnosticsOutputPath))
    }
  }

  @Test(.requireScannerSupportsBinaryFrameworkDependencies()) func binaryFrameworkDependencyScan() async throws {
    try await withTemporaryDirectory { path in
      let (stdLibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()
      let moduleCachePath = path.appending(component: "ModuleCache")

      // Setup module to be used as dependency
      try localFileSystem.createDirectory(moduleCachePath)
      let frameworksPath = path.appending(component: "Frameworks")
      let frameworkModuleDir = frameworksPath.appending(component: "Foo.framework")
                                             .appending(component: "Modules")
                                             .appending(component: "Foo.swiftmodule")
      let frameworkModulePath =
          frameworkModuleDir.appending(component: hostTriple.archName + ".swiftmodule")
      try localFileSystem.createDirectory(frameworkModuleDir, recursive: true)
      let fooSourcePath = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(fooSourcePath, bytes: "public func foo() {}")

      // Setup our main test module
      let mainSourcePath = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(mainSourcePath, bytes: "import Foo")

      // 1. Build Foo module
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driverFoo = try TestDriver(args: ["swiftc",
                                        "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                        "-module-name", "Foo",
                                        "-emit-module",
                                        "-emit-module-path",
                                        frameworkModulePath.nativePathString(escaped: false),
                                        "-working-directory",
                                        path.nativePathString(escaped: false),
                                        fooSourcePath.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driverFoo.planBuild()
      try await driverFoo.run(jobs: jobs)
      #expect(!driverFoo.diagnosticEngine.hasErrors)

      // 2. Run a dependency scan to find the just-built module
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

      var driver = try TestDriver(args: ["swiftc",
                                     "-I", stdLibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-F", frameworksPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-module-name", "main",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     mainSourcePath.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let dependencyGraph =
          try dependencyOracle.getDependencies(workingDirectory: path,
                                               commandLine: scannerCommand,
                                               diagnostics: &scanDiagnostics)

      let fooDependencyInfo = try #require(dependencyGraph.modules[.swiftPrebuiltExternal("Foo")])
      guard case .swiftPrebuiltExternal(let fooDetails) = fooDependencyInfo.details else {
        Issue.record("Foo dependency module does not have Swift details field")
        return
      }

      // Ensure the dependency has been reported as a framework
      #expect(fooDetails.isFramework == true)
    }
  }

  /// Test the libSwiftScan dependency scanning (import-prescan).
  @Test func dependencyImportPrescan() async throws {
    let (stdLibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;"
        """
      )
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let scannerCommand = ["-scan-dependencies",
                            "-import-prescan",
                            "-I", cHeadersPath.nativePathString(escaped: false),
                            "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                            "-I", stdLibPath.nativePathString(escaped: false),
                            "-I", shimsPath.nativePathString(escaped: false),
                            main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let imports =
        try dependencyOracle.getImports(workingDirectory: path,
                                        commandLine: scannerCommand,
                                        diagnostics: &scanDiagnostics)
      let expectedImports = ["C", "E", "G", "Swift", "SwiftOnoneSupport"]
      // Dependnig on how recent the platform we are running on, the _Concurrency module may or may not be present.
      let expectedImports2 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency"]
      // Dependnig on how recent the platform we are running on, the _StringProcessing module may or may not be present.
      let expectedImports3 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency", "_StringProcessing"]
      // Dependnig on how recent the platform we are running on, the _SwiftConcurrencyShims module may or may not be present.
      let expectedImports4 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency", "_StringProcessing", "_SwiftConcurrencyShims"]
      let expectedImports5 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency", "_SwiftConcurrencyShims"]
      #expect(
        Set(imports.imports) == Set(expectedImports) ||
        Set(imports.imports) == Set(expectedImports2) ||
        Set(imports.imports) == Set(expectedImports3) ||
        Set(imports.imports) == Set(expectedImports4) ||
        Set(imports.imports) == Set(expectedImports5))
    }
  }


  /// Test that the scanner invocation does not rely in response files
  @Test func dependencyScanningNoResponse() async throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      // With a number of inputs this large, a response file should be generated
      // unless explicitly not supported, as should be the case for scan-deps.
      let lotsOfInputs = (0...700).map{"test\($0).swift"}
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + lotsOfInputs + sdkArgumentsForTesting)
      let scannerJob = try driver.dependencyScanningJob()

      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let (args, _) = try resolver.resolveArgumentList(for: scannerJob,
                                                       useResponseFiles: .disabled)
      #expect(args.count > 1)
      #expect(!args[0].hasSuffix(".resp"))
    }
  }

  /// Test that the scanner invocation does not rely on response files
  @Test(.requireFrontendArgSupport(.clangScannerModuleCachePath)) func dependencyScanningSeparateClangScanCache() async throws {
    try withTemporaryDirectory { path in
      let scannerCachePath: AbsolutePath = path.appending(component: "ClangScannerCache")
      let moduleCachePath: AbsolutePath = path.appending(component: "ModuleCache")
      let main = path.appending(component: "testDependencyScanningSeparateClangScanCache.swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-explicit-module-build",
                                     "-clang-scanner-module-cache-path",
                                     scannerCachePath.nativePathString(escaped: false),
                                     "-module-cache-path",
                                     moduleCachePath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)

      let scannerJob = try driver.dependencyScanningJob()
      expectCommandLineContains(scannerJob.commandLine, .flag("-clang-scanner-module-cache-path"), .path(.absolute(scannerCachePath)))
    }
  }

  @Test(.requireScannerSupportsPerScanDiagnostics()) func dependencyScanningFailure() async throws {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

    // Missing Swift Interface dependency
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes: "import S;")

      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let _ =
          try dependencyOracle.getDependencies(workingDirectory: path,
                                               commandLine: scannerCommand,
                                               diagnostics: &scanDiagnostics)
      #expect(scanDiagnostics.count == 5)
      let diags = scanDiagnostics
      let error = diags[0]
      #expect(error.severity == .error)
      if try dependencyOracle.supportsDiagnosticSourceLocations() {
        let errorVariant1 =
          """
          Unable to find module dependency: 'unknown_module'
          import unknown_module
                 ^
          """
        let errorVariant2 =
          """
          unable to resolve module dependency: 'unknown_module'
          import unknown_module
                 ^
          """
        #expect(error.message == errorVariant1 || error.message == errorVariant2)
        let sourceLoc = try #require(error.sourceLocation)
        #expect(sourceLoc.bufferIdentifier.hasSuffix("I.swiftinterface"))
        #expect(sourceLoc.lineNumber == 3)
        #expect(sourceLoc.columnNumber == 8)
      } else {
        #expect(error.message == "Unable to find module dependency: 'unknown_module'")
      }
      let noteI = diags[1]
      #expect(noteI.message.starts(with: "a dependency of Swift module 'I':"))
      #expect(noteI.severity == .note)
      let noteW = diags[2]
      #expect(noteW.message.starts(with: "a dependency of Swift module 'W':"))
      #expect(noteW.severity == .note)
      let noteS = diags[3]
      #expect(noteS.message.starts(with: "a dependency of Swift module 'S':"))
      #expect(noteS.severity == .note)
      let noteTest = diags[4]
      if try dependencyOracle.supportsDiagnosticSourceLocations() {
        #expect(noteTest.message ==
        """
        a dependency of main module 'testDependencyScanning'
        import unknown_module
               ^
        """
        )
      } else {
        #expect(noteTest.message == "a dependency of main module 'testDependencyScanning'")
      }
      #expect(noteTest.severity == .note)
    }

    // Missing main module dependency
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes: "import FooBar")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let _ =
          try dependencyOracle.getDependencies(workingDirectory: path,
                                               commandLine: scannerCommand,
                                               diagnostics: &scanDiagnostics)
      #expect(scanDiagnostics.count == 2)
      let diags = scanDiagnostics
      let error = diags[0]
      #expect(error.severity == .error)
      if try dependencyOracle.supportsDiagnosticSourceLocations() {
        let errorVariant1 =
          """
          Unable to find module dependency: 'FooBar'
          import FooBar
                 ^
          """
        let errorVariant2 =
          """
          unable to resolve module dependency: 'FooBar'
          import FooBar
                 ^
          """
        #expect(error.message == errorVariant1 || error.message == errorVariant2)
        let sourceLoc = try #require(error.sourceLocation)
        #expect(sourceLoc.bufferIdentifier.hasSuffix("testDependencyScanning.swift"))
        #expect(sourceLoc.lineNumber == 1)
        #expect(sourceLoc.columnNumber == 8)
      } else {
        #expect(error.message == "Unable to find module dependency: 'FooBar'")
      }
      let noteTest = diags[1]
      if try dependencyOracle.supportsDiagnosticSourceLocations() {
        #expect(noteTest.message ==
        """
        a dependency of main module 'testDependencyScanning'
        import FooBar
               ^
        """
        )
      } else {
        #expect(noteTest.message == "a dependency of main module 'testDependencyScanning'")
      }
      #expect(noteTest.severity == .note)
    }
  }

  /// Test the libSwiftScan dependency scanning.
  @Test func dependencyScanningPluginFlagPropagation() async throws {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

    // Create a simple test case.
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "/tmp/Foo.o",
                                     "-plugin-path", "PluginA", "-external-plugin-path", "Plugin~B#Bexe",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      #expect(scannerCommand.contains("-plugin-path"))
      #expect(scannerCommand.contains("-external-plugin-path"))
      let jobs = try await driver.planBuild()
      for job in jobs {
        if job.kind != .compile {
          continue
        }
        let command = try job.commandLine.map { try resolver.resolve($0) }
        #expect(command.contains { $0 == "-in-process-plugin-server-path" })
      }
    }
  }

  /// Test the libSwiftScan dependency scanning.
  @Test func dependencyScanning() async throws {
    let (stdlibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)

    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: false),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-I", stdlibPath.nativePathString(escaped: false),
                                     "-I", shimsPath.nativePathString(escaped: false),
                                     "/tmp/Foo.o",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly via libSwiftScan.
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }

      if driver.isFrontendArgSupported(.scannerModuleValidation) {
        #expect(scannerCommand.contains("-scanner-module-validation"))
      }

      // Ensure we do not propagate the usual PCH-handling arguments to the scanner invocation
      #expect(!scannerCommand.contains("-pch-output-dir"))
      #expect(!scannerCommand.contains("Foo.o"))

      // Here purely to dump diagnostic output in a reasonable fashion when things go wrong.
      let lock = NSLock()

      // Module `X` is only imported on Darwin when:
      // #if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 110000
      let expectedNumberOfDependencies: Int
      if hostTriple.isMacOSX,
         hostTriple.version(for: .macOS) < Triple.Version(11, 0, 0) {
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
    }
  }

  // Ensure dependency scanning succeeds via fallback `swift-frontend -scan-dependenceis`
  // mechanism if libSwiftScan.dylib fails to load.
  @Test(.disabled("skipping until CAS is supported on all platforms"))
  func dependencyScanningFallback() async throws {

    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanningFallback.swift")
      try localFileSystem.writeFileContents(main, bytes: "import C;")

      let dummyBrokenDylib = path.appending(component: "lib_InternalSwiftScan.dylib")
      try localFileSystem.writeFileContents(dummyBrokenDylib, bytes: "n/a")

      var environment = ProcessEnv.block
      environment["SWIFT_DRIVER_SWIFTSCAN_LIB"] = dummyBrokenDylib.nativePathString(escaped: false)

      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
      let sdkArgumentsForTesting: [String] = (try? Driver.sdkArgumentsForTesting()) ?? []
      let driverArgs: [String] = ["swiftc",
                                  "-I", cHeadersPath.nativePathString(escaped: false),
                                  "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                  "-I", stdlibPath.nativePathString(escaped: false),
                                  "-I", shimsPath.nativePathString(escaped: false),
                                  "/tmp/Foo.o",
                                  "-explicit-module-build",
                                  "-working-directory", path.nativePathString(escaped: false),
                                  "-disable-clang-target",
                                  main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      do {
        var driver = try TestDriver(args: driverArgs, env: environment)
        let interModuleDependencyGraph = try driver.performDependencyScan()
        #expect(driver.diagnosticEngine.diagnostics.contains { $0.behavior == .warning &&
          $0.message.text == "In-process dependency scan query failed due to incompatible libSwiftScan (\(dummyBrokenDylib.nativePathString(escaped: false))). Fallback to `swift-frontend` dependency scanner invocation. Specify '-nonlib-dependency-scanner' to silence this warning."})
        #expect(interModuleDependencyGraph.mainModule.directDependencies?.contains(where: { $0.moduleName == "C" }) == true)
      }

      // Ensure no warning is emitted with '-nonlib-dependency-scanner'
      do {
        var driver = try TestDriver(args: driverArgs + ["-nonlib-dependency-scanner"], env: environment)
        let _ = try driver.performDependencyScan()
        #expect(!driver.diagnosticEngine.diagnostics.contains { $0.behavior == .warning &&
          $0.message.text == "In-process dependency scan query failed due to incompatible libSwiftScan (\(dummyBrokenDylib.nativePathString(escaped: false))). Fallback to `swift-frontend` dependency scanner invocation. Specify '-nonlib-dependency-scanner' to silence this warning."})
      }

      // Ensure error is emitted when caching is enabled
      do {
        var driver = try TestDriver(args: driverArgs + ["-cache-compile-job"], env: environment)
        let _ = try driver.performDependencyScan()
        #expect(!driver.diagnosticEngine.diagnostics.contains { $0.behavior == .error &&
          $0.message.text == "Swift Caching enabled - libSwiftScan load failed (\(dummyBrokenDylib.nativePathString(escaped: false))."})
      }
    }
  }

  @Test(.requireScannerSupportsPerScanDiagnostics()) func parallelDependencyScanningDiagnostics() async throws {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()
    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
    // Create a simple test case.
    try withTemporaryDirectory { path in
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let baseDriverArgs = ["swiftc",
                            "-I", cHeadersPath.nativePathString(escaped: false),
                            "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                            "-I", stdlibPath.nativePathString(escaped: false),
                            "-I", shimsPath.nativePathString(escaped: false),
                            "/tmp/Foo.o",
                            "-explicit-module-build",
                            "-working-directory", path.nativePathString(escaped: false),
                            "-disable-clang-target"] + sdkArgumentsForTesting
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let numFiles = 10
      var files: [AbsolutePath] = []
      var drivers: [Driver] = []
      var scannerCommands: [[String]] = []
      for fileIndex in 0..<numFiles {
        files.append(path.appending(component: "testParallelDependencyScanningDiagnostics\(fileIndex).swift"))
        try localFileSystem.writeFileContents(files.last!, bytes: ByteString(encodingAsUTF8: "import UnknownModule\(fileIndex);"))
        var driver = try TestDriver(args: baseDriverArgs +
                                      [files.last!.nativePathString(escaped: false)] +
                                      ["-module-name","testParallelDependencyScanningDiagnostics\(fileIndex)"] +
                                       // FIXME: We need to differentiate the scanning action hash,
                                       // though the module-name above should be sufficient.
                                      ["-I/tmp/foo/bar/\(fileIndex)"])
        var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
        if scannerCommand.first == "-frontend" {
          scannerCommand.removeFirst()
        }
        scannerCommands.append(scannerCommand)
        driver.unwrap {
          (d: Driver) in drivers.append(d)
        }
      }
      let scanCommandsSnapshot = scannerCommands
      // Each iteration accesses a distinct index — no actual data race.
      nonisolated(unsafe) var scanDiagnostics = [[ScannerDiagnosticPayload]](repeating: [], count: numFiles)
      // Execute scans concurrently
      DispatchQueue.concurrentPerform(iterations: numFiles) { scanIndex in
        do {
          let _ =
            try dependencyOracle.getDependencies(workingDirectory: path,
                                                 commandLine: scanCommandsSnapshot[scanIndex],
                                                 diagnostics: &scanDiagnostics[scanIndex])
        } catch {
          Issue.record("Unexpected error: \(error)")
        }
      }
      // Examine the results
      for scanIndex in 0..<numFiles {
        let diagnostics = scanDiagnostics[scanIndex]
        #expect(diagnostics.count == 2)
        // Diagnostic source locations came after per-scan diagnostics, only meaningful
        // on this test code-path
        if try dependencyOracle.supportsDiagnosticSourceLocations() {
          let sourceLoc = try #require(diagnostics[0].sourceLocation)
          #expect(sourceLoc.lineNumber == 1)
          #expect(sourceLoc.columnNumber == 8)
          let errorVariant1 =
            """
            Unable to find module dependency: 'UnknownModule\(scanIndex)'
            import UnknownModule\(scanIndex);
                   ^
            """
          let errorVariant2 =
            """
            unable to resolve module dependency: 'UnknownModule\(scanIndex)'
            import UnknownModule\(scanIndex);
                   ^
            """
          #expect(diagnostics[0].message == errorVariant1 || diagnostics[0].message == errorVariant2)
          let noteSourceLoc = try #require(diagnostics[1].sourceLocation)
          #expect(noteSourceLoc.lineNumber == 1)
          #expect(noteSourceLoc.columnNumber == 8)
          #expect(diagnostics[1].message ==
              """
              a dependency of main module 'testParallelDependencyScanningDiagnostics\(scanIndex)'
              import UnknownModule\(scanIndex);
                     ^
              """)
        } else {
          #expect(diagnostics[0].message == "Unable to find module dependency: 'UnknownModule\(scanIndex)'")
          #expect(diagnostics[1].message == "a dependency of main module 'testParallelDependencyScanningDiagnostics\(scanIndex)'")
        }
      }
    }
  }

  @Test func printingExplicitDependencyGraph() async throws {
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testPrintingExplicitDependencyGraph.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )
      let cHeadersPath: AbsolutePath = try testInputsPath.appending(component: "ExplicitModuleBuilds").appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath = try testInputsPath.appending(component: "ExplicitModuleBuilds").appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      let baseCommandLine = ["swiftc",
                             "-I", cHeadersPath.nativePathString(escaped: false),
                             "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                             main.nativePathString(escaped: false)] + sdkArgumentsForTesting
      do {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try TestDriver(args: baseCommandLine + ["-print-explicit-dependency-graph"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try await driver.planBuild()
        #expect(diagnosticEngine.hasErrors)
        #expect(diagnosticEngine.diagnostics.first?.message.data.description ==
                       "'-print-explicit-dependency-graph' cannot be specified if '-explicit-module-build' is not present")
      }
      do {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try TestDriver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-explicit-dependency-graph-format=json"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try await driver.planBuild()
        #expect(diagnosticEngine.hasErrors)
        #expect(diagnosticEngine.diagnostics.first?.message.data.description ==
                       "'-explicit-dependency-graph-format=' cannot be specified if '-print-explicit-dependency-graph' is not present")
      }
      do {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try TestDriver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=watercolor"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try await driver.planBuild()
        #expect(diagnosticEngine.hasErrors)
        #expect(diagnosticEngine.diagnostics.first?.message.data.description ==
                       "unsupported argument \'watercolor\' to option \'-explicit-dependency-graph-format=\'")
      }

      let _ = try await withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try TestDriver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=json"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try await driver.planBuild()
      }

      let output = try await withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try TestDriver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=json"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try await driver.planBuild()
      }
      #expect(output.contains("\"mainModuleName\" : \"testPrintingExplicitDependencyGraph\""))

      let output2 = try await withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try TestDriver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=dot"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try await driver.planBuild()
      }
      #expect(output2.contains("\"testPrintingExplicitDependencyGraph\" [shape=box, style=bold, color=navy"))

      let output3 = try await withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try TestDriver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try await driver.planBuild()
      }
      #expect(output3.contains("\"mainModuleName\" : \"testPrintingExplicitDependencyGraph\""))
    }
  }

  @Test func dependencyGraphDotSerialization() async throws {
      let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try #require(try toolchain.lookupSwiftScanLib())
      try dependencyOracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
      // Create a simple test case.
      try withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import C;\
          import E;\
          import G;
          """
        )

        let cHeadersPath: AbsolutePath =
            try testInputsPath.appending(component: "ExplicitModuleBuilds")
                              .appending(component: "CHeaders")
        let swiftModuleInterfacesPath: AbsolutePath =
            try testInputsPath.appending(component: "ExplicitModuleBuilds")
                              .appending(component: "Swift")
        let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
        var driver = try TestDriver(args: ["swiftc",
                                       "-I", cHeadersPath.nativePathString(escaped: false),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                       "-I", stdlibPath.nativePathString(escaped: false),
                                       "-I", shimsPath.nativePathString(escaped: false),
                                       "-explicit-module-build",
                                       "-working-directory", path.nativePathString(escaped: false),
                                       "-disable-clang-target",
                                       main.nativePathString(escaped: false)] + sdkArgumentsForTesting)
        let resolver = try ArgsResolver(fileSystem: localFileSystem)
        var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
        if scannerCommand.first == "-frontend" {
          scannerCommand.removeFirst()
        }
        var scanDiagnostics: [ScannerDiagnosticPayload] = []
        let dependencyGraph =
          try dependencyOracle.getDependencies(workingDirectory: path,
                                               commandLine: scannerCommand,
                                               diagnostics: &scanDiagnostics)
        let serializer = DOTModuleDependencyGraphSerializer(dependencyGraph)

        let outputFile = path.appending(component: "dependency_graph.dot")
        var outputStream = try ThreadSafeOutputByteStream(LocalFileOutputByteStream(outputFile))
        serializer.writeDOT(to: &outputStream)
        outputStream.flush()
        let contents = try localFileSystem.readFileContents(outputFile).description
        #expect(contents.contains("\"testDependencyScanning\" [shape=box, style=bold, color=navy"))
        #expect(contents.contains("\"G\" [style=bold, color=orange"))
        #expect(contents.contains("\"E\" [style=bold, color=orange, style=filled"))
        #expect(contents.contains("\"C (C)\" [style=bold, color=lightskyblue, style=filled"))
        #expect(contents.contains("\"Swift\" [style=bold, color=orange, style=filled") ||
                      contents.contains("\"Swift (Prebuilt)\" [style=bold, color=darkorange3, style=filled"))
        #expect(contents.contains("\"SwiftShims (C)\" [style=bold, color=lightskyblue, style=filled"))
        #expect(contents.contains("\"Swift\" -> \"SwiftShims (C)\" [color=black];") ||
	              contents.contains("\"Swift (Prebuilt)\" -> \"SwiftShims (C)\" [color=black];"))
      }
  }

  @Test func dependencyScanCommandLineEscape() throws {
#if os(Windows)
  let quote: Character = "\""
#else
  let quote: Character = "'"
#endif
    let input1 = try AbsolutePath(validating: "/tmp/input example/test.swift")
    let input2 = try AbsolutePath(validating: "/tmp/baz.swift")
    let input3 = try AbsolutePath(validating: "/tmp/input example/bar.o")
    var driver = try TestDriver(args: ["swiftc", "-explicit-module-build",
                                   "-module-name", "testDependencyScanning",
                                   input1.nativePathString(escaped: false),
                                   input2.nativePathString(escaped: false),
                                   "-Xcc", input3.nativePathString(escaped: false)])
    let scanJob = try driver.dependencyScanningJob()
    let scanJobCommand = try Driver.itemizedJobCommand(of: scanJob,
                                                       useResponseFiles: .disabled,
                                                       using: ArgsResolver(fileSystem: InMemoryFileSystem()))
    #expect(scanJobCommand.contains("\(quote)\(input1.nativePathString(escaped: false))\(quote)"))
    #expect(scanJobCommand.contains("\(quote)\(input3.nativePathString(escaped: false))\(quote)"))
    #expect(scanJobCommand.contains(input2.nativePathString(escaped: false)))
  }

  @Test func dependencyGraphTransitiveClosure() throws {
    let moduleDependencyGraph =
          try JSONDecoder().decode(
            InterModuleDependencyGraph.self,
            from: ModuleDependenciesInputs.simpleDependencyGraphInputWithSwiftOverlayDep.data(using: .utf8)!)
    let reachabilityMap = try moduleDependencyGraph.computeTransitiveClosure()
    let mainModuleDependencies = try #require(reachabilityMap[.swift("simpleTestModule")])
    let aModuleDependencies = try #require(reachabilityMap[.swift("A")])
    #expect(mainModuleDependencies.contains(.swift("B")))
    #expect(aModuleDependencies.contains(.swift("B")))
  }

  @Test func explicitSwiftModuleMap() throws {
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
    #expect(moduleMap.count == 2)
    #expect(moduleMap[0].moduleName == "A")
    #expect(moduleMap[0].modulePath.path.description == "A.swiftmodule")
    #expect(moduleMap[0].docPath!.path.description == "A.swiftdoc")
    #expect(moduleMap[0].sourceInfoPath!.path.description == "A.swiftsourceinfo")
    #expect(moduleMap[0].isFramework == true)
    #expect(moduleMap[1].moduleName == "B")
    #expect(moduleMap[1].modulePath.path.description == "B.swiftmodule")
    #expect(moduleMap[1].docPath!.path.description == "B.swiftdoc")
    #expect(moduleMap[1].sourceInfoPath!.path.description == "B.swiftsourceinfo")
    #expect(moduleMap[1].isFramework == false)
  }

  @Test func traceDependency() async throws {
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testTraceDependency.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      // Detailed explain (all possible paths)
      do {
        try await assertDriverDiagnostics(args: [
            "swiftc",
            "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
            "-I", cHeadersPath.nativePathString(escaped: false),
            "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
            "-explicit-module-build",
            "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
            "-working-directory", path.nativePathString(escaped: false),
            "-explain-module-dependency-detailed", "A",
            main.nativePathString(escaped: false)
        ] + sdkArgumentsForTesting) { driver, diagnostics in
          diagnostics.forbidUnexpected(.error, .warning, .note, .remark)
          diagnostics.expect(.remark("Module 'testTraceDependency' depends on 'A'"))
          diagnostics.expect(.note("[testTraceDependency] -> [A] -> [A](ObjC)"))
          diagnostics.expect(.note("[testTraceDependency] -> [C](ObjC) -> [B](ObjC) -> [A](ObjC)"))
          try await driver.run(jobs: driver.planBuild())
        }
      }

      // Simple explain (first available path)
      do {
        try await assertDriverDiagnostics(args:[
            "swiftc",
            "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
            "-I", cHeadersPath.nativePathString(escaped: false),
            "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
            "-explicit-module-build",
            "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
            "-working-directory", path.nativePathString(escaped: false),
            "-explain-module-dependency", "A",
            main.nativePathString(escaped: false)
        ] + sdkArgumentsForTesting) { driver, diagnostics in
          diagnostics.forbidUnexpected(.error, .warning, .note, .remark)
          diagnostics.expect(.remark("Module 'testTraceDependency' depends on 'A'"))
          diagnostics.expect(.note("[testTraceDependency] -> [A] -> [A](ObjC)"),
                             alternativeMessage: .note("[testTraceDependency] -> [C](ObjC) -> [B](ObjC) -> [A](ObjC)"))
          try await driver.run(jobs: driver.planBuild())
        }
      }
    }
  }

  @Test func emitModuleSeparatelyJobs() async throws {
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let fileA = path.appending(component: "fileA.swift")
      try localFileSystem.writeFileContents(fileA, bytes:
        """
        public struct A {}
        """
      )
      let fileB = path.appending(component: "fileB.swift")
      try localFileSystem.writeFileContents(fileB, bytes:
        """
        public struct B {}
        """
      )

      let outputModule = path.appending(component: "Test.swiftmodule")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc",
                                     "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
                                     "-explicit-module-build", "-module-name", "Test",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                     "-working-directory", path.nativePathString(escaped: false),
                                     "-emit-module", "-emit-module-path", outputModule.nativePathString(escaped: false),
                                     "-experimental-emit-module-separately",
                                     fileA.nativePathString(escaped: false), fileB.nativePathString(escaped: false)] + sdkArgumentsForTesting)
      let jobs = try await driver.planBuild()
      let compileJobs = jobs.filter({ $0.kind == .compile })
      #expect(compileJobs.count == 0)
      let emitModuleJob = jobs.filter({ $0.kind == .emitModule })
      #expect(emitModuleJob.count == 1)
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)
    }
  }

  @Test func clangTargetOptionsExplicit() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
    let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
    let mockSDKPath: AbsolutePath =
      try testInputsPath.appending(component: "mock-sdk.sdk")

    // Only '-target' is specified, the driver infers '-clang-target' from SDK deployment target
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import A;
          """
        )
        var driver = try TestDriver(args: ["swiftc",
                                       "-target", "x86_64-apple-macosx10.10",
                                       "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                       "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                       "-emit-module",
                                       "-emit-module-path", "foo.swiftmodule/target.swiftmodule",
                                       "-I", cHeadersPath.nativePathString(escaped: false),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                       "-I", stdlibPath.nativePathString(escaped: false),
                                       "-I", shimsPath.nativePathString(escaped: false),
                                       "-explicit-module-build",
                                       "-sdk", mockSDKPath.nativePathString(escaped: false),
                                       main.pathString])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try #require(plannedJobs.findJobs(.emitModule).spm_only)
        expectCommandLineContains(emitModuleJob.commandLine, .flag("-sdk"))
        #expect(emitModuleJob.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("x86_64-apple-macosx10.15")]))
      }
    }

    // User-specified '-clang-target'
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import A;
          """
        )
        var driver = try TestDriver(args: ["swiftc",
                                       "-target", "x86_64-apple-macosx10.10",
                                       "-clang-target", "x86_64-apple-macosx10.12",
                                       "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                       "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                       "-emit-module",
                                       "-emit-module-path", "foo.swiftmodule/target.swiftmodule",
                                       "-I", cHeadersPath.nativePathString(escaped: false),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                       "-I", stdlibPath.nativePathString(escaped: false),
                                       "-I", shimsPath.nativePathString(escaped: false),
                                       "-explicit-module-build",
                                       "-sdk", mockSDKPath.nativePathString(escaped: false),
                                       main.pathString])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try #require(plannedJobs.findJobs(.emitModule).spm_only)
        expectCommandLineContains(emitModuleJob.commandLine, .flag("-sdk"))
        #expect(emitModuleJob.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("x86_64-apple-macosx10.12")]))
      }
    }

    // Only '-target' and '-target-variant' is specified, the driver infers '-clang-target' from SDK deployment target
    // and '-clang-target-variant' form the
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import A;
          """
        )
        var driver = try TestDriver(args: ["swiftc",
                                       "-target", "x86_64-apple-macosx10.10",
                                       "-target-variant", "x86_64-apple-ios13.0-macabi",
                                       "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                       "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                       "-emit-module",
                                       "-emit-module-path", "foo.swiftmodule/target.swiftmodule",
                                       "-I", cHeadersPath.nativePathString(escaped: false),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                       "-I", stdlibPath.nativePathString(escaped: false),
                                       "-I", shimsPath.nativePathString(escaped: false),
                                       "-explicit-module-build",
                                       "-sdk", mockSDKPath.nativePathString(escaped: false),
                                       main.pathString])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try #require(plannedJobs.findJobs(.emitModule).spm_only)
        expectCommandLineContains(emitModuleJob.commandLine, .flag("-sdk"))
        #expect(emitModuleJob.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("x86_64-apple-macosx10.15")]))
        #expect(emitModuleJob.commandLine.contains(subsequence: [.flag("-clang-target-variant"), .flag("x86_64-apple-ios13.1-macabi")]))
      }
    }

    // User-specified '-clang-target' and '-clang-target-variant'
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import A;
          """
        )
        var driver = try TestDriver(args: ["swiftc",
                                       "-target", "x86_64-apple-macosx10.10",
                                       "-target-variant", "x86_64-apple-ios13.0-macabi",
                                       "-clang-target", "x86_64-apple-macosx10.12",
                                       "-clang-target-variant", "x86_64-apple-ios14.0-macabi",
                                       "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                       "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                       "-emit-module",
                                       "-emit-module-path", "foo.swiftmodule/target.swiftmodule",
                                       "-I", cHeadersPath.nativePathString(escaped: false),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                       "-I", stdlibPath.nativePathString(escaped: false),
                                       "-I", shimsPath.nativePathString(escaped: false),
                                       "-explicit-module-build",
                                       "-sdk", mockSDKPath.nativePathString(escaped: false),
                                       main.pathString])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try #require(plannedJobs.findJobs(.emitModule).spm_only)
        expectCommandLineContains(emitModuleJob.commandLine, .flag("-sdk"))
        #expect(emitModuleJob.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("x86_64-apple-macosx10.12")]))
        #expect(emitModuleJob.commandLine.contains(subsequence: [.flag("-clang-target-variant"), .flag("x86_64-apple-ios14.0-macabi")]))
      }
    }
  }

  @Test func targetVariantEmitModuleExplicit() async throws {
    let (stdlibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()
    let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "CHeaders")
    let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
        .appending(component: "Swift")
    let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

    // Ensure we produce two separate module precompilation task graphs
    // one for the main triple, one for the variant triple
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import C;\
          import E;\
          import G;
          """
        )
        var driver = try TestDriver(args: ["swiftc",
                                       "-swift-version", "5",
                                       "-experimental-emit-variant-module",
                                       "-target", "x86_64-apple-macosx10.14",
                                       "-target-variant", "x86_64-apple-ios13.1-macabi",
                                       "-clang-target", "x86_64-apple-macosx12.14",
                                       "-clang-target-variant", "x86_64-apple-ios15.1-macabi",
                                       "-enable-library-evolution", "-emit-module", "-emit-module-interface",
                                       "-emit-module-path", "foo.swiftmodule/target.swiftmodule",
                                       "-emit-variant-module-path", "foo.swiftmodule/variant.swiftmodule",
                                       "-emit-module-interface-path", "foo.swiftmodule/target.swiftinterface",
                                       "-emit-variant-module-interface-path", "foo.swiftmodule/variant.swiftinterface",
                                       "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                       "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                       "-I", cHeadersPath.nativePathString(escaped: false),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                       "-I", stdlibPath.nativePathString(escaped: false),
                                       "-I", shimsPath.nativePathString(escaped: false),
                                       "-explicit-module-build",
                                       main.pathString] + sdkArgumentsForTesting)

        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJobs = try plannedJobs.findJobs(.emitModule)
        let targetModuleJob = emitModuleJobs[0]
        let variantModuleJob = emitModuleJobs[1]

        #expect(targetModuleJob.commandLine.contains(.flag("-emit-module")))
        #expect(variantModuleJob.commandLine.contains(.flag("-emit-module")))

        #expect(targetModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/target.swiftdoc")))))
        #expect(targetModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/target.swiftsourceinfo")))))
        #expect(targetModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/target.abi.json")))))
        #expect(targetModuleJob.commandLine.contains(subsequence: [.flag("-o"), .path(.relative(try .init(validating: "foo.swiftmodule/target.swiftmodule")))]))

        #expect(variantModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/variant.swiftdoc")))))
        #expect(variantModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/variant.swiftsourceinfo")))))
        #expect(variantModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/variant.abi.json")))))
        #expect(variantModuleJob.commandLine.contains(subsequence: [.flag("-o"), .path(.relative(try .init(validating: "foo.swiftmodule/variant.swiftmodule")))]))

        let verifyModuleJobs = try plannedJobs.findJobs(.verifyModuleInterface)
        let verifyTargetModuleJob = verifyModuleJobs[0]
        let verifyVariantModuleJob = verifyModuleJobs[1]
        #expect(verifyTargetModuleJob.commandLine.contains(.flag("-typecheck-module-from-interface")))
        #expect(verifyVariantModuleJob.commandLine.contains(.flag("-typecheck-module-from-interface")))

        #expect(verifyTargetModuleJob.commandLine.contains(.flag("-target")))
        #expect(verifyTargetModuleJob.commandLine.contains(.flag("x86_64-apple-macosx10.14")))
        #expect(verifyTargetModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/target.swiftinterface")))))

        #expect(verifyVariantModuleJob.commandLine.contains(.flag("-target")))
        #expect(verifyVariantModuleJob.commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
        #expect(verifyVariantModuleJob.commandLine.contains(.path(.relative(try .init(validating: "foo.swiftmodule/variant.swiftinterface")))))

        let interfaceCompilationJobs = try plannedJobs.findJobs(.compileModuleFromInterface)
        let _ = try #require(interfaceCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("A")]) &&
                                                               $0.commandLine.contains(subsequence: [.flag("-target"), .flag("x86_64-apple-macosx10.14")])})
        let _ = try #require(interfaceCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("A")]) &&
                                                               $0.commandLine.contains(subsequence: [.flag("-target"), .flag("x86_64-apple-ios13.1-macabi")])})

        let _ = try #require(interfaceCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("G")]) &&
                                                               $0.commandLine.contains(subsequence: [.flag("-target"), .flag("x86_64-apple-macosx10.14")])})
        let _ = try #require(interfaceCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("G")]) &&
                                                               $0.commandLine.contains(subsequence: [.flag("-target"), .flag("x86_64-apple-ios13.1-macabi")])})

        let _ = try #require(interfaceCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("E")]) &&
                                                               $0.commandLine.contains(subsequence: [.flag("-target"), .flag("x86_64-apple-macosx10.14")])})
        let _ = try #require(interfaceCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("E")]) &&
                                                               $0.commandLine.contains(subsequence: [.flag("-target"), .flag("x86_64-apple-ios13.1-macabi")])})

        let pcmCompilationJobs = try plannedJobs.findJobs(.generatePCM)
        let _ = try #require(pcmCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("A")]) &&
                                                         $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-triple"), .flag("-Xcc"), .flag("x86_64-apple-macosx12.14.0")]) &&
                                                         !$0.commandLine.contains(.flag("-darwin-target-variant-triple"))})
        let _ = try #require(pcmCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("A")]) &&
                                                         $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-darwin-target-variant-triple"), .flag("-Xcc"), .flag("x86_64-apple-ios15.1-macabi")])})

        let _ = try #require(pcmCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("C")]) &&
                                                         $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-triple"), .flag("-Xcc"), .flag("x86_64-apple-macosx12.14.0")]) &&
                                                         !$0.commandLine.contains(.flag("-darwin-target-variant-triple"))})
        let _ = try #require(pcmCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("C")]) &&
                                                         $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-darwin-target-variant-triple"), .flag("-Xcc"), .flag("x86_64-apple-ios15.1-macabi")])})

        let _ = try #require(pcmCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("G")]) &&
                                                         $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-triple"), .flag("-Xcc"), .flag("x86_64-apple-macosx12.14.0")]) &&
                                                         !$0.commandLine.contains(.flag("-darwin-target-variant-triple"))})
        let _ = try #require(pcmCompilationJobs.first { $0.commandLine.contains(subsequence: [.flag("-module-name"), .flag("G")]) &&
                                                         $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-darwin-target-variant-triple"), .flag("-Xcc"), .flag("x86_64-apple-ios15.1-macabi")])})
      }
    }

    // Ensure each emit-module gets a distinct PCH file
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import C;\
          import E;\
          import G;
          """
        )
        let PCHPath = path.appending(component: "PCH")
        let fooHeader = path.appending(component: "foo.h")
        try localFileSystem.writeFileContents(fooHeader) {
          $0.send("struct Profiler { void* ptr; };")
        }
        var driver = try TestDriver(args: ["swiftc",
                                       "-experimental-emit-variant-module",
                                       "-target", "x86_64-apple-macosx10.14",
                                       "-target-variant", "x86_64-apple-ios13.1-macabi",
                                       "-clang-target", "x86_64-apple-macosx12.14",
                                       "-clang-target-variant", "x86_64-apple-ios15.1-macabi",
                                       "-emit-module",
                                       "-emit-module-path", "foo.swiftmodule/target.swiftmodule",
                                       "-emit-variant-module-path", "foo.swiftmodule/variant.swiftmodule",
                                       "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                       "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                       "-I", cHeadersPath.nativePathString(escaped: false),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                       "-I", stdlibPath.nativePathString(escaped: false),
                                       "-I", shimsPath.nativePathString(escaped: false),
                                       "-import-objc-header", fooHeader.nativePathString(escaped: false),
                                       "-pch-output-dir", PCHPath.nativePathString(escaped: false),
                                       "-explicit-module-build",
                                       main.pathString] + sdkArgumentsForTesting)

        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJobs = try plannedJobs.findJobs(.emitModule)
        let targetModuleJob = emitModuleJobs[0]
        let variantModuleJob = emitModuleJobs[1]

        let pchJobs = try plannedJobs.findJobs(.generatePCH)
        let pchTargetJob = try #require(pchJobs.first { $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-triple"), .flag("-Xcc"), .flag("x86_64-apple-macosx12.14.0")]) &&
                                                         $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-darwin-target-variant-triple"), .flag("-Xcc"),.flag("x86_64-apple-ios15.1-macabi")])})
        let pchVariantJob = try #require(pchJobs.first { $0.commandLine.contains(subsequence: [.flag("-Xcc"), .flag("-triple"), .flag("-Xcc"), .flag("x86_64-apple-macosx12.14.0")]) &&
                                                          !$0.commandLine.contains(.flag("-darwin-target-variant-triple"))})
        #expect(targetModuleJob.inputs.contains(try #require(pchTargetJob.outputs.first)))
        #expect(variantModuleJob.inputs.contains(try #require(pchVariantJob.outputs.first)))
      }
    }
  }

// We only care about prebuilt modules in macOS.
#if os(macOS)
  @Test func prebuiltModuleGenerationJobs() throws {
    func getInputModules(_ job: Job) -> [String] {
      return job.inputs.filter {$0.type == .swiftModule}.map { input in
        return input.file.absolutePath!.parentDirectory.basenameWithoutExt
      }.sorted()
    }

    func getOutputName(_ job: Job) -> String {
      #expect(job.outputs.count == 1)
      return job.outputs[0].file.basename
    }

    func checkInputOutputIntegrity(_ job: Job) {
      let name = job.outputs[0].file.basenameWithoutExt
      #expect(job.outputs[0].file.extension == "swiftmodule")
      job.inputs.forEach { input in
        // Inputs include all the dependencies and the interface from where
        // the current module can be built.
        #expect(input.file.extension == "swiftmodule" ||
                      input.file.extension == "swiftinterface")
        let inputName = input.file.basenameWithoutExt
        // arm64 interface can depend on ar64e interface
        if inputName.starts(with: "arm64e-") && name.starts(with: "arm64-") {
          return
        }
        #expect(inputName == name)
      }
    }

    func findJob(_ jobs: [Job],_ module: String, _ basenameWithoutExt: String) -> Job? {
      return jobs.first { job in
        return job.moduleName == module &&
          job.outputs[0].file.basenameWithoutExt == basenameWithoutExt
      }
    }

    let mockSDKPath: String =
        try testInputsPath.appending(component: "mock-sdk.sdk").pathString
    let diagnosticEnging = DiagnosticsEngine()
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPath).absolutePath!, diagnosticEnging)
    let interfaceMap = try collector.collectSwiftInterfaceMap().inputMap

    let extraArgs = try {
        let driver = try TestDriver(args: ["swiftc"])
        if driver.isFrontendArgSupported(.moduleLoadMode) {
          return ["-Xfrontend", "-module-load-mode", "-Xfrontend", "prefer-interface"]
        }
        return []
    }()

    // Check interface map always contain everything
    #expect(interfaceMap["Swift"]?.count == 3)
    #expect(interfaceMap["A"]?.count == 3)
    #expect(interfaceMap["E"]?.count == 3)
    #expect(interfaceMap["F"]?.count == 3)
    #expect(interfaceMap["G"]?.count == 3)
    #expect(interfaceMap["H"]?.count == 3)

    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import A
        import E
        import F
        import G
        import H
        import Swift

        """
      )
      let moduleCachePath = "/tmp/module-cache"
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                     "-module-cache-path", moduleCachePath,
                                    ] + extraArgs)
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                 into: path,
                                                                                 exhaustive: true)

      #expect(danglingJobs.count == 2)
      #expect(danglingJobs.allSatisfy { job in
        job.moduleName == "MissingKit"
      })
      #expect(jobs.count == 18)
      #expect(jobs.allSatisfy {$0.outputs.count == 1})
      #expect(jobs.allSatisfy {$0.kind == .compile})
      #expect(jobs.allSatisfy {$0.commandLine.contains(.flag("-compile-module-from-interface"))})
      #expect(jobs.allSatisfy {$0.commandLine.contains(.flag("-module-cache-path"))})
      #expect(jobs.allSatisfy {$0.commandLine.contains(.flag("-bad-file-descriptor-retry-count"))})
      #expect(try jobs.allSatisfy {$0.commandLine.contains(.path(try VirtualPath(path: moduleCachePath)))})
      let HJobs = jobs.filter { $0.moduleName == "H"}
      #expect(HJobs.count == 3)
      // arm64
      #expect(getInputModules(HJobs[0]) == ["A", "A", "E", "E", "F", "F", "G", "G", "Swift", "Swift"])
      // arm64e
      #expect(getInputModules(HJobs[1]) == ["A", "E", "F", "G", "Swift"])
      // x86_64
      #expect(getInputModules(HJobs[2]) == ["A", "E", "F", "G", "Swift"])
      #expect(getOutputName(HJobs[0]) != getOutputName(HJobs[1]))
      #expect(getOutputName(HJobs[1]) != getOutputName(HJobs[2]))
      checkInputOutputIntegrity(HJobs[0])
      checkInputOutputIntegrity(HJobs[1])
      checkInputOutputIntegrity(HJobs[2])
      let GJobs = jobs.filter { $0.moduleName == "G"}
      #expect(GJobs.count == 3)
      #expect(getInputModules(GJobs[0]) == ["E", "E", "Swift", "Swift"])
      #expect(getInputModules(GJobs[1]) == ["E", "Swift"])
      #expect(getInputModules(GJobs[2]) == ["E", "Swift"])
      #expect(getOutputName(GJobs[0]) != getOutputName(GJobs[1]))
      #expect(getOutputName(GJobs[1]) != getOutputName(GJobs[2]))
      checkInputOutputIntegrity(GJobs[0])
      checkInputOutputIntegrity(GJobs[1])
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import H\n")
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ] + extraArgs)
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                 into: path,
                                                                                 exhaustive: false)

      #expect(danglingJobs.isEmpty)
      #expect(jobs.count == 18)
      #expect(jobs.allSatisfy {$0.outputs.count == 1})
      #expect(jobs.allSatisfy {$0.kind == .compile})
      #expect(jobs.allSatisfy {$0.commandLine.contains(.flag("-compile-module-from-interface"))})

      let HJobs = jobs.filter { $0.moduleName == "H"}
      #expect(HJobs.count == 3)
      // arm64
      #expect(getInputModules(HJobs[0]) == ["A", "A", "E", "E", "F", "F", "G", "G", "Swift", "Swift"])
      // arm64e
      #expect(getInputModules(HJobs[1]) == ["A", "E", "F", "G", "Swift"])
      // x86_64
      #expect(getInputModules(HJobs[2]) == ["A", "E", "F", "G", "Swift"])
      #expect(getOutputName(HJobs[0]) != getOutputName(HJobs[1]))
      checkInputOutputIntegrity(HJobs[0])
      checkInputOutputIntegrity(HJobs[1])

      let GJobs = jobs.filter { $0.moduleName == "G"}
      #expect(GJobs.count == 3)
      #expect(getInputModules(GJobs[0]) == ["E", "E", "Swift", "Swift"])
      #expect(getInputModules(GJobs[1]) == ["E", "Swift"])
      #expect(getInputModules(GJobs[2]) == ["E", "Swift"])
      #expect(getOutputName(GJobs[0]) != getOutputName(GJobs[1]))
      #expect(getOutputName(GJobs[1]) != getOutputName(GJobs[2]))
      checkInputOutputIntegrity(GJobs[0])
      checkInputOutputIntegrity(GJobs[1])
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import Swift\n")
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ] + extraArgs)
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                 into: path,
                                                                                 exhaustive: false)

      #expect(danglingJobs.isEmpty)
      #expect(jobs.count == 3)
      #expect(jobs.allSatisfy { $0.moduleName == "Swift" })
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import F\n")
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ] + extraArgs)
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                 into: path,
                                                                                 exhaustive: false)

      #expect(danglingJobs.isEmpty)
      #expect(jobs.count == 9)
      jobs.forEach({ job in
        // Check we don't pull in other modules than A, F and Swift
        #expect(["A", "F", "Swift"].contains(job.moduleName))
        checkInputOutputIntegrity(job)
      })
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import H\n")
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ] + extraArgs)
      let (jobs, _) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                      into: path,
                                                                      exhaustive: false)
      let F = findJob(jobs, "F", "arm64-apple-macos")!
      let H = findJob(jobs, "H", "arm64e-apple-macos")!
      // Test arm64 interface requires arm64e interfaces as inputs
      #expect(F.inputs.contains { input in
        input.file.basenameWithoutExt == "arm64e-apple-macos"
      })
      // Test arm64e interface doesn't require arm64 interfaces as inputs
      #expect(!H.inputs.contains { input in
        input.file.basenameWithoutExt == "arm64-apple-macos"
      })
    }
  }

  @Test func ignoreScannerPrefixMapping() async throws {
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "testScannerPrefixMap.swift")
      let mockSDKPath: AbsolutePath =
        try testInputsPath.appending(component: "mock-sdk.sdk")
      try localFileSystem.writeFileContents(main, bytes: "import Swift\n")
      var driver = try TestDriver(args: ["swiftc", main.pathString, "-c",
                                     "-sdk", mockSDKPath.nativePathString(escaped: false),
                                     "-g", "-explicit-module-build", "-O",
                                     "-scanner-prefix-map-sdk", "/^sdk",
                                     "-scanner-prefix-map-toolchain", "/^toolchain",
                                    ])
      let _ = try await driver.planBuild()
      #expect(driver.diagnosticEngine.diagnostics.contains {
        $0.behavior == .warning && $0.message.text == "ignore '-scanner-prefix-*' options that cannot be used without compilation caching"
      })
    }
  }

  @Test func aBICheckWhileBuildingPrebuiltModule() throws {
    func checkABICheckingJob(_ job: Job) throws {
      #expect(job.kind == .compareABIBaseline)
      #expect(job.inputs.count == 2)
      let (baseline, current) = (job.inputs[0], job.inputs[1])
      #expect(baseline.type == .jsonABIBaseline)
      #expect(current.type == .jsonABIBaseline)
      #expect(current.file != baseline.file)
      #expect(current.file.basename == baseline.file.basename)
    }
    let mockSDKPath: String =
        try testInputsPath.appending(component: "mock-sdk.sdk").pathString
    let baselineABIPath: String =
        try testInputsPath.appending(component: "ABIBaselines").pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPath).absolutePath!, DiagnosticsEngine())
    let interfaceMap = try collector.collectSwiftInterfaceMap().inputMap
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import A\n")
      let moduleCachePath = "/tmp/module-cache"
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                     "-module-cache-path", moduleCachePath
                                    ])
      let (jobs, _) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                      into: path,
                                                                      exhaustive: true,
                                                                      currentABIDir: path.appending(component: "ABI"),
                                                                      baselineABIDir: VirtualPath(path: baselineABIPath).absolutePath)
      let compileJobs = jobs.filter {$0.kind == .compile}
      let abiCheckJobs = jobs.filter {$0.kind == .compareABIBaseline}
      #expect(!compileJobs.isEmpty)
      #expect(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-compile-module-from-interface")) })
      #expect(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-emit-abi-descriptor-path")) })
      try abiCheckJobs.forEach { try checkABICheckingJob($0) }
    }
  }
  @Test func prebuiltModuleInternalSDK() throws {
    let mockSDKPath = try testInputsPath.appending(component: "mock-sdk.Internal.sdk")
    let mockSDKPathStr: String = mockSDKPath.pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPathStr).absolutePath!, DiagnosticsEngine())
    let interfaceMap = try collector.collectSwiftInterfaceMap().inputMap
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import A\n")
      let moduleCachePath = "/tmp/module-cache"
      var driver = try TestDriver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPathStr,
                                     "-module-cache-path", moduleCachePath
                                    ])
      let (jobs, _) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                      into: path,
                                                                      exhaustive: true)
      let compileJobs = jobs.filter {$0.kind == .compile}
      #expect(!compileJobs.isEmpty)
      #expect(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-suppress-warnings")) })
      let PFPath = mockSDKPath.appending(component: "System").appending(component: "Library")
        .appending(component: "PrivateFrameworks")
      #expect(compileJobs.allSatisfy { $0.commandLine.contains(.path(VirtualPath.absolute(PFPath))) })
    }
  }
  @Test func collectSwiftAdopters() throws {
    let mockSDKPath = try testInputsPath.appending(component: "mock-sdk.Internal.sdk")
    let mockSDKPathStr: String = mockSDKPath.pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPathStr).absolutePath!, DiagnosticsEngine())
    let adopters = try collector.collectSwiftInterfaceMap().adopters
    #expect(!adopters.isEmpty)
    let A = adopters.first {$0.name == "A"}!
    #expect(!A.isFramework)
    #expect(!A.isPrivate)
    #expect(!A.hasModule)
    #expect(!A.hasPrivateInterface)
    #expect(!A.hasPackageInterface)
    #expect(A.hasInterface)

    let B = adopters.first {$0.name == "B"}!
    #expect(B.isFramework)
    #expect(!B.isPrivate)
    #expect(!B.hasModule)
    #expect(B.hasPrivateInterface)
    #expect(!B.hasPackageInterface)
  }

  @Test func collectSwiftAdoptersWhetherMixed() throws {
    let mockSDKPath = try testInputsPath.appending(component: "mock-sdk.Internal.sdk")
    let mockSDKPathStr: String = mockSDKPath.pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPathStr).absolutePath!, DiagnosticsEngine())
    let adopters = try collector.collectSwiftInterfaceMap().adopters
    #expect(!adopters.isEmpty)
    let B = adopters.first {$0.name == "B"}!
    #expect(B.isFramework)
    #expect(B.hasCompatibilityHeader)
    #expect(!B.isMixed)

    let C = adopters.first {$0.name == "C"}!
    #expect(C.isFramework)
    #expect(!C.hasCompatibilityHeader)
    #expect(C.isMixed)
  }
#endif
}
