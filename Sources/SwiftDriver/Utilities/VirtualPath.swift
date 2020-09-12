//===--------------- VirtualPath.swift - Swift Virtual Paths --------------===//
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
import TSCBasic
import Foundation

/// A virtual path.
public enum VirtualPath: Hashable {
  /// A relative path that has not been resolved based on the current working
  /// directory.
  case relative(RelativePath)

  /// An absolute path in the file system.
  case absolute(AbsolutePath)

  /// Standard input
  case standardInput

  /// Standard output
  case standardOutput

  /// A temporary file with the given name.
  case temporary(RelativePath)

  /// A temporary file with the given name and contents.
  case temporaryWithKnownContents(RelativePath, Data)

  /// A temporary file that holds a list of paths.
  case fileList(RelativePath, FileList)

  /// Form a virtual path which may be either absolute or relative.
  public init(path: String) throws {
    if let absolute = try? AbsolutePath(validating: path) {
      self = .absolute(absolute)
    } else {
      let relative = try RelativePath(validating: path)
      self = .relative(relative)
    }
  }

  /// The name of the path for presentation purposes.
  public var name: String { description }

  /// The extension of this path, for relative or absolute paths.
  public var `extension`: String? {
    switch self {
    case .relative(let path), .temporary(let path),
         .temporaryWithKnownContents(let path, _), .fileList(let path, _):
      return path.extension
    case .absolute(let path):
      return path.extension
    case .standardInput, .standardOutput:
      return nil
    }
  }

  /// Whether this virtual path is to a temporary.
  public var isTemporary: Bool {
    switch self {
    case .relative, .absolute, .standardInput, .standardOutput:
      return false
    case .temporary, .temporaryWithKnownContents, .fileList:
      return true
    }
  }

  public var absolutePath: AbsolutePath? {
    switch self {
    case let .absolute(absolutePath):
      return absolutePath
    case .relative, .temporary, .temporaryWithKnownContents, .fileList, .standardInput, .standardOutput:
      return nil
    }
  }

  /// Retrieve the basename of the path.
  public var basename: String {
    switch self {
    case .absolute(let path):
      return path.basename
    case .relative(let path), .temporary(let path), .temporaryWithKnownContents(let path, _), .fileList(let path, _):
      return path.basename
    case .standardInput, .standardOutput:
      return ""
    }
  }

  /// Retrieve the basename of the path without the extension.
  public var basenameWithoutExt: String {
    switch self {
    case .absolute(let path):
      return path.basenameWithoutExt
    case .relative(let path), .temporary(let path), .temporaryWithKnownContents(let path, _), .fileList(let path, _):
      return path.basenameWithoutExt
    case .standardInput, .standardOutput:
      return ""
    }
  }

  /// Retrieve the path to the parent directory.
  public var parentDirectory: VirtualPath {
    switch self {
    case .absolute(let path):
      return .absolute(path.parentDirectory)
    case .relative(let path):
      return .relative(RelativePath(path.dirname))
    case .temporary(let path), .temporaryWithKnownContents(let path, _):
      return .temporary(RelativePath(path.dirname))
    case .fileList(let path, _):
      return .temporary(RelativePath(path.dirname))
    case .standardInput, .standardOutput:
      assertionFailure("Can't get directory of stdin/stdout")
      return self
    }
  }

  /// Returns the virtual path with an additional literal component appended.
  ///
  /// This should not be used with `.standardInput` or `.standardOutput`.
  public func appending(component: String) -> VirtualPath {
    switch self {
    case .absolute(let path):
      return .absolute(path.appending(component: component))
    case .relative(let path):
      return .relative(path.appending(component: component))
    case .temporary(let path):
      return .temporary(path.appending(component: component))
    case let .temporaryWithKnownContents(path, contents):
      return .temporaryWithKnownContents(path.appending(component: component), contents)
    case .fileList(let path, let content):
      return .fileList(path.appending(component: component), content)
    case .standardInput, .standardOutput:
      assertionFailure("Can't append path component to standard in/out")
      return self
    }
  }

  /// Returns the virtual path with an additional suffix appended to base name.
  ///
  /// This should not be used with `.standardInput` or `.standardOutput`.
  public func appendingToBaseName(_ suffix: String) -> VirtualPath {
    switch self {
    case let .absolute(path):
      return .absolute(AbsolutePath(path.pathString + suffix))
    case let .relative(path):
      return .relative(RelativePath(path.pathString + suffix))
    case let .temporary(path):
      return .temporary(RelativePath(path.pathString + suffix))
    case let .temporaryWithKnownContents(path, contents):
      return .temporaryWithKnownContents(RelativePath(path.pathString + suffix), contents)
    case let .fileList(path, content):
      return .fileList(RelativePath(path.pathString + suffix), content)
    case .standardInput, .standardOutput:
      assertionFailure("Can't append path component to standard in/out")
      return self
    }
  }
}

