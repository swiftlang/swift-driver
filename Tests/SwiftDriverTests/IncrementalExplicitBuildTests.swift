//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(Testing) import SwiftDriver
import SwiftOptions
import TSCBasic
import TestUtilities
import Testing

@Suite(.enabled(if: sdkArgumentsAvailable, "SDK not available"))
struct IncrementalExplicitBuildTests: DiagVerifiable {

  // MARK: - Simple builds

  // Simple re-use of a prior inter-module dependency graph on a null build
  @Test(arguments: TestBuildConfig.availableExplicitConfigs)
  func explicitIncrementalSimpleBuildCheckDiagnostics(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    try await h.buildInitialState(checkDiagnostics: false)
    try await h.checkNullBuild(checkDiagnostics: true)
  }

  // MARK: - Reaction to change (parameterized over all explicit configs)

  // Source files have changed but the inter-module dependency graph still up-to-date
  @Test(arguments: TestBuildConfig.availableExplicitConfigs)
  func reactionToChange(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    try await h.buildInitialState(checkDiagnostics: false)
    try await h.checkReactionToTouchingAll(checkDiagnostics: true)
  }

  @Test(arguments: TestBuildConfig.cachingConfigs)
  func incrementalCompilationCachingBasic(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    try await h.buildInitialState(checkDiagnostics: false)
    try h.touch("other")
    try await h.doABuild(
      "touch other only",
      checkDiagnostics: true,
      extraArguments: h.explicitBuildArgs + h.configCachingArgs,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      maySkip("main")
      schedulingChangedInitialQueuing("other")
      skipping("main")
      findingBatchingCompiling("other")
      reading(deps: "other")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedulingPostCompileJobs
      linking
      skipped("main")
    }
  }

  // MARK: - Changed dependency invalidates upstream (parameterized)

