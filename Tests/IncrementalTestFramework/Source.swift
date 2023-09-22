//===----------- PhasedSources.swift - Swift Testing --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

/// A source file to be used in an incremental test.
/// User edits can be simulated by using `AddOn`s.
public struct Source: Hashable, Comparable {

  /// E.g. "main" for "main.swift"
  public let name: String

  /// The code in the file, including any `AddOn` markers.
  let contents: String

  public init(named name: String, containing contents: String) {
    self.name = name
    self.contents = contents
  }

  /// Produce a Source from a Fixture
  /// - Parameters:
  ///   - named: E.g. "foo" for "foo.swift"
  ///   - relativePath: The relative path of the subdirectory under
  ///                   `<package-root>/TestInputs`
  ///   - fileSystem: The filesystem on which to search.
  /// - Returns: A Source with the given name and contents from the file
  public init?(named name: String,
              at relativePath: RelativePath,
              on fileSystem: FileSystem = localFileSystem) throws {
    guard let absPath = try Fixture.fixturePath(at: relativePath,
                                                for: "\(name).swift",
                                                on: fileSystem)
    else {
      return nil
    }
    let contents = try fileSystem.readFileContents(absPath).cString
    self.init(named: name, containing: contents)
  }

  public static func < (lhs: Source, rhs: Source) -> Bool {
    lhs.name < rhs.name
  }

}
