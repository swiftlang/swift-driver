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

// MARK: - Test Harness

final class IncrementalTestHarness {
  let config: TestBuildConfig
  let sdkArgumentsForTesting: [String]

  var tempDir: AbsolutePath = try! AbsolutePath(validating: "/tmp")
  var derivedDataDir: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }

  let module = "theModule"
  var OFM: AbsolutePath {
    tempDir.appending(component: "OFM.json")
  }
  let baseNamesAndContents = [
    "main": "let foo = 1",
    "other": "let bar = foo",
  ]
  func inputPath(basename: String) -> AbsolutePath {
    tempDir.appending(component: basename + ".swift")
  }
  var inputPathsAndContents: [(AbsolutePath, String)] {
    baseNamesAndContents.map {
      (inputPath(basename: $0.key), $0.value)
    }
  }
  var derivedDataPath: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }
  var mainSwiftDepsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-main.swiftdeps")
  }
  var priorsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-main.priors")
  }
  var casPath: AbsolutePath {
    derivedDataPath.appending(component: "cas")
  }
  func swiftDepsPath(basename: String) -> AbsolutePath {
    derivedDataPath.appending(component: "\(basename).swiftdeps")
  }
  var serializedDepScanCachePath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-main.swiftmoduledeps")
  }
  var autolinkIncrementalExpectedDiags: [Diagnostic.Message] {
    queuingExtractingAutolink(module)
  }
  var autolinkLifecycleExpectedDiags: [Diagnostic.Message] {
    extractingAutolink(module)
  }
  var commonArgs: [String] {
    [
      "swiftc",
      "-Xcc", "-Xclang", "-Xcc", "-fbuiltin-headers-in-system-modules",
      "-module-name", module,
      "-o", derivedDataPath.appending(component: module + ".o").nativePathString(escaped: false),
      "-output-file-map", OFM.nativePathString(escaped: false),
      "-driver-show-incremental",
      "-driver-show-job-lifecycle",
      "-enable-batch-mode",
      //        "-v",
      "-save-temps",
      "-incremental",
      "-no-color-diagnostics",
      "-swift-version", "5",
    ]
      + inputPathsAndContents.map({ $0.0.nativePathString(escaped: false) }).sorted()
  }

  var explicitModuleCacheDir: AbsolutePath {
    tempDir.appending(component: "ModuleCache")
  }
  var explicitDependencyTestInputsPath: AbsolutePath {
    tempDir.appending(component: "ExplicitTestInputs")
  }
  var explicitCDependenciesPath: AbsolutePath {
    explicitDependencyTestInputsPath.appending(component: "CHeaders")
  }
  var explicitSwiftDependenciesPath: AbsolutePath {
    explicitDependencyTestInputsPath.appending(component: "Swift")
  }

  var explicitDependencyTestInputsSourcePath: AbsolutePath {
    var root: AbsolutePath = try! AbsolutePath(validating: #file)
    while root.basename != "Tests" {
      root = root.parentDirectory
    }
    return root.parentDirectory.appending(component: "TestInputs")
  }

  var explicitBuildArgs: [String] {
    [
      "-explicit-module-build",
      "-incremental-dependency-scan",
      "-module-cache-path", explicitModuleCacheDir.nativePathString(escaped: false),
      // Disable implicit imports to keep tests simpler
      "-Xfrontend", "-disable-implicit-concurrency-module-import",
      "-Xfrontend", "-disable-implicit-string-processing-module-import",
      "-I", explicitCDependenciesPath.nativePathString(escaped: false),
      "-I", explicitSwiftDependenciesPath.nativePathString(escaped: false),
    ] + extraExplicitBuildArgs
  }
  var extraExplicitBuildArgs: [String] = []

  var cachingArgs: [String] {
    [
      "-cache-compile-job",
      "-cas-path", casPath.nativePathString(escaped: false),
    ]
  }

  var prefixMappingArgs: [String] {
    [
      "-scanner-prefix-map-paths",
      tempDir.pathString, "/^tmp",
    ]
  }

  /// Extra args determined by the config (caching/prefix only, excluding explicit build args)
  var configCachingArgs: [String] {
    switch config {
    case .implicitModule, .explicitModule: return []
    case .cachingBuild: return cachingArgs
    case .cachingPrefixMapped: return cachingArgs + prefixMappingArgs
    }
  }

  /// All config-derived args (explicit + caching + prefix as appropriate)
  var configBuildArgs: [String] {
    switch config {
    case .implicitModule: return []
    case .explicitModule: return explicitBuildArgs
    case .cachingBuild: return explicitBuildArgs + cachingArgs
    case .cachingPrefixMapped: return explicitBuildArgs + cachingArgs + prefixMappingArgs
    }
  }

  init(config: TestBuildConfig = .implicitModule) throws {
    self.config = config

    guard let sdkArgs = try Driver.sdkArgumentsForTesting() else {
      throw IncrementalTestError("SDK arguments not available")
    }
    self.sdkArgumentsForTesting = sdkArgs

    self.tempDir = try withTemporaryDirectory(removeTreeOnDeinit: false) { $0 }
    try! localFileSystem.createDirectory(explicitModuleCacheDir)
    try! localFileSystem.createDirectory(derivedDataPath)
    try! localFileSystem.createDirectory(explicitDependencyTestInputsPath)
    try! localFileSystem.createDirectory(explicitCDependenciesPath)
    try! localFileSystem.createDirectory(explicitSwiftDependenciesPath)
    OutputFileMapCreator.write(
      module: module,
      inputPaths: inputPathsAndContents.map { $0.0 },
      derivedData: derivedDataPath,
      to: OFM
    )
    for (base, contents) in baseNamesAndContents {
      write(contents, to: base)
    }

    // Set up a per-test copy of all the explicit build module input artifacts
    do {
      let ebmSwiftInputsSourcePath =
        explicitDependencyTestInputsSourcePath
        .appending(component: "ExplicitModuleBuilds").appending(component: "Swift")
      let ebmCInputsSourcePath =
        explicitDependencyTestInputsSourcePath
        .appending(component: "ExplicitModuleBuilds").appending(component: "CHeaders")
      stdoutStream.flush()
      try! localFileSystem.getDirectoryContents(ebmSwiftInputsSourcePath).forEach { filePath in
        let sourceFilePath = ebmSwiftInputsSourcePath.appending(component: filePath)
        let destinationFilePath = explicitSwiftDependenciesPath.appending(component: filePath)
        try! localFileSystem.copy(from: sourceFilePath, to: destinationFilePath)
      }
      try! localFileSystem.getDirectoryContents(ebmCInputsSourcePath).forEach { filePath in
        let sourceFilePath = ebmCInputsSourcePath.appending(component: filePath)
        let destinationFilePath = explicitCDependenciesPath.appending(component: filePath)
        try! localFileSystem.copy(from: sourceFilePath, to: destinationFilePath)
      }
    }
    // Touch timestamp file, which in process ensures the file system timestamp changed.
    try! localFileSystem.touch(tempDir.appending(component: "timestamp"))
    let driver = try! TestDriver(args: ["swiftc"])
    if driver.isFrontendArgSupported(.moduleLoadMode) {
      self.extraExplicitBuildArgs = ["-Xfrontend", "-module-load-mode", "-Xfrontend", "prefer-interface"]
    }
  }

  deinit {
    try? localFileSystem.removeFileTree(tempDir)
  }
}

