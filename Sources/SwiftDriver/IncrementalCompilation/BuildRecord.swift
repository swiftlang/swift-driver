//===--------------- BuildRecord.swift - Swift Input File Info Map -------===//
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

import class TSCBasic.DiagnosticsEngine
import struct TSCBasic.AbsolutePath
import struct TSCBasic.Diagnostic

/// Holds the info about inputs needed to plan incremenal compilation
/// A.k.a. BuildRecord was the legacy name
public struct BuildRecord {
  public let swiftVersion: String
  /// When testing, the argsHash may be missing from the build record
  public let argsHash: String
  /// Next compile, will compare an input mod time against the start time of the previous build
  public let buildStartTime: TimePoint
  /// Next compile, will compare an output mod time against the end time of the previous build
  public let buildEndTime: TimePoint
  /// The date is the modification time of the main input file the last time the driver ran
  public let inputInfos: [VirtualPath: InputInfo]

  public init(argsHash: String,
              swiftVersion: String,
              buildStartTime: TimePoint,
              buildEndTime: TimePoint,
              inputInfos: [VirtualPath: InputInfo]) {
    self.argsHash = argsHash
    self.swiftVersion = swiftVersion
    self.buildStartTime = buildStartTime
    self.buildEndTime = buildEndTime
    self.inputInfos = inputInfos
  }
}

// MARK: - Creating and writing a new map
extension BuildRecord {
  /// Create a new buildRecord for writing
  init(jobs: [Job],
       finishedJobResults: [BuildRecordInfo.JobResult],
       skippedInputs: Set<TypedVirtualPath>?,
       compilationInputModificationDates: [TypedVirtualPath: TimePoint],
       actualSwiftVersion: String,
       argsHash: String,
       timeBeforeFirstJob: TimePoint,
       timeAfterLastJob: TimePoint
  ) {
    let jobResultsByInput = Dictionary(uniqueKeysWithValues:
      finishedJobResults.flatMap { entry in
        entry.job.inputsGeneratingCode.map { ($0, entry.result) }
    })
    let inputInfosArray = compilationInputModificationDates
      .map { input, modDate -> (VirtualPath, InputInfo) in
        let status = InputInfo.Status(  wasSkipped: skippedInputs?.contains(input),
                                        jobResult: jobResultsByInput[input])
        return (input.file, InputInfo(status: status, previousModTime: modDate))
      }

    self.init(
      argsHash: argsHash,
      swiftVersion: actualSwiftVersion,
      buildStartTime: timeBeforeFirstJob,
      buildEndTime: timeAfterLastJob,
      inputInfos: Dictionary(uniqueKeysWithValues: inputInfosArray)
    )
  }
}
