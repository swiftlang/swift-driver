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

// MARK: - DependencySource
extension ModuleDependencyGraph {
  /// Points to the source of dependencies, i.e. the file read to obtain the information.
  /*@_spi(Testing)*/ public struct DependenciesSource: Hashable, CustomStringConvertible {

    let file: VirtualPath
    #warning("if generalize, fix IncrementalCompilationState.swift:417")

    init?(_ typedFile: TypedVirtualPath) {
      guard typedFile.type == .swiftDeps else { return nil }
      self.init(typedFile.file)
    }
    init(_ file: VirtualPath) {
      self.file = file
    }
    /*@_spi(Testing)*/ public init(mock i: Int) {
      self.file = try! VirtualPath(path: String(i))
    }
    /*@_spi(Testing)*/ public var mockID: Int {
       Int(file.name)!
    }
    public var description: String {
      file.description
    }
  }
}

// MARK: - testing
extension ModuleDependencyGraph.DependenciesSource {
  /*@_spi(Testing)*/ public var sourceFileProvideNameForMockDependenciesSource: String {
    file.name
  }
  /*@_spi(Testing)*/ public var interfaceHashForMockDependenciesSource: String {
    file.name
  }
}
// MARK: - comparing
extension ModuleDependencyGraph.DependenciesSource: Comparable {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.file.name < rhs.file.name
  }
}
