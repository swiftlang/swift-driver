//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
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

/// Tests for `-incremental-build-stats`: the flag that the driver passes on to
/// frontend jobs, and the two files that the driver writes into
/// `-stats-output-dir`.
@Suite(.enabled(if: sdkArgumentsAvailable, "SDK not available"))
struct IncrementalBuildStatisticsTests {

  // MARK: - Passing the flag on

  /// Every compile and emit-module job gets the flag, if the frontend
  /// supports it, and no job gets it otherwise.
  @Test func passesFlagToFrontendJobs() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-module-name", "main", "-c", "-emit-module",
      "-stats-output-dir", "/tmp/stats", "-incremental-build-stats",
      "foo.swift", "bar.swift",
    ])
    let jobs = try await driver.planBuild()
    let frontendJobs = jobs.filter { $0.kind == .compile || $0.kind == .emitModule }
    #expect(frontendJobs.contains { $0.kind == .compile })
    #expect(frontendJobs.contains { $0.kind == .emitModule })

    let supported = driver.isFrontendArgSupported(.incrementalBuildStats)
    for job in frontendJobs {
      #expect(job.commandLine.contains(.flag("-stats-output-dir")))
      #expect(job.commandLine.contains(.flag("-incremental-build-stats")) == supported)
    }
  }

  /// Without the flag, no job gets it.
  @Test func doesNotPassFlagUnlessRequested() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-module-name", "main", "-c", "-emit-module",
      "-stats-output-dir", "/tmp/stats", "foo.swift", "bar.swift",
    ])
    for job in try await driver.planBuild() {
      #expect(!job.commandLine.contains(.flag("-incremental-build-stats")))
    }
  }

  // MARK: - The files that the driver writes

  /// The first build writes one stats file and one report, and counts both
  /// inputs as compiled.
  @Test func initialBuild() async throws {
    let h = try IncrementalTestHarness()
    let statsDir = try makeStatsDirectory(in: h)
    try await h.buildInitialState(extraArguments: statsArguments(statsDir))

    let statistics = try DriverStatistics(in: statsDir, module: h.module)
    #expect(statistics.counters == [
      "Driver.NumSwiftInputs": 2,
      "Driver.NumFilesCompiled": 2,
      "Driver.NumFilesSkipped": 0,
      "Driver.NumCompileJobsRun": 1,
      "Driver.NumEmitModuleJobsRun": 0,
      "Driver.NumJobsFailed": 0,
      "Driver.IncrementalDisabled": 0,
    ])
    #expect(statistics.report.version == 1)
    #expect(statistics.report.module == h.module)
    #expect(statistics.report.incremental)
    #expect(statistics.compiledBaseNames == ["main.swift", "other.swift"])
    #expect(statistics.report.filesSkipped == 0)
    #expect(statistics.report.jobs.compile == 1)
    #expect(statistics.report.jobs.failed == 0)
  }

  /// A null build compiles nothing, and still writes both files.
  @Test func nullBuild() async throws {
    let h = try IncrementalTestHarness()
    let statsDir = try makeStatsDirectory(in: h)
    try await h.buildInitialState(extraArguments: statsArguments(statsDir))
    try emptyDirectory(statsDir)
    try await h.checkNullBuild(extraArguments: statsArguments(statsDir))

    let statistics = try DriverStatistics(in: statsDir, module: h.module)
    #expect(statistics.counters["Driver.NumFilesCompiled"] == 0)
    #expect(statistics.counters["Driver.NumFilesSkipped"] == 2)
    #expect(statistics.counters["Driver.NumCompileJobsRun"] == 0)
    #expect(statistics.compiledBaseNames.isEmpty)
  }

  /// Touching one input compiles only that input.
  @Test func touchingOneInput() async throws {
    let h = try IncrementalTestHarness()
    let statsDir = try makeStatsDirectory(in: h)
    try await h.buildInitialState(extraArguments: statsArguments(statsDir))
    try emptyDirectory(statsDir)
    try await h.checkNoPropagation(extraArguments: statsArguments(statsDir))

    let statistics = try DriverStatistics(in: statsDir, module: h.module)
    #expect(statistics.counters["Driver.NumFilesCompiled"] == 1)
    #expect(statistics.counters["Driver.NumFilesSkipped"] == 1)
    #expect(statistics.counters["Driver.NumCompileJobsRun"] == 1)
    #expect(statistics.compiledBaseNames == ["other.swift"])
  }
}

