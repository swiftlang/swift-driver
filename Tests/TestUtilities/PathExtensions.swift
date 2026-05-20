//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import TSCBasic
import SwiftDriver
import struct Foundation.URL
import class Foundation.Thread

extension AbsolutePath {
  public func nativePathString(escaped: Bool) -> String {
    return URL(fileURLWithPath: self.pathString).withUnsafeFileSystemRepresentation {
      let repr: String = String(cString: $0!)
      if escaped { return repr.replacingOccurrences(of: "\\", with: "\\\\") }
      return repr
    }
  }
}

extension VirtualPath {
  public func nativePathString(escaped: Bool) -> String {
    return URL(fileURLWithPath: self.description).withUnsafeFileSystemRepresentation {
      let repr: String = String(cString: $0!)
      if escaped { return repr.replacingOccurrences(of: "\\", with: "\\\\") }
      return repr
    }
  }
}

extension FileSystem {
  /// Touch a file so its modification time is guaranteed to change.
  ///
  /// If the file does not exist, creates it with empty content. Re-writes the
  /// file in a loop until `lastModificationTime` reports a value different from
  /// the original.
  /// This works on filesystems with coarse (1-second) timestamp granularity
  /// without requiring a fixed 1-second sleep.
  public func touch(_ path: AbsolutePath) throws {
    let file = VirtualPath.absolute(path)
    if !exists(path) {
      try writeFileContents(path, bytes: "")
    }
    let originalModTime = try lastModificationTime(for: file)

    let maxAttempts = 30
    let sleepInterval = 0.1  // seconds
    for _ in 0..<maxAttempts {
      let contents = try readFileContents(path)
      try writeFileContents(path) { $0.send(contents) }
      let newModTime = try lastModificationTime(for: file)
      if newModTime != originalModTime {
        return
      }
      Thread.sleep(forTimeInterval: sleepInterval)
    }
    preconditionFailure("Timed out waiting for modification time to change on \(path)")
  }
}
