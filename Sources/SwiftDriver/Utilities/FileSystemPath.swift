//===--------------- FileSystemPath.swift - Swift File System Paths --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic

/// AbsolutePath or RelativePath
public enum FileSystemPath: Hashable {
  /// A relative path that has not been resolved based on the current working
  /// directory.
  case relative(RelativePath)

  /// An absolute path in the file system.
  case absolute(AbsolutePath)

  /// Form a path which may be either absolute or relative.
  public init(path: String) throws {
    if let absolute = try? AbsolutePath(validating: path) {
      self = .absolute(absolute)
    } else {
      let relative = try RelativePath(validating: path)
      self = .relative(relative)
    }
  }
}

extension FileSystemPath {
  public var virtualPath: VirtualPath {
    switch self {
    case .relative(let path):
      return .relative(path)
    case .absolute(let path):
      return .absolute(path)
    }
  }
}

extension FileSystemPath {

  /// The name of the path for presentation purposes.
  public var name: String { description }
  
  /// Normalized string representation. This string is never empty.
  public var pathString: String {
    switch self {
    case .absolute(let path):
      return path.pathString
    case .relative(let path):
      return path.pathString
    }
  }

  /// Parent directory, uses .. for relative paths.
  public var parentDirectory: FileSystemPath {
    switch self {
    case .absolute(let path):
      return .absolute(path.parentDirectory)
    case .relative(let path):
      return .relative(path.appending(component: ".."))
    }
  }

  /// Returns the virtual path with an additional literal component appended.
  public func appending(component: String) -> FileSystemPath {
    switch self {
    case .absolute(let path):
      return .absolute(path.appending(component: component))
    case .relative(let path):
      return .relative(path.appending(component: component))
    }
  }

  /// Returns the virtual path with additional literal components appended.
  public func appending(components: String...) -> FileSystemPath {
    // Need to copy implementations here because swift doesn't support forwarding variadic arguments
    switch self {
    case .absolute(let path):
      return .absolute(components.reduce(path, { path, name in
          path.appending(component: name)
      }))
    case .relative(let path):
      return .relative(RelativePath(path.pathString + "/" + components.joined(separator: "/")))
    }
  }

  /// Retrieve the basename of the path without the extension.
  public var basenameWithoutExt: String {
    switch self {
    case .absolute(let path):
      return path.basenameWithoutExt
    case .relative(let path):
      return path.basenameWithoutExt
    }
  }
}

extension FileSystemPath: Codable {
  private enum CodingKeys: String, CodingKey {
    case relative, absolute
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
    }
  }
}

extension FileSystemPath: CustomStringConvertible {
  public var description: String {
    return pathString
  }
}

extension TSCBasic.FileSystem {
  private func resolvingVirtualPath<T>(
    _ path: FileSystemPath,
    apply f: (AbsolutePath) -> T
  ) -> T {
    switch path {
    case let .absolute(absPath):
      return f(absPath)
    case let .relative(relPath):
      guard let cwd = currentWorkingDirectory else {
        fatalError("currentWorkingDirectory no longer exists")
      }
      return f(.init(cwd, relPath))
    }
  }

  /// Resolve provided `FileSystemPath` to a `AbsolutePath` and check if it exists.
  func exists(_ path: FileSystemPath) -> Bool {
    return resolvingVirtualPath(path, apply: exists)
  }

  /// Resolve provided `FileSystemPath` to a `AbsolutePath` and check if it is a file.
  func isFile(_ path: FileSystemPath) -> Bool {
    return resolvingVirtualPath(path, apply: isFile)
  }
}
