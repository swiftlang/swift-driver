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
import TSCBasic
import Testing

@_spi(Testing) import SwiftDriver

@Suite struct LastModificationTimeTests {
  private func foundationModTime(_ path: AbsolutePath) throws -> TimeInterval {
    let attributes = try FileManager.default.attributesOfItem(atPath: path.pathString)
    let date = try #require(attributes[.modificationDate] as? Date)
    return date.timeIntervalSince1970
  }

  private func interval(_ timePoint: TimePoint) -> TimeInterval {
    TimeInterval(timePoint.seconds) + TimeInterval(timePoint.nanoseconds) / 1_000_000_000
  }

  /// The modification time must retain sub-second precision. Truncating to whole seconds makes
  /// "is this output newer than this input?" checks ambiguous for files written within the same
  /// second, which caused emit-module jobs to be spuriously rescheduled on non-Darwin platforms.
  @Test(.disabled(if: isWindows, "Windows still derives modification times from Foundation with whole-second precision"))
  func retainsSubSecondPrecision() throws {
    try withTemporaryDirectory(removeTreeOnDeinit: true) { dir in
      let file = dir.appending(component: "file.swift")
      try localFileSystem.writeFileContents(file, bytes: "")

      let expected = try foundationModTime(file)
      let actual = interval(try localFileSystem.lastModificationTime(for: .absolute(file)))
      #expect(abs(actual - expected) < 0.001, "expected \(expected), got \(actual)")
    }
  }

  @Test(.disabled(if: isWindows, "Symbolic links require additional privileges on Windows"))
  func followsSymbolicLinks() throws {
    try withTemporaryDirectory(removeTreeOnDeinit: true) { dir in
      let target = dir.appending(component: "target.swift")
      let link = dir.appending(component: "link.swift")
      try localFileSystem.writeFileContents(target, bytes: "")
      try localFileSystem.createSymbolicLink(link, pointingAt: target, relative: false)

      #expect(try localFileSystem.lastModificationTime(for: .absolute(link)) ==
              localFileSystem.lastModificationTime(for: .absolute(target)))
    }
  }
}

private let isWindows: Bool = {
  #if os(Windows)
  return true
  #else
  return false
  #endif
}()
