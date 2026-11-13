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

import SwiftOptions

import struct Foundation.Date
import class Foundation.JSONEncoder
import struct TSCBasic.ByteString
import struct TSCBasic.ProcessResult

extension Driver {
  /// For -incremental-build-stats, write the Swift files that this build
  /// compiled and skipped, and the jobs that ran, into -stats-output-dir, as a
  /// stats file of counts and as a report that lists the files compiled.
  ///
  /// Only the driver knows these: a skipped file runs no frontend job, and a
  /// job replayed from the compilation cache runs no frontend either.
  ///
  /// - Parameters:
  ///   - jobs: The jobs that the driver planned.
  ///   - skippedInputs: The inputs that the incremental build still skips when
  ///     it ends, or nil if the build isn't incremental, so every file
  ///     compiles.
  func writeIncrementalBuildStatistics(jobs: [Job], skippedInputs: Set<TypedVirtualPath>?) {
    var parsedOptions = self.parsedOptions
    guard parsedOptions.hasArgument(.incrementalBuildStats),
          let directory = parsedOptions.getLastArgument(.statsOutputDir)?.asSingle
    else {
      return
    }

    let inputs = inputFiles.filter { $0.type == .swift }
    let compiled = inputs.filter { !(skippedInputs?.contains($0) ?? false) }

    // The jobs that ran. swiftc and Swift Build report each finished job, with
    // its exit status, to the build record. Without a build record, the build
    // isn't incremental, so every planned job runs, and failures aren't known.
    let jobsRun: [(kind: Job.Kind, failed: Bool)] =
      buildRecordInfo?.finishedJobs.map { ($0.job.kind, !$0.result.exitedWithZero) }
      ?? jobs.map { ($0.kind, false) }
    let compileJobs = jobsRun.filter { $0.kind == .compile }.count
    let emitModuleJobs = jobsRun.filter { $0.kind == .emitModule }.count
    let failedJobs = jobsRun.filter { $0.failed }.count

    // The names follow the frontend's stats files, so that
    // utils/jobstats/jobstats.py reads the stats file as a driver job.
    let time = incrementalBuildStatisticsFileID.time
    let random = incrementalBuildStatisticsFileID.random
    let module = Self.statsFileNameComponent(moduleOutputInfo.name)
    let triple = Self.statsFileNameComponent(targetTriple.triple)
    let optimization: String
    switch parsedOptions.getLast(in: .O)?.option {
    case .O?, .Ounchecked?: optimization = "O"
    case .Osize?: optimization = "Osize"
    default: optimization = "Onone"
    }
    let statsFileName =
      "stats-\(time)-swift-driver-\(module)-all-\(triple)--\(optimization)-\(random)-incremental.json"
    let reportFileName = "incremental-build-\(time)-\(module)-\(triple)-\(random).json"

    let counters: KeyValuePairs = [
      "Driver.NumSwiftInputs": inputs.count,
      "Driver.NumFilesCompiled": compiled.count,
      "Driver.NumFilesSkipped": inputs.count - compiled.count,
      "Driver.NumCompileJobsRun": compileJobs,
      "Driver.NumEmitModuleJobsRun": emitModuleJobs,
      "Driver.NumJobsFailed": failedJobs,
      "Driver.IncrementalDisabled": skippedInputs == nil ? 1 : 0,
    ]
    let stats = "{\n"
      + counters.map { "\t\"\($0.key)\": \($0.value)" }.joined(separator: ",\n")
      + "\n}\n"

    let base = workingDirectory ?? fileSystem.currentWorkingDirectory
    let report = IncrementalBuildReport(
      module: moduleOutputInfo.name,
      triple: targetTriple.triple,
      incremental: skippedInputs != nil,
      filesCompiled: compiled.map { input in
        base.map { input.file.resolvedRelativePath(base: $0).name } ?? input.file.name
      },
      filesSkipped: inputs.count - compiled.count,
      jobs: .init(compile: compileJobs, emitModule: emitModuleJobs, failed: failedJobs))

    do {
      let encoder = JSONEncoder()
#if os(Linux) || os(Android)
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
#else
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
#endif
      let directoryPath = try VirtualPath(path: directory)
      try fileSystem.writeFileContents(
        directoryPath.appending(component: statsFileName),
        bytes: ByteString(encodingAsUTF8: stats), atomically: true)
      var reportData = try encoder.encode(report)
      reportData.append(UInt8(ascii: "\n"))
      try fileSystem.writeFileContents(
        directoryPath.appending(component: reportFileName),
        bytes: ByteString(reportData), atomically: true)
    } catch {
      diagnosticEngine.emit(
        .warning("could not write the incremental build statistics: \(error.localizedDescription)"))
    }
  }

  /// A name as the frontend's stats files spell it: letters, digits, and
  /// periods, with an underscore for anything else.
  private static func statsFileNameComponent(_ name: String) -> String {
    String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") ? $0 : "_" })
  }
}

/// The report that -incremental-build-stats writes for each driver run.
private struct IncrementalBuildReport: Encodable {
  let version = 1
  let module: String
  let triple: String
  let incremental: Bool
  let filesCompiled: [String]
  let filesSkipped: Int
  let jobs: Jobs

  /// The jobs that ran, including jobs replayed from the compilation cache.
  struct Jobs: Encodable {
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

private extension ProcessResult {
  var exitedWithZero: Bool {
    if case .terminated(code: 0) = exitStatus {
      return true
    }
    return false
  }
}

/// The time and random number in the names of a driver's statistics files.
///
/// They're fixed when the driver is created, so that each write replaces the
/// last one. Under Swift Build, the driver writes twice: when Swift Build plans
/// the build (from the `defer` in `Driver.run(jobs:)`, because Swift Build's
/// executor only records the jobs), and when the target's build ends.
struct IncrementalBuildStatisticsFileID {
  /// When the driver was created, in microseconds since the epoch.
  let time = UInt64(Date().timeIntervalSince1970 * 1_000_000)
  let random = UInt32.random(in: .min ... .max)
}