  // A dependency has changed one of its inputs, ensure
  // other modules that depend on it are invalidated also.
  //
  //             test
  //             /   \
  //             Y   T
  //            / \ / \
  //           H   R   J
  //            \       \
  //             \-------G
  //
  // On this graph, inputs of 'G' are updated, causing it to be re-built
  // as well as all modules on paths from root to it: 'Y', 'H', 'T','J'
  @Test(arguments: TestBuildConfig.explicitOnlyConfigs)
  func changedDependencyInvalidatesUpstream(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    h.replace(contentsOf: "other", with: "import Y;import T")
    try await h.buildInitialState(checkDiagnostics: false)

    let GInterfacePath = h.explicitSwiftDependenciesPath.appending(component: "G.swiftinterface")
    h.touch(GInterfacePath)
    h.touch(GInterfacePath) // touch twice to make sure it is newer than build output.

    try await h.doABuild(
      "update dependency (G) interface timestamp",
      checkDiagnostics: true,
      extraArguments: h.configBuildArgs,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanDependencyNewInput("G", GInterfacePath.pathString)
      explicitIncrementalScanDependencyInvalidated("J")
      explicitIncrementalScanDependencyInvalidated("T")
      explicitIncrementalScanDependencyInvalidated("H")
      explicitIncrementalScanDependencyInvalidated("Y")
      explicitIncrementalScanDependencyInvalidated("theModule")
      noFingerprintInSwiftModule("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface")
      reading(deps: "main")
      reading(deps: "other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      maySkip("main")
      maySkip("other")
      invalidatedExternally("main", "other")
      queuingInitial("main", "other")
      findingBatchingCompiling("main", "other")
      explicitDependencyModuleOlderThanInput("G")
      moduleWillBeRebuiltInvalidatedDownstream("J")
      moduleWillBeRebuiltInvalidatedDownstream("T")
      moduleWillBeRebuiltInvalidatedDownstream("Y")
      moduleWillBeRebuiltInvalidatedDownstream("H")
      explicitModulesWillBeRebuilt(["G", "H", "J", "T", "Y"])
      moduleWillBeRebuiltOutOfDate("G")
      compilingExplicitSwiftDependency("G")
      compilingExplicitSwiftDependency("J")
      compilingExplicitSwiftDependency("T")
      compilingExplicitSwiftDependency("Y")
      compilingExplicitSwiftDependency("H")
      schedulingPostCompileJobs
      linking
    }
  }

  // MARK: - File hashing tests

  // Source file and external deps timestamps updated but contents are the same,
  // and file-hashing is enabled.
  @Test(arguments: TestBuildConfig.explicitOnlyConfigs)
  func explicitIncrementalBuildWithHashing(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    h.replace(contentsOf: "other", with: "import E;let bar = foo")
    try await h.buildInitialState(extraArguments: ["-enable-incremental-file-hashing"])
    try h.touch("main")
    try h.touch("other")
    h.touch(
      try AbsolutePath(validating: h.explicitSwiftDependenciesPath.appending(component: "E.swiftinterface").pathString)
    )
    let driver = try await h.checkNullBuild(extraArguments: ["-enable-incremental-file-hashing"])
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    let mandatoryJobInputs = mandatoryJobs.flatMap { $0.inputs }.map { $0.file.basename }
    #expect(!mandatoryJobInputs.contains("main.swift"))
    #expect(!mandatoryJobInputs.contains("other.swift"))
  }

  // External deps timestamp updated but contents are the same, and
  // file-hashing is explicitly disabled.
  @Test(arguments: TestBuildConfig.availableExplicitConfigs)
  func explicitIncrementalBuildExternalDepsWithoutHashing(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    h.replace(contentsOf: "other", with: "import E;let bar = foo")
    try await h.buildInitialState(extraArguments: ["-disable-incremental-file-hashing"])
    h.touch(
      try AbsolutePath(validating: h.explicitSwiftDependenciesPath.appending(component: "E.swiftinterface").pathString)
    )
    let driver = try await h.checkNullBuild(extraArguments: ["-disable-incremental-file-hashing"])
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    let mandatoryJobInputs = mandatoryJobs.flatMap { $0.inputs }.map { $0.file.basename }
    #expect(mandatoryJobInputs.contains("other.swift"))
    #expect(mandatoryJobInputs.contains("main.swift"))
  }

  // Source file timestamps updated but contents are the same, and
  // file-hashing is explicitly disabled.
  @Test(arguments: TestBuildConfig.availableExplicitConfigs)
  func explicitIncrementalBuildSourceFilesWithoutHashing(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    try await h.buildInitialState(extraArguments: ["-disable-incremental-file-hashing"])
    try h.touch("main")
    try h.touch("other")
    let driver = try await h.checkNullBuild(extraArguments: ["-disable-incremental-file-hashing"])
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    let mandatoryJobInputs = mandatoryJobs.flatMap { $0.inputs }.map { $0.file.basename }
    #expect(mandatoryJobInputs.contains("other.swift"))
    #expect(mandatoryJobInputs.contains("main.swift"))
  }

  // MARK: - Import and dependency change tests

  // Adding an import invalidates prior inter-module dependency graph.
  @Test(arguments: TestBuildConfig.explicitOnlyConfigs)
  func explicitIncrementalBuildNewImport(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    try await h.buildInitialState(checkDiagnostics: false)
    // Introduce a new import. This will cause a re-scan and a re-build of 'other.swift'.
    h.replace(contentsOf: "other", with: "import E;let bar = foo")
    try await h.doABuild(
      "add import to 'other'",
      checkDiagnostics: true,
      extraArguments: h.explicitBuildArgs,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      maySkip("main")
      schedulingChangedInitialQueuing("other")
      skipping("main")
      findingBatchingCompiling("other")
      reading(deps: "other")
      fingerprintsChanged("other")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      moduleOutputNotFound("E")
      moduleWillBeRebuiltOutOfDate("E")
      explicitModulesWillBeRebuilt(["E"])
      compilingExplicitSwiftDependency("E")
      skipped("main")
      schedLinking
    }
  }

  // A dependency has changed one of its inputs.
  @Test(arguments: TestBuildConfig.explicitOnlyConfigs)
  func explicitIncrementalBuildChangedDependency(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    // Add an import of 'E' to make sure followup changes has consistent inputs.
    h.replace(contentsOf: "other", with: "import E;let bar = foo")
    try await h.buildInitialState(checkDiagnostics: false)

    let EInterfacePath = h.explicitSwiftDependenciesPath.appending(component: "E.swiftinterface")
    // Just update the time-stamp of one of the module dependencies and use a value
    // it is defined in. Touch twice to make sure it is newer than the build product.
    h.touch(EInterfacePath)
    h.touch(EInterfacePath)
    h.replace(contentsOf: "other", with: "import E;let bar = foo + moduleEValue")

    // Changing a dependency will mean that we both re-run the dependency scan,
    // and also ensure that all source-files are re-built with a non-cascading build
    // since the source files themselves have not changed.
    try await h.doABuild(
      "update dependency (E) interface timestamp",
      checkDiagnostics: true,
      extraArguments: h.explicitBuildArgs,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanDependencyNewInput("E", EInterfacePath.pathString)
      explicitIncrementalScanDependencyInvalidated("theModule")
      noFingerprintInSwiftModule("E.swiftinterface")
      dependencyNewerThanNode("E.swiftinterface")
      dependencyNewerThanNode("E.swiftinterface")  // FIXME: Why do we see this twice?
      maySkip("main")
      schedulingChanged("other")
      invalidatedExternally("main", "other")
      queuingInitial("main", "other")
      notSchedulingDependentsUnknownChanges("other")
      findingBatchingCompiling("main", "other")
      explicitDependencyModuleOlderThanInput("E")
      moduleWillBeRebuiltOutOfDate("E")
      explicitModulesWillBeRebuilt(["E"])
      compilingExplicitSwiftDependency("E")
    }
  }

  // MARK: - Binary dependency invalidation tests

  // A dependency has been re-built to be newer than its dependents so we must
  // ensure the dependents get re-built even though all the modules are
  // up-to-date with respect to their textual source inputs.
  //
  //             test
  //                 \
  //                  J
  //                   \
  //                    G
  //
  // On this graph, after the initial build, if G module binary file is newer
  // than that of J, even if each of the modules is up-to-date w.r.t. their
  // source inputs, we still expect that J gets re-built.
  @Test(arguments: TestBuildConfig.explicitOnlyConfigs)
  func explicitIncrementalBuildChangedDependencyBinaryInvalidatesUpstream(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    h.replace(contentsOf: "other", with: "import J;")
    try await h.buildInitialState(checkDiagnostics: false)

    let modCacheEntries = try localFileSystem.getDirectoryContents(h.explicitModuleCacheDir)
    let nameOfGModule = try #require(modCacheEntries.first { $0.hasPrefix("G") && $0.hasSuffix(".swiftmodule") })
    let pathToGModule = h.explicitModuleCacheDir.appending(component: nameOfGModule)
    // Just update the time-stamp of one of the module dependencies' outputs.
    h.touch(pathToGModule)
    // Touch one of the inputs to actually trigger the incremental build.
    try h.touch("other")
    try h.touch("other") // touch twice to make sure it is newer than build output.

    try await h.doABuild(
      "update dependency (G) result timestamp",
      checkDiagnostics: true,
      extraArguments: h.explicitBuildArgs,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      maySkip("main")
      schedulingChangedInitialQueuing("other")
      skipping("main")
      explicitDependencyModuleOlderThanInput("J")
      moduleWillBeRebuiltOutOfDate("J")
      explicitModulesWillBeRebuilt(["J"])
      compilingExplicitSwiftDependency("J")
      findingBatchingCompiling("other")
      reading(deps: "other")
      skipped("main")
      schedulingPostCompileJobs
      linking
    }
  }

  // An unchanged binary dependency should not invalidate upstream dependencies.
  @Test(arguments: TestBuildConfig.explicitOnlyConfigs)
  func explicitIncrementalBuildUnchangedBinaryDependencyDoesNotInvalidateUpstream(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    h.replace(contentsOf: "other", with: "import J;")

    // After an initial build, replace the G.swiftinterface with G.swiftmodule
    // and repeat the initial build to settle into the "initial" state for the test.
    try await h.buildInitialState(checkDiagnostics: false)
    let modCacheEntries = try localFileSystem.getDirectoryContents(h.explicitModuleCacheDir)
    let nameOfGModule = try #require(modCacheEntries.first { $0.hasPrefix("G") && $0.hasSuffix(".swiftmodule") })
    let pathToGModule = h.explicitModuleCacheDir.appending(component: nameOfGModule)
    // Rename the binary module to G.swiftmodule so that the next build's scan finds it.
    let newPathToGModule = h.explicitSwiftDependenciesPath.appending(component: "G.swiftmodule")
    try! localFileSystem.move(from: pathToGModule, to: newPathToGModule)
    // Delete the textual interface it was built from so that it is treated as a binary-only dependency now.
    try! localFileSystem.removeFileTree(
      try AbsolutePath(validating: h.explicitSwiftDependenciesPath.appending(component: "G.swiftinterface").pathString)
    )
    try await h.buildInitialState(checkDiagnostics: false)

    // Touch one of the inputs to actually trigger the incremental build.
    try h.touch("other")
    try h.touch("other") // touch twice to make sure it is newer than build output.

    // Touch the output of a dependency of 'G', to ensure that it is newer than 'G', but 'G' still
    // does not get "invalidated".
    let nameOfDModule = try #require(modCacheEntries.first { $0.hasPrefix("D") && $0.hasSuffix(".pcm") })
    let pathToDModule = h.explicitModuleCacheDir.appending(component: nameOfDModule)
    h.touch(pathToDModule)

    try await h.doABuild(
      "Unchanged binary dependency (G)",
      checkDiagnostics: true,
      extraArguments: h.explicitBuildArgs,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      noFingerprintInSwiftModule("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface")  // FIXME: Why do we see this twice?
      maySkip("main")
      schedulingChangedInitialQueuing("other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      invalidatedExternally("main", "other")
      queuingInitial("main")
      foundBatchableJobs(2)
      formingOneBatch
      addingToBatchThenForming("main", "other")
      compiling("main", "other")
      reading(deps: "main")
      reading(deps: "other")
      schedulingPostCompileJobs
      linking
    }
  }

  // A changed binary dependency causes a rescan.
  @Test(arguments: TestBuildConfig.explicitOnlyConfigs)
  func explicitIncrementalBuildChangedBinaryDependencyCausesRescan(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    h.replace(contentsOf: "other", with: "import J;")

    // After an initial build, replace the G.swiftinterface with G.swiftmodule
    // and repeat the initial build to settle into the "initial" state for the test.
    try await h.buildInitialState(checkDiagnostics: false)
    let modCacheEntries = try localFileSystem.getDirectoryContents(h.explicitModuleCacheDir)
    let nameOfGModule = try #require(modCacheEntries.first { $0.hasPrefix("G") && $0.hasSuffix(".swiftmodule") })
    let pathToGModule = h.explicitModuleCacheDir.appending(component: nameOfGModule)
    // Rename the binary module to G.swiftmodule so that the next build's scan finds it.
    let newPathToGModule = h.explicitSwiftDependenciesPath.appending(component: "G.swiftmodule")
    try! localFileSystem.move(from: pathToGModule, to: newPathToGModule)
    // Delete the textual interface it was built from so that it is treated as a binary-only dependency now.
    try! localFileSystem.removeFileTree(
      try AbsolutePath(validating: h.explicitSwiftDependenciesPath.appending(component: "G.swiftinterface").pathString)
    )
    try await h.buildInitialState(checkDiagnostics: false)

    // Touch one of the inputs to actually trigger the incremental build.
    try h.touch("other")
    try h.touch("other") // touch twice to make sure it is newer than build output.

    // Touch 'G.swiftmodule' to trigger the dependency scanner to re-scan it.
    h.touch(newPathToGModule)

    try await h.doABuild(
      "Changed binary dependency (G)",
      checkDiagnostics: true,
      extraArguments: h.explicitBuildArgs,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanDependencyNewInput("G", newPathToGModule.pathString)
      explicitIncrementalScanDependencyInvalidated("J")
      explicitIncrementalScanDependencyInvalidated("theModule")
      noFingerprintInSwiftModule("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface")  // FIXME: Why do we see this twice?
      maySkip("main")
      explicitDependencyModuleOlderThanInput("J")
      moduleWillBeRebuiltOutOfDate("J")
      explicitModulesWillBeRebuilt(["J"])
      compilingExplicitSwiftDependency("J")
      schedulingChangedInitialQueuing("other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      invalidatedExternally("main", "other")
      queuingInitial("main")
      foundBatchableJobs(2)
      formingOneBatch
      addingToBatchThenForming("main", "other")
      compiling("main", "other")
      reading(deps: "main")
      reading(deps: "other")
      schedulingPostCompileJobs
      linking
    }
  }

  // MARK: - Emit module only

  @Test(arguments: TestBuildConfig.availableExplicitConfigs)
  func explicitIncrementalEmitModuleOnly(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)

    let args =
      [
        "swiftc",
        "-module-name", h.module,
        "-emit-module", "-emit-module-path",
        h.derivedDataPath.appending(component: h.module + ".swiftmodule").pathString,
        "-incremental",
        "-driver-show-incremental",
        "-driver-show-job-lifecycle",
        "-save-temps",
        "-output-file-map", h.OFM.pathString,
        "-no-color-diagnostics",
      ] + h.inputPathsAndContents.map { $0.0.pathString }.sorted() + h.explicitBuildArgs + h.sdkArgumentsForTesting

    // Initial build.
    try await h.doABuildWithoutExpectations(arguments: args)

    // Subsequent build: ensure module does not get re-emitted since inputs have not changed.
    try await h.doABuild(
      whenAutolinking: h.autolinkLifecycleExpectedDiags,
      arguments: args
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      queuingInitial("main", "other")
    }

    try h.touch("main")
    try h.touch("other")
    // Subsequent build: ensure module re-emitted since inputs changed.
    try await h.doABuild(
      whenAutolinking: h.autolinkLifecycleExpectedDiags,
      arguments: args
    ) {
      readGraph
      explicitIncrementalScanReuseCache(h.serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(h.serializedDepScanCachePath.pathString)
      queuingInitial("main", "other")
      emittingModule(h.module)
      schedulingPostCompileJobs
    }
  }

  // MARK: - Compilation caching incremental tests

  @Test(
    .serialized,
    .skipHostOS(.win32, comment: "CAS cannot be removed on windows when test is running"),
    arguments: TestBuildConfig.available([.cachingBuild, .cachingPrefixMapped])
  )
  func incrementalCompilationCaching(config: TestBuildConfig) async throws {
    let h = try IncrementalTestHarness(config: config)
    let extraArguments = [
      "-cache-compile-job",
      "-cas-path", h.casPath.nativePathString(escaped: true),
      "-O", "-parse-stdlib",
    ]
    h.replace(contentsOf: "other", with: "import O;")

    // Simplified initial build.
    try await h.doABuild(
      "Initial Simplified Build with Caching",
      checkDiagnostics: false,
      extraArguments: h.explicitBuildArgs + extraArguments,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      startCompilingExplicitSwiftDependency("O")
      finishCompilingExplicitSwiftDependency("O")
      compiling("main", "other")
    }

    // Delete the CAS, then rebuild.
    try localFileSystem.removeFileTree(h.casPath)

    // Deleting the CAS should cause a full rebuild since all modules are missing from CAS.
    try await h.doABuild(
      "Deleting CAS and rebuild",
      checkDiagnostics: false,
      extraArguments: h.explicitBuildArgs + extraArguments,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      explicitDependencyModuleMissingFromCAS("O")
      moduleInfoStaleOutOfDate("O")
      moduleWillBeRebuiltOutOfDate("O")
      explicitModulesWillBeRebuilt(["O"])
      compilingExplicitSwiftDependency("O")
      foundBatchableJobs(2)
      formingOneBatch
      addingToBatchThenForming("main", "other")
      startCompilingExplicitSwiftDependency("O")
      finishCompilingExplicitSwiftDependency("O")
      compiling("main", "other")
    }
  }
}
