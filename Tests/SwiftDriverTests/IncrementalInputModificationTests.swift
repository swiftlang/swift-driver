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
struct IncrementalInputModificationTests: DiagVerifiable {

  @Test func optionsParsing() async throws {
    let h = try IncrementalTestHarness()
    let optionPairs:
      [(
        Option, (IncrementalCompilationState.IncrementalDependencyAndInputSetup) -> Bool
      )] = [
        (.driverAlwaysRebuildDependents, { $0.alwaysRebuildDependents }),
        (.driverShowIncremental, { $0.reporter != nil }),
        (.driverEmitFineGrainedDependencyDotFileAfterEveryImport, { $0.emitDependencyDotFileAfterEveryImport }),
        (.driverVerifyFineGrainedDependencyGraphAfterEveryImport, { $0.verifyDependencyGraphAfterEveryImport }),
      ]

    for (driverOption, stateOptionFn) in optionPairs {
      try await h.doABuild(
        "initial",
        checkDiagnostics: false,
        extraArguments: [driverOption.spelling],
        whenAutolinking: []
      ) {}

      var driver = try TestDriver(
        args: h.commonArgs + [
          driverOption.spelling
        ] + h.sdkArgumentsForTesting
      )
      _ = try await driver.planBuild()
      #expect(!driver.diagnosticEngine.hasErrors)
      let state = try #require(driver.incrementalCompilationState)
      #expect(stateOptionFn(state.info))
    }
  }

  /// Ensure that autolink output file goes with .o directory, to not prevent incremental
  /// omission of autolink job.
  @Test func autolinkOutputPath() async throws {
    let h = try IncrementalTestHarness()
    var env = ProcessEnv.block
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "//usr/bin/swift-autolink-extract"
    env["SWIFT_DRIVER_DSYMUTIL_EXEC"] = "//usr/bin/dsymutil"

    var driver = try TestDriver(
      args: h.commonArgs + [
        "-emit-library", "-target", "x86_64-unknown-linux",
      ],
      env: env
    )

    let jobs = try await driver.planBuild()
    let job = try #require(jobs.filter { $0.kind == .autolinkExtract }.first)

    let outputs = job.outputs.filter { $0.type == .autolink }
    #expect(outputs.count == 1)

    let expected = try AbsolutePath(validating: "\(h.module).autolink", relativeTo: h.derivedDataPath)
    #expect(outputs.first!.file.absolutePath == expected)
  }