struct IncrementalTestError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

// MARK: - Build stage helpers

extension IncrementalTestHarness {
  /// Setup the initial post-build state.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  ///   - overrideExplicit: Override config's explicit module build setting
  /// - Returns: The `Driver` object
  @discardableResult
  func buildInitialState(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = [],
    overrideExplicit: Bool? = nil
  ) async throws -> TestDriver {
    let isExplicit = overrideExplicit ?? config.isExplicitModuleBuild
    let buildExtraArgs =
      isExplicit
      ? explicitBuildArgs + configCachingArgs + extraArguments
      : extraArguments

    @DiagsBuilder var implicitBuildInitialRemarks: [Diagnostic.Message] {
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
    @DiagsBuilder var explicitBuildInitialRemarks: [Diagnostic.Message] {
      implicitBuildInitialRemarks
      explicitIncrementalScanReuseCache(serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheLoadFailure(serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(serializedDepScanCachePath.pathString)
      compilingExplicitClangDependency("SwiftShims")
      compilingExplicitSwiftDependency("Swift")
      compilingExplicitSwiftDependency("SwiftOnoneSupport")
    }

    return try await doABuild(
      "initial",
      checkDiagnostics: checkDiagnostics,
      extraArguments: buildExtraArgs,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) { isExplicit ? explicitBuildInitialRemarks : implicitBuildInitialRemarks }
  }

  /// Try a build with no changes.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  ///   - overrideExplicit: Override config's explicit module build setting
  @discardableResult
  func checkNullBuild(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = [],
    overrideExplicit: Bool? = nil
  ) async throws -> TestDriver {
    let isExplicit = overrideExplicit ?? config.isExplicitModuleBuild
    let buildExtraArgs =
      isExplicit
      ? explicitBuildArgs + configCachingArgs + extraArguments
      : extraArguments

    @DiagsBuilder var implicitBuildNullRemarks: [Diagnostic.Message] {
      readGraph
      maySkip("main", "other")
      skipping("main", "other")
      skipped("main", "other")
      skippingLinking
    }
    @DiagsBuilder var explicitBuildNullRemarks: [Diagnostic.Message] {
      implicitBuildNullRemarks
      explicitIncrementalScanReuseCache(serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(serializedDepScanCachePath.pathString)
    }

    return try await doABuild(
      "as is",
      checkDiagnostics: checkDiagnostics,
      extraArguments: buildExtraArgs,
      whenAutolinking: []
    ) { isExplicit ? explicitBuildNullRemarks : implicitBuildNullRemarks }
  }

  /// Check reaction to touching a non-propagating input.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  func checkNoPropagation(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) async throws {
    try touch("other")
    try await doABuild(
      "touch other; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      maySkip("main")
      schedulingChangedInitialQueuing("other")
      skipping("main")
      readGraph
      findingBatchingCompiling("other")
      reading(deps: "other")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedLinking
      skipped("main")
    }
  }

  /// Check reaction to touching both inputs.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  ///   - overrideExplicit: Override config's explicit module build setting
  func checkReactionToTouchingAll(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = [],
    overrideExplicit: Bool? = nil
  ) async throws {
    let isExplicit = overrideExplicit ?? config.isExplicitModuleBuild
    let buildExtraArgs =
      isExplicit
      ? explicitBuildArgs + configCachingArgs + extraArguments
      : extraArguments

    @DiagsBuilder var implicitBuildRemarks: [Diagnostic.Message] {
      readGraph
      schedulingChangedInitialQueuing("main", "other")
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedLinking
    }
    @DiagsBuilder var explicitBuildRemarks: [Diagnostic.Message] {
      implicitBuildRemarks
      explicitIncrementalScanReuseCache(serializedDepScanCachePath.pathString)
      explicitIncrementalScanCacheSerialized(serializedDepScanCachePath.pathString)
    }

    try touch("main")
    try touch("other")
    try await doABuild(
      "touch both; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: buildExtraArgs,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) { isExplicit ? explicitBuildRemarks : implicitBuildRemarks }
  }

  /// Check reaction to changing a top-level declaration.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  func checkPropagationOfTopLevelChange(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) async throws {
    replace(contentsOf: "main", with: "let foo = \"hello\"")
    try await doABuild(
      "replace contents of main; propagating into 2nd wave",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      schedulingChanged("main")
      maySkip("other")
      queuingInitial("main")
      notSchedulingDependentsUnknownChanges("main")
      skipping("other")
      findingBatchingCompiling("main")
      reading(deps: "main")
      fingerprintsChanged("main")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      trace {
        TraceStep(.interface, sourceFileProvide: "main")
        TraceStep(.interface, topLevel: "foo", input: "main")
        TraceStep(.implementation, sourceFileProvide: "other")
      }
      queuingLaterSchedInvalBatchLink("other")
      findingBatchingCompiling("other")
      reading(deps: "other")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedLinking
    }
  }

  /// Check functioning of `-driver-always-rebuild-dependents`
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  func checkAlwaysRebuildDependents(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) async throws {
    try touch("main")
    let extraArgument = "-driver-always-rebuild-dependents"
    try await doABuild(
      "touch main; non-propagating but \(extraArgument)",
      checkDiagnostics: checkDiagnostics,
      extraArguments: [extraArgument],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      maySkip("other")
      queuingInitial("main")
      schedulingAlwaysRebuild("main")
      trace {
        TraceStep(.interface, topLevel: "foo", input: "main")
        TraceStep(.implementation, sourceFileProvide: "other")
      }
      foundDependent(of: "main", compiling: "other")
      schedulingChanged("main")
      schedulingDependent(of: "main", compiling: "other")
      queuingBecauseInitial("other")
      findingAndFormingBatch(2)
      addingToBatchThenForming("main", "other")
      schedulingPostCompileJobs
      compiling("main", "other")
      reading(deps: "main", "other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      linking
    }
  }

  /// Run the full incremental test pipeline (initial → null → no-propagation → touch all → propagation)
  func runIncrementalPipeline(checkDiagnostics: Bool) async throws {
    try await buildInitialState(checkDiagnostics: checkDiagnostics)
    try await checkNullBuild(checkDiagnostics: checkDiagnostics)
    try await checkNoPropagation(checkDiagnostics: checkDiagnostics)
    try await checkReactionToTouchingAll(checkDiagnostics: checkDiagnostics)
    try await checkPropagationOfTopLevelChange(checkDiagnostics: checkDiagnostics)
  }
}

// MARK: - Adding/Removing input test stages

extension IncrementalTestHarness {

  /// Test the addition of an input file
  ///
  /// - Parameters:
  ///   - newInput: basename without extension of new input file
  ///   - topLevelName: a new top level name defined in the new input
  func runAddingInputTest(newInput: String, defining topLevelName: String) async throws {
    try await buildInitialState(checkDiagnostics: true).withModuleDependencyGraph { initial in
      initial.ensureOmits(sourceBasenameWithoutExt: newInput)
      initial.ensureOmits(name: topLevelName)
    }

    write("let \(topLevelName) = foo", to: newInput)
    let newInputsPath = inputPath(basename: newInput)
    OutputFileMapCreator.write(
      module: module,
      inputPaths: inputPathsAndContents.map { $0.0 } + [newInputsPath],
      derivedData: derivedDataPath,
      to: OFM
    )
    try await checkReactionToAddingInput(newInput: newInput, definingTopLevel: topLevelName)
    try await checkRestorationOfIncrementalityAfterAddition(newInput: newInput, definingTopLevel: topLevelName)
  }

  /// Check reaction to adding an input file.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  func checkReactionToAddingInput(
    newInput: String,
    definingTopLevel topLevelName: String
  ) async throws {
    let newInputsPath = inputPath(basename: newInput)
    let driver = try await doABuild(
      "after addition of \(newInput)",
      checkDiagnostics: true,
      extraArguments: [newInputsPath.pathString],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      maySkip("main", "other")
      schedulingNew(newInput)
      missing(newInput)
      queuingInitial(newInput)
      notSchedulingDependentsNoEntry(newInput)
      skipping("main", "other")
      findingBatchingCompiling(newInput)
      reading(deps: newInput)
      newDefinitionOfSourceFile(.interface, newInput)
      newDefinitionOfSourceFile(.implementation, newInput)
      newDefinitionOfTopLevelName(.interface, name: topLevelName, input: newInput)
      newDefinitionOfTopLevelName(.implementation, name: topLevelName, input: newInput)
      schedLinking
      skipped("main", "other")
    }

    try driver.withModuleDependencyGraph { graph in
      #expect(graph.contains(sourceBasenameWithoutExt: newInput))
      #expect(graph.contains(name: topLevelName))
    }
  }

  /// Ensure that incremental builds happen after an addition.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  func checkRestorationOfIncrementalityAfterAddition(
    newInput: String,
    definingTopLevel topLevelName: String
  ) async throws {
    let newInputPath = inputPath(basename: newInput)
    let driver = try await doABuild(
      "after restoration of \(newInput)",
      checkDiagnostics: true,
      extraArguments: [newInputPath.pathString],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      maySkip("main", "other", newInput)
      skipping("main", "other", newInput)
      skippingLinking
      skipped(newInput, "main", "other")
    }

    try driver.withModuleDependencyGraph { graph in
      #expect(graph.contains(sourceBasenameWithoutExt: newInput))
      #expect(graph.contains(name: topLevelName))
    }
  }

  /// Check fallback to nonincremental build after a removal.
  ///
  /// - Parameters:
  ///   - removedInput: The basename without extension of the removed input
  ///   - topLevelName: A top level name defined by the removed file
  ///   - removeInputFromInvocation: Whether to remove the input from the invocation
  ///   - removeSwiftDepsOfRemovedInput: Whether to remove the swiftdeps of the removed input
  func checkNonincrementalAfterRemoving(
    removedInput: String,
    defining topLevelName: String,
    removeInputFromInvocation: Bool,
    removeSwiftDepsOfRemovedInput: Bool
  ) async throws -> TestDriver {
    let extraArguments =
      removeInputFromInvocation
      ? [] : [inputPath(basename: removedInput).pathString]

    if removeSwiftDepsOfRemovedInput {
      removeSwiftDeps(removedInput)
    }

    let driver = try await doABuild(
      "after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      switch (removeInputFromInvocation, removeSwiftDepsOfRemovedInput) {
      case (false, false):
        readGraphAndSkipAll("main", "other", removedInput)
      case (true, _):
        readGraph
        disabledForRemoval(removedInput)
        reading(deps: "main", "other")
        findingBatchingCompiling("main", "other")
        schedulingPostCompileJobs
        linking
      case (false, true):
        readGraph
        maySkip("main", "other", removedInput)
        missing(removedInput)
        queuingInitial(removedInput)
        skipping("main", "other")
        findingBatchingCompiling(removedInput)
        reading(deps: removedInput)
        fingerprintsMissingOfTopLevelName(name: topLevelName, removedInput)
        schedulingPostCompileJobs
        linking
        skipped("main", "other")
      }
    }

    if !removeInputFromInvocation {
      try driver.withModuleDependencyGraph { graph in
        graph.verifyGraph()
        #expect(graph.contains(sourceBasenameWithoutExt: removedInput))
        #expect(graph.contains(name: topLevelName))
      }
    }
    return driver
  }

  /// Ensure that incremental builds happen after a removal.
  ///
  /// - Parameters:
  ///   - removedInput: The basename without extension of the removed file
  ///   - topLevelName: The top-level decl name added by the removed file
  ///   - removeInputFromInvocation: Whether the input was removed from the invocation
  ///   - removeSwiftDepsOfRemovedInput: Whether swiftdeps were removed
  ///   - removedFileDependsOnChangedFileAndMainWasChanged: Whether main was changed
  func checkRestorationOfIncrementalityAfterRemoval(
    removedInput: String,
    defining topLevelName: String,
    removeInputFromInvocation: Bool,
    removeSwiftDepsOfRemovedInput: Bool,
    removedFileDependsOnChangedFileAndMainWasChanged: Bool
  ) async throws {
    let inputs = ["main", "other"] + (removeInputFromInvocation ? [] : [removedInput])
    let extraArguments =
      removeInputFromInvocation
      ? [] : [inputPath(basename: removedInput).pathString]
    let mainChanged = removedFileDependsOnChangedFileAndMainWasChanged
    let changedInputs = mainChanged ? ["main"] : []
    let unchangedInputs = inputs.filter { !changedInputs.contains($0) }
    let affectedInputs =
      removeInputFromInvocation
      ? ["other"] : [removedInput, "other"]
    let affectedInputsInBuild = affectedInputs.filter(inputs.contains)
    let affectedInputsInInvocationOrder = inputs.filter(affectedInputsInBuild.contains)

    let driver = try await doABuild(
      "restoring incrementality after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph

      if changedInputs.isEmpty {
        skippingAll(inputs)
      } else {
        let swiftDepsReadAfterFirstWave = changedInputs
        let omittedFromFirstWave = unchangedInputs
        respondToChangedInputs(
          changedInputs: changedInputs,
          unchangedInputs: unchangedInputs,
          swiftDepsReadAfterFirstWave: swiftDepsReadAfterFirstWave,
          omittedFromFirstWave: omittedFromFirstWave
        )
        integrateChangedMainWithPriors(
          removedInput: removedInput,
          defining: topLevelName,
          affectedInputs: affectedInputs,
          affectedInputsInBuild: affectedInputsInBuild,
          affectedInputsInInvocationOrder: affectedInputsInInvocationOrder,
          removeInputFromInvocation: removeInputFromInvocation
        )
        schedLinking
      }
    }

    try driver.withModuleDependencyGraph { graph in
      graph.verifyGraph()
      if removeInputFromInvocation {
        graph.ensureOmits(sourceBasenameWithoutExt: removedInput)
        graph.ensureOmits(name: topLevelName)
      } else {
        #expect(graph.contains(sourceBasenameWithoutExt: removedInput))
        #expect(graph.contains(name: topLevelName))
      }
    }
  }

  @DiagsBuilder func respondToChangedInputs(
    changedInputs: [String],
    unchangedInputs: [String],
    swiftDepsReadAfterFirstWave: [String],
    omittedFromFirstWave: [String]
  ) -> [Diagnostic.Message] {
    schedulingChanged(changedInputs)
    maySkip(unchangedInputs)
    queuingInitial(swiftDepsReadAfterFirstWave)
    notSchedulingDependentsUnknownChanges(changedInputs)
    skipping(omittedFromFirstWave)
    findingBatchingCompiling(swiftDepsReadAfterFirstWave)
    reading(deps: swiftDepsReadAfterFirstWave)
  }

  @DiagsBuilder var addDefsWithoutGraph: [Diagnostic.Message] {
    for (input, name) in [("main", "foo"), ("other", "bar")] {
      newDefinitionOfSourceFile(.interface, input)
      newDefinitionOfSourceFile(.implementation, input)
      newDefinitionOfTopLevelName(.interface, name: name, input: input)
      newDefinitionOfTopLevelName(.implementation, name: name, input: input)
    }
  }

  @DiagsBuilder func integrateChangedMainWithPriors(
    removedInput: String,
    defining topLevelName: String,
    affectedInputs: [String],
    affectedInputsInBuild: [String],
    affectedInputsInInvocationOrder: [String],
    removeInputFromInvocation: Bool
  ) -> [Diagnostic.Message] {
    fingerprintsChanged("main")
    fingerprintsMissingOfTopLevelName(name: "foo", "main")

    for input in affectedInputs {
      trace {
        TraceStep(.interface, sourceFileProvide: "main")
        TraceStep(.interface, topLevel: "foo", input: "main")
        TraceStep(.implementation, sourceFileProvide: input)
      }
    }
    queuingLater(affectedInputsInBuild)
    schedulingInvalidated(affectedInputsInBuild)
    findingBatchingCompiling(affectedInputsInInvocationOrder)
    reading(deps: "other")
    fingerprintsMissingOfTopLevelName(name: "bar", "other")

    let readingAnotherDeps = !removeInputFromInvocation
    if readingAnotherDeps {
      reading(deps: removedInput)
      fingerprintsMissingOfTopLevelName(name: topLevelName, removedInput)
    }
  }

  func checkReactionToObsoletePriors() async throws {
    try await doABuild(
      "check reaction to obsolete priors",
      checkDiagnostics: true,
      extraArguments: [],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      couldNotReadPriors
      findingBatchingCompiling("main", "other")
      reading(deps: "main")
      reading(deps: "other")
      schedLinking
    }
  }

  func checkReactionToTouchingSymlinks(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) async throws {
    try localFileSystem.touch(tempDir.appending(component: "timestamp"))

    for (file, _) in self.inputPathsAndContents {
      try localFileSystem.removeFileTree(file)
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try localFileSystem.createSymbolicLink(file, pointingAt: linkTarget, relative: false)
    }

    try await doABuild(
      "touch both symlinks; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      maySkip("main", "other")
      skipping("main", "other")
      skippingLinking
      skipped("main", "other")
    }
  }

  func checkReactionToTouchingSymlinkTargets(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) async throws {
    try localFileSystem.touch(tempDir.appending(component: "timestamp"))

    for (file, contents) in self.inputPathsAndContents {
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try! localFileSystem.writeFileContents(linkTarget) { $0.send(contents) }
    }

    try await doABuild(
      "touch both symlink targets; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      schedulingChangedInitialQueuing("main", "other")
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedulingPostCompileJobs
      linking
    }
  }
}

// MARK: - Build execution helpers

extension IncrementalTestHarness {
  @discardableResult
  func doABuild(
    _ message: String,
    checkDiagnostics: Bool,
    extraArguments: [String],
    whenAutolinking autolinkExpectedDiags: [Diagnostic.Message],
    @DiagsBuilder expecting expectedDiags: () -> [Diagnostic.Message]
  ) async throws -> TestDriver {
    if verboseTestOutput { print("*** starting build \(message) ***", to: &stderrStream); stderrStream.flush() }

    let allArgs = commonArgs + extraArguments + sdkArgumentsForTesting

    return try await checkDiagnostics
      ? doABuild(
        whenAutolinking: autolinkExpectedDiags,
        expecting: expectedDiags(),
        arguments: allArgs
      )
      : doABuildWithoutExpectations(arguments: allArgs)
  }

