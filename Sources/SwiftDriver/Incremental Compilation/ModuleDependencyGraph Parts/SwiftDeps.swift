//===------------------------ Node.swift ----------------------------------===//
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
import Foundation
import TSCBasic

// MARK: - SwiftDeps
extension ModuleDependencyGraph {
  @_spi(Testing) public struct SwiftDeps: Hashable, CustomStringConvertible {

    let file: VirtualPath

    @_spi(Testing) public init?(_ typedFile: TypedVirtualPath) {
      guard typedFile.type == .swiftDeps else { return nil }
      self.file = typedFile.file
    }

    @_spi(Testing) public init(mock whatever: String) {
      self.file = try! VirtualPath(path: whatever)
    }

    public var description: String {
      file.description
    }
  }
}

// MARK: - testing
extension ModuleDependencyGraph.SwiftDeps {
  @_spi(Testing) public var sourceFileProvideNameForMockSwiftDeps: String {
    file.name
  }
  @_spi(Testing) public var interfaceHashForMockSwiftDeps: String {
    file.name
  }
}
