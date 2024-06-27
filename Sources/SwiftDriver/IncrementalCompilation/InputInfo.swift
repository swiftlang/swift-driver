//===--------------- InputInfo.swift - Swift Input File Info --------------===//
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

import struct TSCBasic.ProcessResult

/// Contains information about the current status of an input to the incremental
/// build.
///
/// This is as opposed to information derived from the build record, which
/// from our perspective only records informatiuon about inputs that were known
/// to the driver in the past.
/*@_spi(Testing)*/ public struct InputInfo: Equatable {

  /// The current status of the input file.
  /*@_spi(Testing)*/ public let status: Status
  /// The last known modification time of this input.
  /*@_spi(Testing)*/ public let previousModTime: TimePoint

  /*@_spi(Testing)*/ public init(status: Status, previousModTime: TimePoint) {
    self.status = status
    self.previousModTime = previousModTime
  }
}

/*@_spi(Testing)*/ public extension InputInfo {
  /// The status of an input known to the driver. These are used to affect
  /// the scheduling decisions made during an incremental build.
  ///
  /// - Note: The order of cases matters. They are ordered from least to
  ///         greatest impact on the incremental build schedule.
  enum Status: Equatable {
    /// The input to this job is up to date.
    case upToDate
    /// The input to this job has changed in a way that requires this job to
    /// be rerun, but not in such a way that it requires a cascading rebuild.
    case needsNonCascadingBuild
    /// The input to this job has changed in a way that requires this job to
    /// be rerun, and in such a way that all jobs dependent upon this one
    /// must be scheduled as well.
    case needsCascadingBuild
    /// The input to this job was not known to the driver when it was last
    /// run.
    case newlyAdded
  }
}

// MARK: - reading
extension InputInfo.Status {
  public init?(identifier: String) {
    switch identifier {
    case "":
      self = .upToDate
    case "!dirty":
      self = .needsCascadingBuild
    case "!private":
      self = .needsNonCascadingBuild
    default:
      // See Tag.swift in YAMS
      // This is what an absent tag looks like.
      if identifier.hasPrefix("tag:yaml.org") {
        self = .upToDate
        return
      }
      return nil
    }
    assert(self.identifier == identifier, "Ensure reversibility")
  }
}

// MARK: - writing
extension InputInfo.Status {
  /// The identifier is used for the tag in the value of the input in the BuildRecord
  var identifier: String {
    switch self {
    case .upToDate:
      return ""
    case .needsCascadingBuild, .newlyAdded:
      return "!dirty"
    case .needsNonCascadingBuild:
      return "!private"
    }
  }

  /// Construct a status to write at the end of the compilation.
  /// The status will be read for the next driver invocation and will control the scheduling of that job.
  /// `upToDate` means only that the file was up to date when the build record was written.
  init( wasSkipped: Bool?, jobResult: ProcessResult? ) {
    if let _ = jobResult, wasSkipped == true {
      fatalError("Skipped job cannot have finished")
    }
    let ok = wasSkipped == true || jobResult?.finishedWithoutError == true
    let incrementally = wasSkipped != nil
    switch (ok, incrementally) {
    case (true,      _): self = .upToDate
    case (false,  true): self = .needsNonCascadingBuild
    case (false, false): self = .needsCascadingBuild
    }
  }
}

fileprivate extension ProcessResult {
  var finishedWithoutError: Bool {
    if case let .terminated(exitCode) = exitStatus, exitCode == 0 {
      return true
    }
    return false
  }
}