  func doABuild(
    whenAutolinking autolinkExpectedDiags: [Diagnostic.Message],
    expecting expectedDiags: [Diagnostic.Message],
    arguments: [String]
  ) async throws -> TestDriver {
    try await assertDriverDiagnostics(args: arguments) {
      driver,
      verifier in
      verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)

      expectedDiags.forEach { verifier.expect($0) }
      if driver.isAutolinkExtractJobNeeded {
        autolinkExpectedDiags.forEach { verifier.expect($0) }
      }
      await doTheCompile(&driver)
      return driver
    }
  }

  @discardableResult
  func doABuild(
    whenAutolinking autolinkExpectedDiags: [Diagnostic.Message],
    arguments: [String],
    @DiagsBuilder expecting expectedDiags: () -> [Diagnostic.Message]
  ) async throws -> TestDriver {
    try await doABuild(whenAutolinking: autolinkExpectedDiags, expecting: expectedDiags(), arguments: arguments)
  }

  @discardableResult
  func doABuildWithoutExpectations(arguments: [String]) async throws -> TestDriver {
    var driver = try TestDriver(args: arguments)
    await doTheCompile(&driver)
    return driver
  }

  func doTheCompile(_ driver: inout TestDriver) async {
    touch(tempDir.appending(component: "timestamp"))
    let jobs = try! await driver.planBuild()
    try? await driver.run(jobs: jobs)
  }
}

