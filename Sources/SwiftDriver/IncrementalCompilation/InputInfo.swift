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
import Foundation
import TSCBasic

/*@_spi(Testing)*/ public struct InputInfo: Equatable {

  /*@_spi(Testing)*/ public let status: Status
  /*@_spi(Testing)*/ public let previousModTime: Date

  /*@_spi(Testing)*/ public init(status: Status, previousModTime: Date) {
    self.status = status
    self.previousModTime = previousModTime
  }
}

/*@_spi(Testing)*/ public extension InputInfo {
  enum Status: Equatable {
    case upToDate,
         needsCascadingBuild,
         needsNonCascadingBuild,
         newlyAdded
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

// MARK: - reading
public extension InputInfo {
  init?(tag: String, previousModTime: Date,
        failedToReadOutOfDateMap: (String) -> Void
  ) {
    guard let status = Status(identifier: tag) else {
      failedToReadOutOfDateMap("no previous build state in build record")
      return nil
    }
    self.init(status: status, previousModTime: previousModTime)
  }
}

// MARK: - writing
extension InputInfo {
  var tag: String { status.identifier }
}
