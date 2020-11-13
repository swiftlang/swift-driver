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

public struct InputInfo: Equatable {

  let status: Status
  let previousModTime: Date

  public init(status: Status, previousModTime: Date) {
    self.status = status
    self.previousModTime = previousModTime
  }
}

public extension InputInfo {
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
    case "": self = .upToDate
    case "!dirty": self = .needsCascadingBuild
    case "!private": self = .needsNonCascadingBuild
    default: return nil
    }
    assert(self.identifier == identifier, "Ensure reversibility")
  }

  init(tag: String) {
    // The Yams tag can be other values if there is no tag in the file
    self = Self(identifier: tag) ?? Self(identifier: "")!
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
  /// The status will be read for the nextr driver invocaiton and will control the scheduling of that job.
  /// `upToDate` means only that the file was up to date when the build record was written.
  init( wasSkipped: Bool?, jobResult: ProcessResult? ) {
    if let exitStatus = jobResult?.exitStatus,
       case let .terminated(exitCode) = exitStatus,
       exitCode == 0 {
      self = .upToDate // File was compiled successfully.
      return
    }
    switch wasSkipped {
    case true?:
      // Incremental compilation decided to skip this file.
      self = .upToDate
    case false?:
      // Incremental compilation decided to compile this file, but the
      // compilation was not successful.
      self = .needsNonCascadingBuild
    case nil:
      // The driver was not run incrementally, and the compilation was
      // not sucessful.
      // TODO: Look for a better heuristic for these last two cases.
      self = .needsCascadingBuild
    }
  }
}

// MARK: - reading
public extension InputInfo {
  init(tag: String, previousModTime: Date) {
    self.init(status: Status(tag: tag), previousModTime: previousModTime)
  }
}

// MARK: - writing
extension InputInfo {
  var tag: String { status.identifier }
}
