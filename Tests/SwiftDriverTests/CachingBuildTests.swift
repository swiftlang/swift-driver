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

private var testInputsPath: AbsolutePath = {
  var root: AbsolutePath = try! AbsolutePath(validating: #file)
  while root.basename != "Tests" {
    root = root.parentDirectory
  }
  return root.parentDirectory.appending(component: "TestInputs")
}()

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
        XCTAssertTrue(job.commandLine.filter {$0 == .flag("-candidate-module-file")}.count == compiledCandidateList.count)
      }
      // make sure command-line from dep-scanner are included.
      let extraCommandLine = try XCTUnwrap(swiftModuleDetails.commandLine)
      for command in extraCommandLine {
        XCTAssertTrue(job.commandLine.contains(.flag(command)))
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
  XCTAssertTrue(job.commandLine.contains(.flag(String("-fno-implicit-modules"))))
  try checkCachingBuildJobDependencies(job: job,
                                       moduleInfo: moduleInfo,
                                       dependencyGraph: dependencyGraph)
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
    let clangDependencyModuleMapPath =
      TypedVirtualPath(file: clangDependencyDetails.moduleMapPath.path,
                       type: .clangModuleMap)
    XCTAssertTrue(job.inputs.contains(clangDependencyModulePath))
    XCTAssertTrue(job.inputs.contains(clangDependencyModuleMapPath))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-fmodule-file=\(dependencyId.moduleName)=\(clangDependencyModulePathString)"))))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-fmodule-map-file=\(clangDependencyDetails.moduleMapPath.path.description)"))))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-fmodule-file-cache-key"))))
    let cacheKey = try XCTUnwrap(clangDependencyDetails.moduleCacheKey)
    XCTAssertTrue(job.commandLine.contains(.flag(String(cacheKey))))
  }

  for dependencyId in moduleInfo.directDependencies! {
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
    for transitiveDependencyId in dependencyInfo.directDependencies! {
      try checkCachingBuildJobDependencies(job: job,
                                           moduleInfo: try dependencyGraph.moduleInfo(of: transitiveDependencyId),
                                           dependencyGraph: dependencyGraph)

    }
  }
}


final class CachingBuildTests: XCTestCase {
  private func pathMatchesSwiftModule(path: VirtualPath, _ name: String) -> Bool {
    return path.basenameWithoutExt.starts(with: "\(name)-") &&
           path.extension! == FileType.swiftModule.rawValue
  }

