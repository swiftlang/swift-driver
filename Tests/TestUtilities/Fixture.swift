//===------------ Fixture.swift - Driver Testing Extensions --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic

/// Contains helpers for retrieving paths to fixtures under the
/// repo-local `TestInputs` directory.
public enum Fixture {
  /// Form a path to a file residing in the test fixtures directory under the
  /// root of this package.
  /// - Parameters:
  ///   - file: The name of the fixture file to search for.
  ///   - relativePath: The relative path of the subdirectory under
  ///                   `<package-root>/TestInputs`
  ///   - fileSystem: The filesystem on which to search.
  /// - Returns: A path to the fixture file if the resulting path exists on the
  ///            given file system. Else, returns `nil`.
  public static func fixturePath(
    at relativePath: RelativePath,
    for file: String,
    on fileSystem: FileSystem = localFileSystem
  ) throws -> AbsolutePath? {
    let packageRootPath: AbsolutePath =
        try AbsolutePath(validating: #file).parentDirectory.parentDirectory.parentDirectory
    let fixturePath =
        try AbsolutePath(validating: relativePath.pathString,
                         relativeTo: packageRootPath.appending(component: "TestInputs"))
              .appending(component: file)

    // Check that the fixture is really there.
    guard fileSystem.exists(fixturePath) else {
      return nil
    }

    return fixturePath
  }
}
