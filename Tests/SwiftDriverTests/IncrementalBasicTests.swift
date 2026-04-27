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
struct IncrementalBasicTests: DiagVerifiable {

  @Test func incrementalDiagnostics() async throws {
    let h = try IncrementalTestHarness()
    try await h.runIncrementalPipeline(checkDiagnostics: true)
  }

  @Test func incremental() async throws {
    let h = try IncrementalTestHarness()
    try await h.runIncrementalPipeline(checkDiagnostics: false)
  }

  @Test func dependencyDotFiles() async throws {
    let h = try IncrementalTestHarness()
    h.expectNoDotFiles()
    try await h.buildInitialState(extraArguments: ["-driver-emit-fine-grained-dependency-dot-file-after-every-import"])
    h.expect(dotFilesFor: [
      "main.swift",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swift",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
    ])
  }

  @Test func dependencyDotFilesCross() async throws {
    let h = try IncrementalTestHarness()
    h.expectNoDotFiles()
    try await h.buildInitialState(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import"
    ])
    h.removeDotFiles()
    try await h.checkNoPropagation(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import"
    ])
    h.expect(dotFilesFor: [
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swift",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
    ])
  }

  /// Ensure that if an output of post-compile job is missing, the job gets rerun.
  @Test func incrementalPostCompileJob() async throws {
    let h = try IncrementalTestHarness()
    let driver = try await h.buildInitialState(checkDiagnostics: true)
    for postCompileOutput in try driver.postCompileOutputs() {
      let absPostCompileOutput = try #require(postCompileOutput.file.absolutePath)
      try localFileSystem.removeFileTree(absPostCompileOutput)
      #expect(!localFileSystem.exists(absPostCompileOutput))
      try await h.checkNullBuild()
      #expect(localFileSystem.exists(absPostCompileOutput))
    }
  }

  @Test func fileMapMissingMainEntry() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(checkDiagnostics: true)
    OutputFileMapCreator.write(
      module: h.module,
      inputPaths: h.inputPathsAndContents.map { $0.0 },
      derivedData: h.derivedDataPath,
      to: h.OFM,
      excludeMainEntry: true
    )
    try await h.doABuild(
      "output file map missing main entry",
      checkDiagnostics: true,
      extraArguments: [],
      whenAutolinking: []
    ) {
      missingMainDependencyEntry
      disablingIncremental
      foundBatchableJobs(2)
      formingOneBatch
      addingToBatchThenForming("main", "other")
      compiling("main", "other")
      startingLinking
      finishedLinking
    }
  }

  @Test func fileMapMissingMainEntryWMO() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(checkDiagnostics: true)
    OutputFileMapCreator.write(
      module: h.module,
      inputPaths: h.inputPathsAndContents.map { $0.0 },
      derivedData: h.derivedDataPath,
      to: h.OFM,
      excludeMainEntry: true
    )
    let args =
      [
        "swiftc",
        "-module-name", h.module,
        "-o", h.derivedDataPath.appending(component: h.module + ".o").pathString,
        "-output-file-map", h.OFM.pathString,
        "-incremental",
        "-whole-module-optimization",
        "-no-color-diagnostics",
      ] + h.inputPathsAndContents.map { $0.0.pathString }.sorted() + h.sdkArgumentsForTesting
    _ = try await h.doABuild(whenAutolinking: [], expecting: disabledForWMO, arguments: args)
  }

  @Test func alwaysRebuildDependents() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(checkDiagnostics: true)
    try await h.checkAlwaysRebuildDependents(checkDiagnostics: true)
  }

  /// Ensure that the mod date of the input comes back exactly the same via the build-record.
  /// Otherwise the up-to-date calculation in `IncrementalCompilationState` will fail.
  @Test func buildRecordDateAccuracy() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState()
    for _ in 1...10 {
      try await h.checkNullBuild(checkDiagnostics: true)
    }
  }

  @Test func nullBuildNoEmitModule() async throws {
    let h = try IncrementalTestHarness()
    let extraArguments = ["-experimental-emit-module-separately", "-emit-module"]
    try await h.buildInitialState(extraArguments: extraArguments)
    let driver = try await h.checkNullBuild(extraArguments: extraArguments)
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    #expect(mandatoryJobs.isEmpty)
  }

  @Test func nullBuildNoVerify() async throws {
    let h = try IncrementalTestHarness()
    let extraArguments = [
      "-experimental-emit-module-separately", "-emit-module", "-emit-module-interface", "-enable-library-evolution",
      "-verify-emitted-module-interface",
    ]
    try await h.buildInitialState(extraArguments: extraArguments)
    let driver = try await h.checkNullBuild(extraArguments: extraArguments)
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    #expect(mandatoryJobs.isEmpty)
  }

  /// Source file timestamps updated but contents are the same, with file-hashing
  /// emit-module job should be skipped.
  @Test func nullBuildNoEmitModuleWithHashing() async throws {
    let h = try IncrementalTestHarness()
    let extraArguments = ["-experimental-emit-module-separately", "-emit-module", "-enable-incremental-file-hashing"]
    try await h.buildInitialState(extraArguments: extraArguments)
    try h.touch("main")
    try h.touch("other")
    h.touch(
      try AbsolutePath(validating: h.explicitSwiftDependenciesPath.appending(component: "E.swiftinterface").pathString)
    )
    let driver = try await h.doABuildWithoutExpectations(arguments: h.commonArgs + extraArguments + h.sdkArgumentsForTesting)
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    let mandatoryJobInputs = mandatoryJobs.flatMap { $0.inputs }.map { $0.file.basename }
    #expect(
      !mandatoryJobs.contains { $0.kind == .emitModule },
      "emit-module should be skipped when using hashes and content unchanged"
    )
    #expect(!mandatoryJobInputs.contains("main.swift"))
    #expect(!mandatoryJobInputs.contains("other.swift"))
  }

  /// Source file updated, emit-module job should not be skipped regardless of file-hashing.
  @Test func emitModuleWithHashingWhenContentChanges() async throws {
    let h = try IncrementalTestHarness()
    let extraArguments = ["-experimental-emit-module-separately", "-emit-module", "-enable-incremental-file-hashing"]
    try await h.buildInitialState(extraArguments: extraArguments)
    h.replace(contentsOf: "main", with: "let foo = 2")
    let driver = try await h.doABuildWithoutExpectations(arguments: h.commonArgs + extraArguments + h.sdkArgumentsForTesting)
    let mandatoryJobs = try #require(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    let mandatoryJobInputs = mandatoryJobs.flatMap { $0.inputs }.map { $0.file.basename }
    #expect(
      mandatoryJobs.contains { $0.kind == .emitModule },
      "emit-module should run when using hashes and content has changed"
    )
    #expect(mandatoryJobInputs.contains("main.swift"))
  }

  @Test func symlinkModification() async throws {
    let h = try IncrementalTestHarness()
    for (file, _) in h.inputPathsAndContents {
      try localFileSystem.createDirectory(h.tempDir.appending(component: "links"))
      let linkTarget = h.tempDir.appending(component: "links").appending(component: file.basename)
      try localFileSystem.move(from: file, to: linkTarget)
      try localFileSystem.removeFileTree(file)
      try localFileSystem.createSymbolicLink(file, pointingAt: linkTarget, relative: false)
    }
    try await h.buildInitialState()
    try await h.checkReactionToTouchingSymlinks(checkDiagnostics: true)
    try await h.checkReactionToTouchingSymlinkTargets(checkDiagnostics: true)
  }

  /// Ensure that the driver can detect and then recover from a priors version mismatch.
  @Test func priorsVersionDetectionAndRecovery() async throws {
    let h = try IncrementalTestHarness()
    try await h.buildInitialState(checkDiagnostics: true)
    let driver = try await h.checkNullBuild(checkDiagnostics: true)

    // Read the priors, change the minor version, and write it back out
    let outputFileMap = try #require(driver.incrementalCompilationState).info.outputFileMap
    let info = IncrementalCompilationState.IncrementalDependencyAndInputSetup
      .mock(outputFileMap: outputFileMap)
    let priorsModTime = try info.blockingConcurrentAccessOrMutation {
      () -> Date in
      let priorsWithOldVersion = try #require(
        try ModuleDependencyGraph.read(
          from: .absolute(h.priorsPath),
          info: info
        )
      )
      let priorsModTime = try localFileSystem.getFileInfo(h.priorsPath).modTime
      let incrementedVersion = ModuleDependencyGraph.serializedGraphVersion.withAlteredMinor
      try priorsWithOldVersion.write(
        to: .absolute(h.priorsPath),
        on: localFileSystem,
        buildRecord: priorsWithOldVersion.buildRecord,
        mockSerializedGraphVersion: incrementedVersion
      )
      return priorsModTime
    }
    try h.setModTime(of: .absolute(h.priorsPath), to: priorsModTime)

    try await h.checkReactionToObsoletePriors()
    try await h.checkNullBuild(checkDiagnostics: true)
  }
}