  func testCachingBuildJobs() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testCachingBuildJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import C;"
        $0 <<< "import E;"
        $0 <<< "import G;"
      }
      let casPath = path.appending(component: "cas")
      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-v",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try XCTUnwrap(driver.toolchain.lookupSwiftScanLib())
      guard try dependencyOracle
              .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                             swiftScanLibPath: scanLibPath) else {
        XCTFail("Dependency scanner library not found")
        return
      }
      guard try dependencyOracle.supportsCaching() else {
        throw XCTSkip("libSwiftScan does not support caching.")
      }

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
            case .relative(RelativePath("testCachingBuildJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testCachingBuildJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink") ||
                            matchTemporary(outputFilePath, basename: "Bridging-", fileExtension: "pch"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build, -verify-emitted-module-interface and -enable-library-evolution.
  func testExplicitModuleVerifyInterfaceJobs() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import C;"
        $0 <<< "import E;"
        $0 <<< "import G;"
      }

      let swiftModuleInterfacesPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let cHeadersPath: AbsolutePath =
          testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let casPath = path.appending(component: "cas")
      let swiftInterfacePath: AbsolutePath = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.swiftinterface")
      let privateSwiftInterfacePath: AbsolutePath = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.private.swiftinterface")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: true),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-verify-emitted-module-interface",
                                     "-enable-library-evolution",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      guard driver.supportExplicitModuleVerifyInterface() else {
        throw XCTSkip("-typecheck-module-from-interface doesn't support explicit build.")
      }
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try XCTUnwrap(driver.toolchain.lookupSwiftScanLib())
      guard try dependencyOracle
              .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                             swiftScanLibPath: scanLibPath) else {
        XCTFail("Dependency scanner library not found")
        return
      }
      guard try dependencyOracle.supportsCaching() else {
        throw XCTSkip("libSwiftScan does not support caching.")
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
          XCTAssertTrue(job.kind == .verifyModuleInterface)
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
            case .relative(RelativePath("testExplicitModuleVerifyInterfaceJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
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
                                     "-explicit-module-build", "-v", "-Rcache-compile-job",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try XCTUnwrap(driver.toolchain.lookupSwiftScanLib())
      guard try dependencyOracle
              .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                             swiftScanLibPath: scanLibPath) else {
        XCTFail("Dependency scanner library not found")
        return
      }
      guard try dependencyOracle.supportsCaching() else {
        throw XCTSkip("libSwiftScan does not support caching.")
      }
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
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
        $0 <<< "extension Profiler {"
        $0 <<< "    public static let count: Int = 42"
        $0 <<< "}"
      }
      let fooHeader = path.appending(component: "foo.h")
      try localFileSystem.writeFileContents(fooHeader) {
        $0 <<< "struct Profiler { void* ptr; };"
      }
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import Foo"
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
                                      env: ProcessEnv.vars)

      // Ensure this tooling supports this functionality
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try XCTUnwrap(fooBuildDriver.toolchain.lookupSwiftScanLib())
      guard try dependencyOracle
              .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                             swiftScanLibPath: scanLibPath) else {
        XCTFail("Dependency scanner library not found")
        return
      }
      guard try dependencyOracle.supportsBinaryModuleHeaderDependencies() else {
        throw XCTSkip("libSwiftScan does not support binary module header dependencies.")
      }
      guard try dependencyOracle.supportsCaching() else {
        throw XCTSkip("libSwiftScan does not support caching.")
      }

      let fooJobs = try fooBuildDriver.planBuild()
      try fooBuildDriver.run(jobs: fooJobs)
      XCTAssertFalse(fooBuildDriver.diagnosticEngine.hasErrors)

      var driver = try Driver(args: ["swiftc",
                                     "-I", FooInstallPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-emit-module", "-emit-module-path",
                                     path.appending(component: "testEMBETEWBHD.swiftmodule").nativePathString(escaped: true),
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      // This is currently not supported.
      XCTAssertThrowsError(try driver.planBuild()) {
        XCTAssertEqual($0 as? Driver.Error, .unsupportedConfigurationForCaching("module Foo has prebuilt header dependency"))
      }
    }
  }

  func testDependencyScanning() throws {
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
      let casPath = path.appending(component: "cas")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "/tmp/Foo.o",
                                     "-explicit-module-build",
                                     "-cache-compile-job", "-cas-path", casPath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try XCTUnwrap(driver.toolchain.lookupSwiftScanLib())
      guard try dependencyOracle
              .verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                             swiftScanLibPath: scanLibPath) else {
        XCTFail("Dependency scanner library not found")
        return
      }
      guard try dependencyOracle.supportsCaching() else {
        throw XCTSkip("libSwiftScan does not support caching.")
      }
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

      // Here purely to dump diagnostic output in a reasonable fashion when things go wrong.
      let lock = NSLock()

      // Module `X` is only imported on Darwin when:
      // #if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 110000
      let expectedNumberOfDependencies: Int
      if driver.hostTriple.isMacOSX,
         driver.hostTriple.version(for: .macOS) >= Triple.Version(11, 0, 0) {
        expectedNumberOfDependencies = 11
      } else if driver.targetTriple.isWindows {
        expectedNumberOfDependencies = 14
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
        let dependencyGraph =
          try! dependencyOracle.getDependencies(workingDirectory: path,
                                                commandLine: iterationCommand)

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
      XCTAssertThrowsError(try dependencyOracle.getDependencies(workingDirectory: path,
                                                                commandLine: command)) {
        XCTAssertTrue($0 is DependencyScanningError)
      }
      let diags = try XCTUnwrap(dependencyOracle.getScannerDiagnostics())
      XCTAssertEqual(diags.count, 1)
      XCTAssertEqual(diags[0].severity, .error)
      XCTAssertEqual(diags[0].message, "CAS error encountered: conflicting CAS options used in scanning service")
    }
  }
}
