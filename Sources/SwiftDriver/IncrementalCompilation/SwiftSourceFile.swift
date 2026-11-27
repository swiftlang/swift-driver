//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Because the incremental compilation system treats files containing Swift source code specially,
/// it is helpful to statically distinguish them wherever an input must be swift source code.
public struct SwiftSourceFile: Hashable {
  public let fileHandle: VirtualPath.Handle
  public let type: FileType

  public init(_ fileHandle: VirtualPath.Handle, type: FileType) {
    self.fileHandle = fileHandle
    self.type = type
  }
  public init(_ path: TypedVirtualPath) {
    assert(path.type.isSwiftSourceFile)
    self.init(path.fileHandle, type: path.type)
  }
  public init?(ifSource path: TypedVirtualPath) {
    guard path.type.isSwiftSourceFile else { return nil }
    self.init(path)
  }

  public init(_ path: VirtualPath) {
    guard let ext = path.extension,
          let type = FileType(rawValue: ext) else {
      fatalError("Bad type")
    }

    assert(type.isSwiftSourceFile)
    self.init(path.intern(), type: type)
  }

  public var typedFile: TypedVirtualPath {
    TypedVirtualPath(file: fileHandle, type: type)
  }
}

public extension Sequence where Element == TypedVirtualPath {
  var swiftSourceFiles: [SwiftSourceFile] {
    compactMap(SwiftSourceFile.init(ifSource:))
  }
}
