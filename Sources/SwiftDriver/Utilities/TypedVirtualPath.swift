//===--------------- TypedVirtualPath.swift - Swift Virtual Paths ---------===//
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
/// A path for which the type of the input is known.
public struct TypedVirtualPath: Hashable, Codable {
  /// The file this input refers to.
  public let fileHandle: VirtualPath.Handle

  /// The type of file we are working with.
  public let type: FileType

  public var file: VirtualPath {
    return VirtualPath.lookup(self.fileHandle)
  }

  public init(file: VirtualPath.Handle, type: FileType) {
    self.fileHandle = file
    self.type = type
  }
}