// MARK: - File manipulation helpers

extension IncrementalTestHarness {
  func touch(_ name: String) throws {
    if verboseTestOutput { print("*** touching \(name) ***", to: &stderrStream); stderrStream.flush() }
    let (path, _) = try #require(inputPathsAndContents.filter { $0.0.pathString.contains(name) }.first)
    touch(path)
  }

  func touch(_ path: AbsolutePath) {
    try! localFileSystem.touch(path)
  }

  /// Set modification time of a file
  ///
  /// - Parameters:
  ///   - path: The file whose modification time to change
  ///   - newModTime: The desired modification time
  func setModTime(of path: VirtualPath, to newModTime: Date) throws {
    var fileAttributes = try FileManager.default.attributesOfItem(atPath: path.name)
    fileAttributes[.modificationDate] = newModTime
    try FileManager.default.setAttributes(fileAttributes, ofItemAtPath: path.name)
  }

  func removeInput(_ name: String) {
    if verboseTestOutput { print("*** removing input \(name) ***", to: &stderrStream); stderrStream.flush() }
    try! localFileSystem.removeFileTree(inputPath(basename: name))
  }

  func removeSwiftDeps(_ name: String) {
    if verboseTestOutput { print("*** removing swiftdeps \(name) ***", to: &stderrStream); stderrStream.flush() }
    let swiftDepsPath = swiftDepsPath(basename: name)
    #expect(localFileSystem.exists(swiftDepsPath))
    try! localFileSystem.removeFileTree(swiftDepsPath)
  }

