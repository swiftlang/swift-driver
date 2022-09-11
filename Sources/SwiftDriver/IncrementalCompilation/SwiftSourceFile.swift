//===-------------------- SwiftSourceFile.swift - Incremental -------------===//
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

/// Because the incremental compilation system treats files containing Swift source code specially,
/// it is helpful to statically distinguish them wherever an input must be swift source code.
public struct SwiftSourceFile: Hashable {
  // must be .swift
  public let fileHandle: VirtualPath.Handle

  public init(_ fileHandle: VirtualPath.Handle) {
    self.fileHandle = fileHandle
  }
  public init(_ path: TypedVirtualPath) {
    assert(path.type == .swift)
    self.init(path.fileHandle)
  }
  public init?(ifSource path: TypedVirtualPath) {
    guard path.type == .swift else { return nil }
    self.init(path)
  }

  public init(_ path: VirtualPath) {
    assert(path.name.hasSuffix(".\(FileType.swift.rawValue)"))
    self.init(path.intern())
  }

  public var typedFile: TypedVirtualPath {
    TypedVirtualPath(file: fileHandle, type: .swift)
  }
}

public extension Sequence where Element == TypedVirtualPath {
  var swiftSourceFiles: [SwiftSourceFile] {
    compactMap(SwiftSourceFile.init(ifSource:))
  }
}
