//===--------------- BuildRecordInfo.swift --------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import class Foundation.JSONDecoder

import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import struct TSCBasic.ProcessResult
import struct TSCBasic.SHA256

import SwiftOptions
import class Dispatch.DispatchQueue

/// Holds information required to read and write the build record (aka
/// compilation record).
///
/// This info is always written, but only read for incremental compilation.
@_spi(Testing) public final class BuildRecordInfo {
  /// A pair of a `Job` and the `ProcessResult` corresponding to the outcome of
  /// its execution during this compilation session.
  struct JobResult {
    /// The job that was executed.
    var job: Job
    /// The result of executing the associated `job`.
    var result: ProcessResult

    init(_ j: Job, _ result: ProcessResult) {
      self.job = j
      self.result = result
    }
  }

  let buildRecordPath: VirtualPath
  let fileSystem: FileSystem
  let currentArgsHash: String
  @_spi(Testing) public let actualSwiftVersion: String
  @_spi(Testing) public let timeBeforeFirstJob: TimePoint
  let diagnosticEngine: DiagnosticsEngine
  let compilationInputModificationDates: [TypedVirtualPath: TimePoint]
  private var explicitModuleDependencyGraph: InterModuleDependencyGraph? = nil

  private var finishedJobResults = [JobResult]()
  // A confinement queue that protects concurrent access to the
  // `finishedJobResults` array.
  // FIXME: Use an actor when possible.
  private let confinementQueue = DispatchQueue(label: "com.apple.swift-driver.jobresults")

  @_spi(Testing) public init(
    buildRecordPath: VirtualPath,
    fileSystem: FileSystem,
    currentArgsHash: String,
    actualSwiftVersion: String,
    timeBeforeFirstJob: TimePoint,
    diagnosticEngine: DiagnosticsEngine,
    compilationInputModificationDates: [TypedVirtualPath: TimePoint])
  {
    self.buildRecordPath = buildRecordPath
    self.fileSystem = fileSystem
    self.currentArgsHash = currentArgsHash
    self.actualSwiftVersion = actualSwiftVersion
    self.timeBeforeFirstJob = timeBeforeFirstJob
    self.diagnosticEngine = diagnosticEngine
    self.compilationInputModificationDates = compilationInputModificationDates
  }

  convenience init?(
    actualSwiftVersion: String,
    compilerOutputType: FileType?,
    workingDirectory: AbsolutePath?,
    diagnosticEngine: DiagnosticsEngine,
    fileSystem: FileSystem,
    moduleOutputInfo: ModuleOutputInfo,
    outputFileMap: OutputFileMap?,
    incremental: Bool,
    parsedOptions: ParsedOptions,
    recordedInputModificationDates: [TypedVirtualPath: TimePoint]
  ) {
    // Cannot write a buildRecord without a path.
    guard let buildRecordPath = try? Self.computeBuildRecordPath(
            outputFileMap: outputFileMap,
            incremental: incremental,
            compilerOutputType: compilerOutputType,
            workingDirectory: workingDirectory,
            diagnosticEngine: diagnosticEngine)
    else {
      return nil
    }
    let currentArgsHash = Self.computeArgsHash(parsedOptions)
    let compilationInputModificationDates =
      recordedInputModificationDates.filter { input, _ in
        input.type.isPartOfSwiftCompilation
      }

    self.init(
      buildRecordPath: buildRecordPath,
      fileSystem: fileSystem,
      currentArgsHash: currentArgsHash,
      actualSwiftVersion: actualSwiftVersion,
      timeBeforeFirstJob: .now(),
      diagnosticEngine: diagnosticEngine,
      compilationInputModificationDates: compilationInputModificationDates)
   }

  private static func computeArgsHash(_ parsedOptionsArg: ParsedOptions
  ) -> String {
    var parsedOptions = parsedOptionsArg
    let hashInput = parsedOptions
      .filter { $0.option.affectsIncrementalBuild && $0.option.kind != .input}
      .map { $0.description } // The description includes the spelling of the option itself and, if present, its argument(s).
      .joined()
    return SHA256().hash(hashInput).hexadecimalRepresentation
  }

  /// Determine the input and output path for the build record
  private static func computeBuildRecordPath(
    outputFileMap: OutputFileMap?,
    incremental: Bool,
    compilerOutputType: FileType?,
    workingDirectory: AbsolutePath?,
    diagnosticEngine: DiagnosticsEngine
  ) throws -> VirtualPath? {
    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard let ofm = outputFileMap else {
      return nil
    }
    guard let partialBuildRecordPath =
            try ofm.existingOutputForSingleInput(outputType: .swiftDeps)
    else {
      if incremental {
        diagnosticEngine.emit(.warning_incremental_requires_build_record_entry)
      }
      return nil
    }
    return workingDirectory
      .map(VirtualPath.lookup(partialBuildRecordPath).resolvedRelativePath(base:))
      ?? VirtualPath.lookup(partialBuildRecordPath)
  }

  /// Write out the build record.
  ///
  /// - Parameters:
  ///   - jobs: All compilation jobs formed during this build.
  ///   - skippedInputs: All primary inputs that were not compiled because the
  ///                    incremental build plan determined they could be
  ///                    skipped.
  @_spi(Testing) public func buildRecord(_ jobs: [Job], _ skippedInputs: Set<TypedVirtualPath>?) -> BuildRecord {
    return self.confinementQueue.sync {
      BuildRecord(
        jobs: jobs,
        finishedJobResults: finishedJobResults,
        skippedInputs: skippedInputs,
        compilationInputModificationDates: compilationInputModificationDates,
        actualSwiftVersion: actualSwiftVersion,
        argsHash: currentArgsHash,
        timeBeforeFirstJob: timeBeforeFirstJob,
        timeAfterLastJob: .now())
    }
  }

  func removeBuildRecord() {
    guard let absPath = buildRecordPath.absolutePath else {
      return
    }
    try? fileSystem.removeFileTree(absPath)
  }

  func jobFinished(job: Job, result: ProcessResult) {
    self.confinementQueue.sync {
      finishedJobResults.append(JobResult(job, result))
    }
  }

  /// A build-record-relative path to the location of a serialized copy of the
  /// driver's dependency graph.
  ///
  /// FIXME: This is a little ridiculous. We could probably just replace the
  /// build record outright with a serialized format.
  @_spi(Testing) public var dependencyGraphPath: VirtualPath {
    let filename = buildRecordPath.basenameWithoutExt
    return buildRecordPath
      .parentDirectory
      .appending(component: filename + ".priors")
  }

  /// A build-record-relative path to the location of a serialized copy of the
  /// driver's inter-module dependency graph.
  var dependencyScanSerializedResultPath: VirtualPath {
    let filename = buildRecordPath.basenameWithoutExt
    return buildRecordPath
      .parentDirectory
      .appending(component: filename + ".swiftmoduledeps")
  }

  /// Directory to emit dot files into
  var dotFileDirectory: VirtualPath {
    buildRecordPath.parentDirectory
  }
}