  func replace(contentsOf name: String, with replacement: String) {
    if verboseTestOutput { print("*** replacing \(name) ***", to: &stderrStream); stderrStream.flush() }
    let path = inputPath(basename: name)
    let previousContents = try! localFileSystem.readFileContents(path).cString
    try! localFileSystem.writeFileContents(path) { $0.send(replacement) }
    let newContents = try! localFileSystem.readFileContents(path).cString
    #expect(previousContents != newContents, "\(path.pathString) unchanged after write")
    #expect(replacement == newContents, "\(path.pathString) failed to write")
  }

  func write(_ contents: String, to basename: String) {
    if verboseTestOutput { print("*** writing \(contents) to \(basename)") }
    try! localFileSystem.writeFileContents(inputPath(basename: basename)) { $0.send(contents) }
  }

  func readPriors() -> ByteString? {
    try? localFileSystem.readFileContents(priorsPath)
  }

  func writePriors(_ contents: ByteString) {
    try! localFileSystem.writeFileContents(priorsPath, bytes: contents)
  }
}

// MARK: - Dot file helpers

extension IncrementalTestHarness {
  func expectNoDotFiles() {
    guard localFileSystem.exists(derivedDataDir) else { return }
    try! localFileSystem.getDirectoryContents(derivedDataDir)
      .forEach { derivedFile in
        #expect(!derivedFile.hasSuffix("dot"))
      }
  }

  func removeDotFiles() {
    try! localFileSystem.getDirectoryContents(derivedDataDir)
      .filter { $0.hasSuffix(".dot") }
      .map { derivedDataDir.appending(component: $0) }
      .forEach { try! localFileSystem.removeFileTree($0) }
  }

  func expect(dotFilesFor importedFiles: [String]) {
    let expectedDotFiles = Set(
      importedFiles.enumerated()
        .map { offset, element in "\(element).\(offset).dot" }
    )
    let actualDotFiles = Set(
      try! localFileSystem.getDirectoryContents(derivedDataDir)
        .filter { $0.hasSuffix(".dot") }
    )

    let missingDotFiles = expectedDotFiles.subtracting(actualDotFiles)
      .sortedByDotFileSequenceNumbers()
    let extraDotFiles = actualDotFiles.subtracting(expectedDotFiles)
      .sortedByDotFileSequenceNumbers()

    #expect(missingDotFiles == [])
    #expect(extraDotFiles == [])
  }
}

// MARK: - Removal test options

enum RemovalTestOption: String, CaseIterable, Comparable, Hashable, CustomStringConvertible, Sendable {
  case
    removeInputFromInvocation,
    removeSwiftDepsOfRemovedInput,
    removedFileDependsOnChangedFile

  private static let byInt = [Int: Self](uniqueKeysWithValues: allCases.enumerated().map { ($0, $1) })
  private static let intFor = [Self: Int](uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })

  var intValue: Int { Self.intFor[self]! }
  init(fromInt i: Int) { self = Self.byInt[i]! }

  static func < (lhs: RemovalTestOption, rhs: RemovalTestOption) -> Bool {
    lhs.intValue < rhs.intValue
  }
  var mask: Int { 1 << intValue }
  static let maxIntValue = allCases.map { $0.intValue }.max()!
  static let maxCombinedValue = (1 << (maxIntValue + 1)) - 1

  var description: String { rawValue }
}

typealias RemovalTestOptions = [RemovalTestOption]

extension RemovalTestOptions {
  static let allCombinations: [RemovalTestOptions] =
    (0...RemovalTestOption.maxCombinedValue).map(decoding)

  static func decoding(_ bits: Int) -> Self {
    RemovalTestOption.allCases.filter { opt in
      (1 << opt.intValue) & bits != 0
    }
  }
}

// MARK: - Diagnostic result builder

/// Build an array of diagnostics from a closure containing various things
@resultBuilder enum DiagsBuilder {}

/// Build a series of messages from series of messages
extension DiagsBuilder {
  static func buildBlock(_ components: [Diagnostic.Message]...) -> [Diagnostic.Message] {
    components.flatMap { $0 }
  }
}

/// A statement can be String, Message, or [Message]
extension DiagsBuilder {
  static func buildExpression(_ expression: String) -> [Diagnostic.Message] {
    [.remark(expression)]
  }
  static func buildExpression(_ expression: [Diagnostic.Message]) -> [Diagnostic.Message] {
    expression
  }
  static func buildExpression(_ expression: Diagnostic.Message) -> [Diagnostic.Message] {
    [expression]
  }
}

/// Handle control structures
extension DiagsBuilder {
  static func buildArray(_ components: [[Diagnostic.Message]]) -> [Diagnostic.Message] {
    components.flatMap { $0 }
  }
  static func buildOptional(_ component: [Diagnostic.Message]?) -> [Diagnostic.Message] {
    component ?? []
  }
  static func buildEither(first component: [Diagnostic.Message]) -> [Diagnostic.Message] {
    component
  }
  static func buildEither(second component: [Diagnostic.Message]) -> [Diagnostic.Message] {
    component
  }
}

// MARK: - Diagnostic shorthand methods

/// Allow tests to specify diagnostics without extra punctuation
protocol DiagVerifiable {}

extension IncrementalTestHarness: DiagVerifiable {}

extension DiagVerifiable {