extension VirtualPath: Codable {
  private enum CodingKeys: String, CodingKey {
    case relative, absolute, standardInput, standardOutput, temporary,
         temporaryWithKnownContents, fileList
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .relative(let a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .relative)
      try unkeyedContainer.encode(a1)
    case .absolute(let a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .absolute)
      try unkeyedContainer.encode(a1)
    case .standardInput:
      _ = container.nestedUnkeyedContainer(forKey: .standardInput)
    case .standardOutput:
      _ = container.nestedUnkeyedContainer(forKey: .standardOutput)
    case .temporary(let a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .temporary)
      try unkeyedContainer.encode(a1)
    case let .temporaryWithKnownContents(path, contents):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .temporaryWithKnownContents)
      try unkeyedContainer.encode(path)
      try unkeyedContainer.encode(contents)
    case .fileList(let path, let fileList):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .fileList)
      try unkeyedContainer.encode(path)
      try unkeyedContainer.encode(fileList)
    }
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard let key = values.allKeys.first(where: values.contains) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
    }
    switch key {
    case .relative:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(RelativePath.self)
      self = .relative(a1)
    case .absolute:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(AbsolutePath.self)
      self = .absolute(a1)
    case .standardInput:
      self = .standardInput
    case .standardOutput:
      self = .standardOutput
    case .temporary:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(RelativePath.self)
      self = .temporary(a1)
    case .temporaryWithKnownContents:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let path = try unkeyedValues.decode(RelativePath.self)
      let contents = try unkeyedValues.decode(Data.self)
      self = .temporaryWithKnownContents(path, contents)
    case .fileList:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let path = try unkeyedValues.decode(RelativePath.self)
      let fileList = try unkeyedValues.decode(FileList.self)
      self = .fileList(path, fileList)
    }
  }
}

/// A wrapper for easier decoding of absolute or relative VirtualPaths from strings.
struct TextualVirtualPath: Codable {
  var path: VirtualPath

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    path = try VirtualPath(path: container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch path {
    case .absolute(let path):
      try container.encode(path.pathString)
    case .relative(let path):
      try container.encode(path.pathString)
    case .temporary, .temporaryWithKnownContents, .standardInput,
         .standardOutput, .fileList:
      preconditionFailure("Path does not have a round-trippable textual representation")
    }
  }
}

extension VirtualPath: CustomStringConvertible {
  public var description: String {
    switch self {
    case .relative(let path):
      return path.pathString

    case .absolute(let path):
      return path.pathString

    case .standardInput, .standardOutput:
      return "-"

    case .temporary(let path), .temporaryWithKnownContents(let path, _),
         .fileList(let path, _):
      return path.pathString
    }
  }
}

extension VirtualPath {
  /// Replace the extension of the given path with a new one based on the
  /// specified file type.
  public func replacingExtension(with fileType: FileType) -> VirtualPath {
    switch self {
    case let .absolute(path):
      return .absolute(AbsolutePath(path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)))
    case let .relative(path):
      return .relative(RelativePath(path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)))
    case let .temporary(path):
      return .temporary(RelativePath(path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)))
    case let .temporaryWithKnownContents(path, contents):
      return .temporaryWithKnownContents(RelativePath(path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)), contents)
    case let .fileList(path, content):
      return .fileList(RelativePath(path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)), content)
    case .standardInput, .standardOutput:
      return self
    }
  }
}

private extension String {
  func withoutExt(_ ext: String?) -> String {
    if let ext = ext {
      return String(dropLast(ext.count + 1))
    } else {
      return self
    }
  }
}

enum FileSystemError: Swift.Error {
  case noCurrentWorkingDirectory
  case cannotResolveTempPath(RelativePath)
  case cannotResolveStandardInput
  case cannotResolveStandardOutput
}

extension TSCBasic.FileSystem {
  private func resolvingVirtualPath<T>(
    _ path: VirtualPath,
    apply f: (AbsolutePath) throws -> T
  ) throws -> T {
    switch path {
    case let .absolute(absPath):
      return try f(absPath)
    case let .relative(relPath):
      guard let cwd = currentWorkingDirectory else {
        throw FileSystemError.noCurrentWorkingDirectory
      }
      return try f(.init(cwd, relPath))
    case let .temporary(relPath), let .temporaryWithKnownContents(relPath, _),
         let .fileList(relPath, _):
      throw FileSystemError.cannotResolveTempPath(relPath)
    case .standardInput:
      throw FileSystemError.cannotResolveStandardInput
    case .standardOutput:
      throw FileSystemError.cannotResolveStandardOutput
    }
  }

  func readFileContents(_ path: VirtualPath) throws -> ByteString {
    try resolvingVirtualPath(path, apply: readFileContents)
  }

  func getFileInfo(_ path: VirtualPath) throws -> TSCBasic.FileInfo {
    try resolvingVirtualPath(path, apply: getFileInfo)
  }
}