// MARK: - Helpers

private func statsArguments(_ statsDir: AbsolutePath) -> [String] {
  ["-stats-output-dir", statsDir.nativePathString(escaped: false), "-incremental-build-stats"]
}

private func makeStatsDirectory(in h: IncrementalTestHarness) throws -> AbsolutePath {
  let statsDir = h.tempDir.appending(component: "stats")
  try emptyDirectory(statsDir)
  return statsDir
}

private func emptyDirectory(_ dir: AbsolutePath) throws {
  try? localFileSystem.removeFileTree(dir)
  try localFileSystem.createDirectory(dir, recursive: true)
}

/// The stats file and the report that one driver run writes.
private struct DriverStatistics {
  let counters: [String: Int]
  let report: Report

  struct Report: Decodable {
    let version: Int
    let module: String
    let triple: String
    let incremental: Bool
    let filesCompiled: [String]
    let filesSkipped: Int
    let jobs: Jobs

    struct Jobs: Decodable {
      let compile: Int
      let emitModule: Int
      let failed: Int

      enum CodingKeys: String, CodingKey {
        case compile, failed
        case emitModule = "emit_module"
      }
    }

    enum CodingKeys: String, CodingKey {
      case version, module, triple, incremental, jobs
      case filesCompiled = "files_compiled"
      case filesSkipped = "files_skipped"
    }
  }

  /// The base names of the compiled files, sorted.
  var compiledBaseNames: [String] {
    report.filesCompiled.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted()
  }

  /// Reads the driver's two files from `directory`. Checks that there is
  /// exactly one of each, that the stats file is named as the frontend names
  /// its files, and that both names carry the same time and random number.
  init(in directory: AbsolutePath, module: String) throws {
    let names = try localFileSystem.getDirectoryContents(directory)
    let statsNames = names.filter { $0.hasPrefix("stats-") && $0.contains("-swift-driver-") }
    let reportNames = names.filter { $0.hasPrefix("incremental-build-") }
    try #require(statsNames.count == 1, "driver stats files: \(statsNames)")
    try #require(reportNames.count == 1, "reports: \(reportNames)")
    let statsFileName = statsNames[0]
    let reportFileName = reportNames[0]

    // stats-<time>-swift-driver-<module>-all-<triple>--<opt>-<random>-incremental.json
    let s = statsFileName.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    try #require(s.count == 11, "\(statsFileName)")
    #expect(s[0] == "stats" && s[2] == "swift" && s[3] == "driver")
    #expect(s[4] == module && s[5] == "all" && s[7] == "" && s[8] == "Onone")
    #expect(s[10] == "incremental.json")

    // incremental-build-<time>-<module>-<triple>-<random>.json
    let r = reportFileName.split(separator: "-").map(String.init)
    try #require(r.count == 6, "\(reportFileName)")
    #expect(r[3] == module)
    #expect(UInt64(s[1]) != nil && s[1] == r[2])
    #expect(s[6] == r[4])
    #expect(UInt32(s[9]) != nil && "\(s[9]).json" == r[5])

    let statsBytes = try localFileSystem.readFileContents(directory.appending(component: statsFileName))
    counters = try JSONDecoder().decode([String: Int].self, from: Data(statsBytes.contents))
    let reportBytes = try localFileSystem.readFileContents(directory.appending(component: reportFileName))
    report = try JSONDecoder().decode(Report.self, from: Data(reportBytes.contents))
  }
}