  // MARK: - explicit builds
  @DiagsBuilder func explicitIncrementalScanReuseCache(_ cachePath: String) -> [Diagnostic.Message] {
    "Incremental module scan: Re-using serialized module scanning dependency cache from: '\(cachePath)'"
  }
  @DiagsBuilder func explicitIncrementalScanCacheLoadFailure(_ cachePath: String) -> [Diagnostic.Message] {
    "Incremental module scan: Failed to load module scanning dependency cache from: '\(cachePath)', re-building scanner cache from scratch."
  }
  @DiagsBuilder func explicitIncrementalScanCacheSerialized(_ cachePath: String) -> [Diagnostic.Message] {
    "Incremental module scan: Serializing module scanning dependency cache to: '\(cachePath)'."
  }
  @DiagsBuilder func explicitIncrementalScanDependencyNewInput(
    _ moduleName: String,
    _ changedInput: String
  ) -> [Diagnostic.Message] {
    "Incremental module scan: Dependency info for module '\(moduleName)' invalidated due to a modified input since last scan: '\(changedInput)'."
  }
  @DiagsBuilder func explicitIncrementalScanDependencyInvalidated(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental module scan: Dependency info for module '\(moduleName)' invalidated due to an out-of-date dependency."
  }
  @DiagsBuilder func explicitDependencyModuleOlderThanInput(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Dependency module \(dependencyModuleName) is older than input file"
  }
  @DiagsBuilder func startEmitModule(_ moduleName: String) -> [Diagnostic.Message] {
    "Starting Emitting module for \(moduleName)"
  }
  @DiagsBuilder func finishEmitModule(_ moduleName: String) -> [Diagnostic.Message] {
    "Finished Emitting module for \(moduleName)"
  }
  @DiagsBuilder func emittingModule(_ moduleName: String) -> [Diagnostic.Message] {
    startEmitModule(moduleName)
    finishEmitModule(moduleName)
  }
  @DiagsBuilder func startCompilingExplicitClangDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Starting Compiling Clang module \(dependencyModuleName)"
  }
  @DiagsBuilder func finishCompilingExplicitClangDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Finished Compiling Clang module \(dependencyModuleName)"
  }
  @DiagsBuilder func startCompilingExplicitSwiftDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Starting Compiling Swift module \(dependencyModuleName)"
  }
  @DiagsBuilder func finishCompilingExplicitSwiftDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Finished Compiling Swift module \(dependencyModuleName)"
  }
  @DiagsBuilder func compilingExplicitClangDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    startCompilingExplicitClangDependency(dependencyModuleName)
    finishCompilingExplicitClangDependency(dependencyModuleName)
  }
  @DiagsBuilder func compilingExplicitSwiftDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    startCompilingExplicitSwiftDependency(dependencyModuleName)
    finishCompilingExplicitSwiftDependency(dependencyModuleName)
  }
  @DiagsBuilder func moduleOutputNotFound(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Module output not found: '\(moduleName)'"
  }
  @DiagsBuilder func moduleWillBeRebuiltOutOfDate(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Dependency module '\(moduleName)' will be re-built: Out-of-date"
  }
  @DiagsBuilder func moduleWillBeRebuiltInvalidatedDownstream(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Dependency module '\(moduleName)' will be re-built: Invalidated by downstream dependency"
  }
  @DiagsBuilder func moduleInfoStaleOutOfDate(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Dependency module '\(moduleName)' info is stale: Out-of-date"
  }
  @DiagsBuilder func moduleInfoStaleInvalidatedDownstream(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Dependency module '\(moduleName)' info is stale: Invalidated by downstream dependency"
  }
  @DiagsBuilder func explicitModulesWillBeRebuilt(_ moduleNames: [String]) -> [Diagnostic.Message] {
    "Incremental compilation: Following explicit module dependencies will be re-built: [\(moduleNames.joined(separator: ", "))]"
  }
  @DiagsBuilder func explicitDependencyModuleMissingFromCAS(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Dependency module \(dependencyModuleName) is missing from CAS"
  }

  // MARK: - misc
  @DiagsBuilder func disabledForRemoval(_ removedInput: String) -> [Diagnostic.Message] {
    "Incremental compilation: Incremental compilation has been disabled, because the following inputs were used in the previous compilation but not in this one: \(removedInput).swift"
  }
  @DiagsBuilder var disabledForWMO: [Diagnostic.Message] {
    "Incremental compilation has been disabled: it is not compatible with whole module optimization"
  }
  // MARK: - build record
  @DiagsBuilder var cannotReadBuildRecord: [Diagnostic.Message] {
    "Incremental compilation: Incremental compilation could not read build record at"
  }
  @DiagsBuilder var disablingIncrementalCannotReadBuildRecord: [Diagnostic.Message] {
    "Incremental compilation: Disabling incremental build: could not read build record"
  }
  @DiagsBuilder var differentArgsPassed: [Diagnostic.Message] {
    "Incremental compilation: Incremental compilation has been disabled, because different arguments were passed to the compiler"
  }
  @DiagsBuilder var disablingIncrementalDifferentArgsPassed: [Diagnostic.Message] {
    "Incremental compilation: Disabling incremental build: different arguments were passed to the compiler"
  }
  @DiagsBuilder var missingMainDependencyEntry: [Diagnostic.Message] {
    .warning(
      "ignoring -incremental; output file map has no main dependencies entry (\"swift-dependencies\" under \"\")"
    )
  }
  @DiagsBuilder var disablingIncremental: [Diagnostic.Message] {
    "Incremental compilation: Disabling incremental build: no build record path"
  }
  // MARK: - graph
  @DiagsBuilder var createdGraphFromSwiftdeps: [Diagnostic.Message] {
    "Incremental compilation: Created dependency graph from swiftdeps files"
  }
  @DiagsBuilder var readGraph: [Diagnostic.Message] {
    "Incremental compilation: Read dependency graph"
  }
  @DiagsBuilder var couldNotReadPriors: [Diagnostic.Message] {
    .remark("Will not do cross-module incremental builds, wrong version of priors; expected")
  }
  // MARK: - dependencies
  @DiagsBuilder func reading(deps inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Reading dependencies from \(input).swift"
    }
  }
  @DiagsBuilder func reading(deps inputs: String...) -> [Diagnostic.Message] {
    reading(deps: inputs)
  }

  @DiagsBuilder func fingerprintChanged(_ aspect: DependencyKey.DeclAspect, _ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Fingerprint changed for existing \(aspect) of source file \(input) in \(input).swift"
  }
  @DiagsBuilder func fingerprintsChanged(_ input: String) -> [Diagnostic.Message] {
    for aspect: DependencyKey.DeclAspect in [.interface, .implementation] {
      fingerprintChanged(aspect, input)
    }
  }

  @DiagsBuilder func fingerprintsMissingOfTopLevelName(name: String, _ input: String) -> [Diagnostic.Message] {
    for aspect: DependencyKey.DeclAspect in [.interface, .implementation] {
      "Incremental compilation: Fingerprint missing for existing \(aspect) of top-level name '\(name)' in \(input).swift"
    }
  }

  @DiagsBuilder func newDefinitionOfSourceFile(
    _ aspect: DependencyKey.DeclAspect,
    _ input: String
  ) -> [Diagnostic.Message] {
    "Incremental compilation: New definition: \(aspect) of source file \(input) in \(input).swift"
  }
  @DiagsBuilder func newDefinitionOfTopLevelName(
    _ aspect: DependencyKey.DeclAspect,
    name: String,
    input: String
  ) -> [Diagnostic.Message] {
    "Incremental compilation: New definition: \(aspect) of top-level name '\(name)' in \(input).swift"
  }

  @DiagsBuilder func foundDependent(of defInput: String, compiling useInput: String) -> [Diagnostic.Message] {
    "Incremental compilation: Found dependent of \(defInput).swift:  {compile: \(useInput).o <= \(useInput).swift}"
  }
  @DiagsBuilder func hasMalformed(_ inputs: [String]) -> [Diagnostic.Message] {
    for newInput in inputs {
      "Incremental compilation: Has malformed dependency source; will queue  {compile: \(newInput).o <= \(newInput).swift}"
    }
  }
  @DiagsBuilder func hasMalformed(_ inputs: String...) -> [Diagnostic.Message] {
    hasMalformed(inputs)
  }
  @DiagsBuilder func invalidatedExternally(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Invalidated externally; will queue  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func invalidatedExternally(_ inputs: String...) -> [Diagnostic.Message] {
    invalidatedExternally(inputs)
  }
  @DiagsBuilder func failedToFindSource(_ input: String) -> [Diagnostic.Message] {
    .warning(
      "Failed to find source file '\(input).swift' in command line, recovering with a full rebuild. Next build will be incremental."
    )
  }
  @DiagsBuilder func failedToReadSomeSource(compiling input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Failed to read some dependencies source; compiling everything  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func noFingerprintInSwiftModule(_ dependencyFile: String) -> [Diagnostic.Message] {
    "No fingerprint in swiftmodule: Invalidating all nodes in newer: \(dependencyFile)"
  }
  @DiagsBuilder func dependencyNewerThanNode(_ dependencyFile: String) -> [Diagnostic.Message] {
    "Newer: \(dependencyFile) -> SwiftDriver.ModuleDependencyGraph.Node"
  }

  // MARK: - tracing
  @DiagsBuilder func trace(@TraceBuilder _ steps: () -> String) -> [Diagnostic.Message] {
    steps()
  }

  // MARK: - scheduling
  @DiagsBuilder func schedulingAlwaysRebuild(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: scheduling dependents of \(input).swift; -driver-always-rebuild-dependents"
  }
  @DiagsBuilder func schedulingNew(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Scheduling new  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func schedulingChanged(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Scheduling changed input  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func schedulingChanged(_ inputs: String...) -> [Diagnostic.Message] {
    schedulingChanged(inputs)
  }

  @DiagsBuilder func schedulingNoncascading(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Scheduling noncascading build  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func schedulingNoncascading(_ inputs: String...) -> [Diagnostic.Message] {
    schedulingNoncascading(inputs)
  }

  @DiagsBuilder func schedulingInvalidated(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Scheduling invalidated  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func schedulingInvalidated(_ inputs: String...) -> [Diagnostic.Message] {
    schedulingInvalidated(inputs)
  }

  @DiagsBuilder func schedulingChangedInitialQueuing(_ inputs: String...) -> [Diagnostic.Message] {
    for input in inputs {
      schedulingChanged(input)
      queuingInitial(input)
      notSchedulingDependentsUnknownChanges(input)
    }
  }

  @DiagsBuilder func schedulingDependent(of defInput: String, compiling useInput: String) -> [Diagnostic.Message] {
    "Incremental compilation: Immediately scheduling dependent on \(defInput).swift  {compile: \(useInput).o <= \(useInput).swift}"
  }

  @DiagsBuilder func notSchedulingDependentsNoEntry(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: not scheduling dependents of \(input).swift: no entry in build record or dependency graph"
  }

  @DiagsBuilder func notSchedulingDependentsUnknownChanges(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: not scheduling dependents of \(input).swift; unknown changes"
    }
  }
  @DiagsBuilder func notSchedulingDependentsUnknownChanges(_ inputs: String...) -> [Diagnostic.Message] {
    notSchedulingDependentsUnknownChanges(inputs)
  }

  @DiagsBuilder func notSchedulingDependentsDoNotNeedCascading(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: not scheduling dependents of \(input).swift: does not need cascading build"
    }
  }
  @DiagsBuilder func notSchedulingDependentsDoNotNeedCascading(_ inputs: String...) -> [Diagnostic.Message] {
    notSchedulingDependentsDoNotNeedCascading(inputs)
  }

  @DiagsBuilder func missing(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Missing an output; will queue  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func queuingInitial(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Queuing (initial):  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func queuingInitial(_ inputs: String...) -> [Diagnostic.Message] {
    queuingInitial(inputs)
  }

  @DiagsBuilder func queuingBecauseInitial(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Queuing because of the initial set:  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func queuingLater(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Queuing because of dependencies discovered later:  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func queuingLater(_ inputs: String...) -> [Diagnostic.Message] { queuingLater(inputs) }

  @DiagsBuilder func queuingLaterSchedInvalBatchLink(_ inputs: [String]) -> [Diagnostic.Message] {
    queuingLater(inputs)
    schedulingInvalidated(inputs)
  }
  @DiagsBuilder func queuingLaterSchedInvalBatchLink(_ inputs: String...) -> [Diagnostic.Message] {
    queuingLaterSchedInvalBatchLink(inputs)
  }

  // MARK: - skipping
  @DiagsBuilder func maySkip(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: May skip current input:  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func maySkip(_ inputs: String...) -> [Diagnostic.Message] {
    maySkip(inputs)
  }
  @DiagsBuilder func skipping(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Skipping input:  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func skipping(_ inputs: String...) -> [Diagnostic.Message] {
    skipping(inputs)
  }
  @DiagsBuilder func skipped(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Skipped Compiling \(input).swift"
    }
  }
  @DiagsBuilder func skipped(_ inputs: String...) -> [Diagnostic.Message] {
    skipped(inputs)
  }
  @DiagsBuilder func skippingAll(_ inputs: [String]) -> [Diagnostic.Message] {
    maySkip(inputs)
    skipping(inputs)
    skippingLinking
    skipped(inputs)
  }
  @DiagsBuilder func skippingAll(_ inputs: String...) -> [Diagnostic.Message] {
    skippingAll(inputs)
  }
  @DiagsBuilder func readGraphAndSkipAll(_ inputs: [String]) -> [Diagnostic.Message] {
    readGraph
    skippingAll(inputs)
  }
  @DiagsBuilder func readGraphAndSkipAll(_ inputs: String...) -> [Diagnostic.Message] {
    readGraphAndSkipAll(inputs)
  }

  // MARK: - batching
  @DiagsBuilder func addingToBatch(_ inputs: [String], _ b: Int) -> [Diagnostic.Message] {
    for input in inputs {
      "Adding {compile: \(input).swift} to batch \(b)"
    }
  }
  @DiagsBuilder func formingBatch(_ inputs: [String]) -> [Diagnostic.Message] {
    "Forming batch job from \(inputs.count) constituents: \(inputs.map{$0 + ".swift"}.joined(separator: ", "))"
  }
  @DiagsBuilder func formingBatch(_ inputs: String...) -> [Diagnostic.Message] {
    formingBatch(inputs)
  }
  @DiagsBuilder func foundBatchableJobs(_ jobCount: Int) -> [Diagnostic.Message] {
    "Found \(jobCount) batchable job"
  }
  @DiagsBuilder var formingOneBatch: [Diagnostic.Message] { "Forming into 1 batch" }

  @DiagsBuilder func findingAndFormingBatch(_ jobCount: Int) -> [Diagnostic.Message] {
    foundBatchableJobs(jobCount); formingOneBatch
  }
  @DiagsBuilder func addingToBatchThenForming(_ inputs: [String]) -> [Diagnostic.Message] {
    addingToBatch(inputs, 0); formingBatch(inputs)
  }
  @DiagsBuilder func addingToBatchThenForming(_ inputs: String...) -> [Diagnostic.Message] {
    addingToBatchThenForming(inputs)
  }

  // MARK: - compiling
  @DiagsBuilder func starting(_ inputs: [String]) -> [Diagnostic.Message] {
    "Starting Compiling \(inputs.map{$0 + ".swift"}.joined(separator: ", "))"
  }
  @DiagsBuilder func finished(_ inputs: [String]) -> [Diagnostic.Message] {
    "Finished Compiling \(inputs.map{$0 + ".swift"}.joined(separator: ", "))"
  }
  @DiagsBuilder func compiling(_ inputs: [String]) -> [Diagnostic.Message] {
    starting(inputs); finished(inputs)
  }
  @DiagsBuilder func compiling(_ inputs: String...) -> [Diagnostic.Message] {
    compiling(inputs)
  }

  // MARK: - batching and compiling
  @DiagsBuilder func findingBatchingCompiling(_ inputs: [String]) -> [Diagnostic.Message] {
    findingAndFormingBatch(inputs.count)
    addingToBatchThenForming(inputs)
    compiling(inputs)
  }
  @DiagsBuilder func findingBatchingCompiling(_ inputs: String...) -> [Diagnostic.Message] {
    findingBatchingCompiling(inputs)
  }

  // MARK: - linking
  @DiagsBuilder var schedulingPostCompileJobs: [Diagnostic.Message] {
    "Incremental compilation: Scheduling all post-compile jobs because something was compiled"
  }
  @DiagsBuilder var startingLinking: [Diagnostic.Message] { "Starting Linking theModule" }

  @DiagsBuilder var finishedLinking: [Diagnostic.Message] { "Finished Linking theModule" }

  @DiagsBuilder var skippingLinking: [Diagnostic.Message] {
    "Incremental compilation: Skipping job: Linking theModule; oldest output is current"
  }
  @DiagsBuilder var schedLinking: [Diagnostic.Message] { schedulingPostCompileJobs; linking }

  @DiagsBuilder var linking: [Diagnostic.Message] { startingLinking; finishedLinking }

  // MARK: - autolinking
  @DiagsBuilder func queuingExtractingAutolink(_ module: String) -> [Diagnostic.Message] {
    "Incremental compilation: Queuing Extracting autolink information for module \(module)"
  }
  @DiagsBuilder func startingExtractingAutolink(_ module: String) -> [Diagnostic.Message] {
    "Starting Extracting autolink information for module \(module)"
  }
  @DiagsBuilder func finishedExtractingAutolink(_ module: String) -> [Diagnostic.Message] {
    "Finished Extracting autolink information for module \(module)"
  }
  @DiagsBuilder func extractingAutolink(_ module: String) -> [Diagnostic.Message] {
    startingExtractingAutolink(module)
    finishedExtractingAutolink(module)
  }
}

// MARK: - Trace building

@resultBuilder enum TraceBuilder {
  static func buildBlock(_ components: TraceStep...) -> String {
    "\(components.map {$0.messagePart}.joined(separator: " -> "))"
  }
}

struct TraceStep {
  let messagePart: String

  init(_ aspect: DependencyKey.DeclAspect, sourceFileProvide source: String) {
    self.init(aspect, sourceFileProvide: source, input: source)
  }
  init(_ aspect: DependencyKey.DeclAspect, sourceFileProvide source: String, input: String?) {
    self.init(aspect, input: input) { t in
      .sourceFileProvide(name: "\(source).swiftdeps".intern(in: t))
    }
  }
  init(_ aspect: DependencyKey.DeclAspect, topLevel name: String, input: String) {
    self.init(aspect, input: input) { t in
      .topLevel(name: name.intern(in: t))
    }
  }
  private init(
    _ aspect: DependencyKey.DeclAspect,
    input: String?,
    _ createDesignator: (InternedStringTable) -> DependencyKey.Designator
  ) {
    self.messagePart = MockIncrementalCompilationSynchronizer.withInternedStringTable { t in
      let key = DependencyKey(aspect: aspect, designator: createDesignator(t))
      let inputPart = input.map { " in \($0).swift" } ?? ""
      return "\(key.description(in: t))\(inputPart)"
    }
  }
}

// MARK: - Graph inspection

extension Driver {
  /// Expose the protected ``ModuleDependencyGraph`` to a function and also prevent concurrent access or modification
  func withModuleDependencyGraph(_ fn: (ModuleDependencyGraph) throws -> Void) throws {
    let incrementalCompilationState = try #require(self.incrementalCompilationState, "no graph")
    try incrementalCompilationState.blockingConcurrentAccessOrMutationToProtectedState {
      try $0.testWithModuleDependencyGraph(fn)
    }
  }
  func verifyNoGraph() {
    #expect(incrementalCompilationState == nil)
  }
}

extension ModuleDependencyGraph {
  /// A convenience for testing
  var allNodes: [Node] {
    var nodes = [Node]()
    nodeFinder.forEachNode { nodes.append($0) }
    return nodes
  }
  func contains(sourceBasenameWithoutExt target: String) -> Bool {
    allNodes.contains { $0.contains(sourceBasenameWithoutExt: target, in: self) }
  }
  func contains(name target: String) -> Bool {
    allNodes.contains { $0.contains(name: target, in: self) }
  }
  func ensureOmits(sourceBasenameWithoutExt target: String) {
    nodeFinder.forEachNode { node in
      #expect(
        !node.contains(sourceBasenameWithoutExt: target, in: self),
        "graph should omit source: \(target)"
      )
    }
  }
  func ensureOmits(name: String) {
    nodeFinder.forEachNode { node in
      #expect(
        !node.contains(name: name, in: self),
        "graph should omit decl named: \(name)"
      )
    }
  }
}

extension ModuleDependencyGraph.Node {
  func contains(sourceBasenameWithoutExt target: String, in g: ModuleDependencyGraph) -> Bool {
    switch key.designator {
    case .sourceFileProvide(let name):
      return (try? VirtualPath(path: name.lookup(in: g)))
        .map { $0.basenameWithoutExt == target }
        ?? false
    case .externalDepend(let externalDependency):
      return externalDependency.path.map {
        $0.basenameWithoutExt == target
      }
        ?? false
    case .topLevel, .dynamicLookup, .nominal, .member, .potentialMember:
      return false
    }
  }

  func contains(name target: String, in g: ModuleDependencyGraph) -> Bool {
    switch key.designator {
    case .topLevel(let name),
      .dynamicLookup(let name):
      return name.lookup(in: g) == target
    case .externalDepend, .sourceFileProvide:
      return false
    case .nominal(let context),
      .potentialMember(let context):
      return context.lookup(in: g).range(of: target) != nil
    case .member(let context, let name):
      return context.lookup(in: g).range(of: target) != nil || name.lookup(in: g) == target
    }
  }
}

// MARK: - Post-compile helpers

extension Driver {
  func postCompileOutputs() throws -> [TypedVirtualPath] {
    try #require(incrementalCompilationState).jobsAfterCompiles.flatMap { $0.outputs }
  }
}

// MARK: - TestDriver graph inspection / post-compile helpers

extension TestDriver {
  func withModuleDependencyGraph(_ fn: (ModuleDependencyGraph) throws -> Void) throws {
    try unwrap { try $0.withModuleDependencyGraph(fn) }
  }
  func verifyNoGraph() {
    #expect(incrementalCompilationState == nil)
  }
  func postCompileOutputs() throws -> [TypedVirtualPath] {
    try unwrap { try $0.postCompileOutputs() }
  }
}
