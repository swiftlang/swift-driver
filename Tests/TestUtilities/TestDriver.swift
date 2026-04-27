//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import Foundation
@_spi(Testing) @preconcurrency import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TSCBasic

/// Whether to print diagnostics to stderr during test runs.
/// Set `SWIFT_DRIVER_TEST_VERBOSE=1` in the environment to enable.
public let verboseTestOutput = ProcessEnv.block["SWIFT_DRIVER_TEST_VERBOSE"] != nil

/// Diagnostic handler that prints to stderr when `SWIFT_DRIVER_TEST_VERBOSE` is set.
public func testDiagnosticsHandler(_ diag: Diagnostic) {
  guard verboseTestOutput else { return }
  var stream = StderrOutputStream()
  print(diag, to: &stream)
}

private struct StderrOutputStream: TextOutputStream {
  mutating func write(_ string: String) {
    FileHandle.standardError.write(Data(string.utf8))
  }
}

/// Async-safe wrapper around `Driver` for use in Swift Testing tests.
///
/// `Driver.run(jobs:)` blocks the calling thread inside an opaque C
/// `engine.build()` call. When Swift Testing runs tests concurrently,
/// each blocking call starves the cooperative thread pool, causing
/// deadlocks. `TestDriver` solves this by dispatching blocking work
/// to a dedicated GCD queue, yielding the cooperative thread at `await`.
///
/// Usage:
/// ```swift
/// var driver = try TestDriver(args: ["swiftc", "foo.swift"])
/// let jobs = try await driver.planBuild()
/// try await driver.run(jobs: jobs)
/// ```
package struct TestDriver {
  private var driver: Driver

  /// Create a test driver with the given arguments.
  package init(
    args: [String],
    env: ProcessEnvironmentBlock = ProcessEnv.block,
    diagnosticsEngine: DiagnosticsEngine? = nil,
    executor: DriverExecutor? = nil,
    fileSystem: FileSystem? = nil,
    integratedDriver: Bool = true,
    interModuleDependencyOracle: InterModuleDependencyOracle? = nil
  ) throws {
    let fs = fileSystem ?? localFileSystem
    let diags = diagnosticsEngine ?? DiagnosticsEngine(handlers: [testDiagnosticsHandler])
    let exec = try executor ?? SwiftDriverExecutor(
      diagnosticsEngine: diags,
      processSet: ProcessSet(),
      fileSystem: fs,
      env: env)
    self.driver = try Driver(
      args: args,
      envBlock: env,
      diagnosticsOutput: .engine(diags),
      fileSystem: fs,
      executor: exec,
      integratedDriver: integratedDriver,
      interModuleDependencyOracle: interModuleDependencyOracle)
  }

  // MARK: - Async wrappers

  /// Plan the build, returning the list of jobs.
  ///
  /// Although `planBuild` is fast and doesn't spawn processes, making it
  /// `async` keeps the API uniform and future-proof.
  package mutating func planBuild() async throws -> [Job] {
    try driver.planBuild()
  }

  /// Execute the given jobs.
  ///
  /// Runs on a detached thread to avoid blocking `engine.build()` call.
  package mutating func run(jobs: [Job]) async throws {
    // Move driver out of self so we can pass it into the closure without
    // capturing self (a mutable struct can't be captured).
    nonisolated(unsafe) var localDriver = driver
    let localJobs = jobs
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      let thread = Thread {
        do {
          try localDriver.run(jobs: localJobs)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
      thread.start()
    }
    // Write back any state changes from the run.
    driver = localDriver
  }

  // MARK: - Driver property passthroughs

  package var targetTriple: Triple { driver.targetTriple }
  package var diagnosticEngine: DiagnosticsEngine { driver.diagnosticEngine }
  package var moduleOutputInfo: ModuleOutputInfo { driver.moduleOutputInfo }
  package var debugInfo: DebugInfo { driver.debugInfo }
  package var incrementalCompilationState: IncrementalCompilationState? { driver.incrementalCompilationState }
  package var intermoduleDependencyGraph: InterModuleDependencyGraph? { driver.intermoduleDependencyGraph }
  package var frontendTargetInfo: FrontendTargetInfo { driver.frontendTargetInfo }
  package var supportedFrontendFlags: Set<String> { driver.supportedFrontendFlags }
  package var supportedFrontendFeatures: Set<String> { driver.supportedFrontendFeatures }
  package var compilerMode: CompilerMode { driver.compilerMode }
  package var fileSystem: FileSystem { driver.fileSystem }
  package var toolchain: Toolchain { driver.toolchain }
  package var hostTriple: Triple { driver.hostTriple }
  package var inputFiles: [TypedVirtualPath] { driver.inputFiles }
  package var recordedInputMetadata: [TypedVirtualPath: FileMetadata] { driver.recordedInputMetadata }
  package var compilerOutputType: FileType? { driver.compilerOutputType }
  package var linkerOutputType: LinkOutputType? { driver.linkerOutputType }
  package var numThreads: Int { driver.numThreads }
  package var packageName: String? { driver.packageName }
  package var interModuleDependencyOracle: InterModuleDependencyOracle { driver.interModuleDependencyOracle }
  package var absoluteSDKPath: AbsolutePath? { driver.absoluteSDKPath }
  package var isAutolinkExtractJobNeeded: Bool {
    mutating get { driver.isAutolinkExtractJobNeeded }
  }

  package var lto: LTOKind? { driver.lto }
  package var numParallelJobs: Int? { driver.numParallelJobs }

  package var cas: SwiftScanCAS? {
    get { driver.cas }
    set { driver.cas = newValue }
  }

  package var allSourcesFileList: VirtualPath? {
    get { driver.allSourcesFileList }
    set { driver.allSourcesFileList = newValue }
  }

  // MARK: - Driver method passthroughs

  package func isFrontendArgSupported(_ option: Option) -> Bool {
    driver.isFrontendArgSupported(option)
  }

  package func isFeatureSupported(_ feature: Driver.KnownCompilerFeature) -> Bool {
    driver.isFeatureSupported(feature)
  }

  package func getSwiftScanLibPath() throws -> AbsolutePath? {
    try driver.getSwiftScanLibPath()
  }

  package func isExplicitMainModuleJob(job: Job) -> Bool {
    driver.isExplicitMainModuleJob(job: job)
  }

  package mutating func dependencyScannerInvocationCommand(
    forVariantModule: Bool = false
  ) throws -> ([TypedVirtualPath], [Job.ArgTemplate]) {
    try driver.dependencyScannerInvocationCommand(forVariantModule: forVariantModule)
  }

  package mutating func scanModuleDependencies(
    forVariantModule: Bool = false
  ) throws -> InterModuleDependencyGraph {
    try driver.scanModuleDependencies(forVariantModule: forVariantModule)
  }

  package mutating func dependencyScanningJob(
    forVariantModule: Bool = false
  ) throws -> Job {
    try driver.dependencyScanningJob(forVariantModule: forVariantModule)
  }

  package mutating func performDependencyScan(
    forVariantModule: Bool = false
  ) throws -> InterModuleDependencyGraph {
    try driver.performDependencyScan(forVariantModule: forVariantModule)
  }

  package mutating func generatePrebuiltModuleGenerationJobs(
    with inputMap: [String: [PrebuiltModuleInput]],
    into prebuiltModuleDir: AbsolutePath,
    exhaustive: Bool,
    dotGraphPath: AbsolutePath? = nil,
    currentABIDir: AbsolutePath? = nil,
    baselineABIDir: AbsolutePath? = nil
  ) throws -> ([Job], [Job]) {
    try driver.generatePrebuiltModuleGenerationJobs(
      with: inputMap, into: prebuiltModuleDir, exhaustive: exhaustive,
      dotGraphPath: dotGraphPath, currentABIDir: currentABIDir,
      baselineABIDir: baselineABIDir)
  }

  package func querySupportedArgumentsForTest() throws -> Set<String>? {
    try driver.querySupportedArgumentsForTest()
  }

  /// For tests that need the SDK path arguments.
  package static func sdkArgumentsForTesting() throws -> [String]? {
    try Driver.sdkArgumentsForTesting()
  }

  // MARK: - Escape hatch

  /// Direct access to the underlying `Driver` for properties or methods
  /// not yet exposed on `TestDriver`.
  package mutating func unwrap<T>(_ body: (inout Driver) throws -> T) rethrows -> T {
    try body(&driver)
  }

  /// Non-mutating variant for read-only access.
  package func unwrap<T>(_ body: (Driver) throws -> T) rethrows -> T {
    try body(driver)
  }
}