  /// Null planning should not return an empty compile job for compatibility reason.
  /// `swift-build` wraps the jobs returned by swift-driver in `Executor` so returning
  /// an empty list of compile job will break build system.
  @Test func nullPlanningCompatibility() async throws {
    let h = try IncrementalTestHarness()
    let extraArguments = ["-experimental-emit-module-separately", "-emit-module"]
    var driver = try TestDriver(
      args: h.commonArgs + extraArguments + h.sdkArgumentsForTesting
    )
    let initialJobs = try await driver.planBuild()
    #expect(initialJobs.contains { $0.kind == .emitModule })
    try await driver.run(jobs: initialJobs)

    // Plan the build again without touching any file. This should be a null build but for
    // compatibility reason, planBuild() should return all the jobs and supported build system
    // will query incremental state for the actual jobs need to be executed.
    let replanJobs = try await driver.planBuild()
    #expect(
      !replanJobs.filter { $0.kind == .compile }.isEmpty,
      "more than one compile job needs to be planned"
    )
    #expect(replanJobs.contains { $0.kind == .emitModule })
  }

  @Test func addingInput() async throws {
    let h = try IncrementalTestHarness()
    try await h.runAddingInputTest(newInput: "another", defining: "nameInAnother")
  }

  /// In order to ensure robustness, test what happens under various conditions when a source
  /// file is removed.
  @Test(.requireObjCRuntime(), arguments: RemovalTestOptions.allCombinations)
  func removal(options: [RemovalTestOption]) async throws {
    let h = try IncrementalTestHarness()
    let newInput = "another"
    let topLevelName = "nameInAnother"
    try await h.runAddingInputTest(newInput: newInput, defining: topLevelName)

    let removeInputFromInvocation = options.contains(.removeInputFromInvocation)
    let removeSwiftDepsOfRemovedInput = options.contains(.removeSwiftDepsOfRemovedInput)
    let removedFileDependsOnChangedFileAndMainWasChanged = options.contains(.removedFileDependsOnChangedFile)

    _ = try await h.checkNonincrementalAfterRemoving(
      removedInput: newInput,
      defining: topLevelName,
      removeInputFromInvocation: removeInputFromInvocation,
      removeSwiftDepsOfRemovedInput: removeSwiftDepsOfRemovedInput
    )

    if removedFileDependsOnChangedFileAndMainWasChanged {
      h.replace(contentsOf: "main", with: "let foo = \"hello\"")
    }

    try await h.checkRestorationOfIncrementalityAfterRemoval(
      removedInput: newInput,
      defining: topLevelName,
      removeInputFromInvocation: removeInputFromInvocation,
      removeSwiftDepsOfRemovedInput: removeSwiftDepsOfRemovedInput,
      removedFileDependsOnChangedFileAndMainWasChanged: removedFileDependsOnChangedFileAndMainWasChanged
    )
  }

  // MARK: - Argument hashing tests

  /// Adding, removing, or changing the arguments of options which don't affect incremental
  /// builds should result in a null build.
  @Test func nullBuildArgumentsNotAffectingIncrementalBuilds() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(extraArguments: ["-driver-batch-size-limit", "5", "-debug-diagnostic-names"])
    let driver = try await h.checkNullBuild(extraArguments: [
      "-driver-batch-size-limit", "10", "-diagnostic-style", "swift",
    ])
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    #expect(mandatoryJobs.isEmpty)
  }

  /// If an option affects incremental builds, changing only the argument should trigger a
  /// full recompile.
  @Test func changingOptionArgumentLeadsToRecompile() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(extraArguments: ["-user-module-version", "1.0"])
    try await h.doABuild(
      "change user module version",
      checkDiagnostics: true,
      extraArguments: ["-user-module-version", "1.1"],
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      differentArgsPassed
      disablingIncrementalDifferentArgsPassed
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
  }

  /// Reordering options which affect incremental builds should trigger a full recompile.
  @Test func optionReorderingLeadsToRecompile() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(extraArguments: ["-warnings-as-errors", "-no-warnings-as-errors"])
    try await h.doABuild(
      "reorder options",
      checkDiagnostics: true,
      extraArguments: ["-no-warnings-as-errors", "-warnings-as-errors"],
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      differentArgsPassed
      disablingIncrementalDifferentArgsPassed
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
  }

  /// Reordering the arguments of an option which affect incremental builds should trigger a
  /// full recompile.
  @Test func argumentReorderingLeadsToRecompile() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(extraArguments: ["-Ifoo", "-Ibar"])
    try await h.doABuild(
      "reorder arguments",
      checkDiagnostics: true,
      extraArguments: ["-Ibar", "-Ifoo"],
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      differentArgsPassed
      disablingIncrementalDifferentArgsPassed
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
  }

  // A dependency has changed one of its inputs.
  @Test func implicitBuildChangedDependency() async throws {
    let h = try IncrementalTestHarness()
    let extraArguments = [
      "-I", h.explicitCDependenciesPath.nativePathString(escaped: false),
      "-I", h.explicitSwiftDependenciesPath.nativePathString(escaped: false),
    ]
    h.replace(contentsOf: "other", with: "import E;let bar = foo")
    try await h.buildInitialState(checkDiagnostics: false, extraArguments: extraArguments)
    h.touch(
      try AbsolutePath(validating: h.explicitSwiftDependenciesPath.appending(component: "E.swiftinterface").pathString)
    )
    h.replace(contentsOf: "other", with: "import E;let bar = foo + moduleEValue")

    try await h.doABuild(
      "update dependency (E) interface timestamp",
      checkDiagnostics: false,
      extraArguments: extraArguments,
      whenAutolinking: h.autolinkLifecycleExpectedDiags
    ) {
      readGraph
      schedulingNoncascading("main", "other")
      missing("main")
      missing("other")
      queuingInitial("main", "other")
      notSchedulingDependentsDoNotNeedCascading("main", "other")
      findingBatchingCompiling("main", "other")
    }
  }
}
