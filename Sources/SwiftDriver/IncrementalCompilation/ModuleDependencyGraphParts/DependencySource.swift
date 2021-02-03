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
  /*@_spi(Testing)*/
  public struct DependencySource: Hashable, CustomStringConvertible {

    let typedFile: TypedVirtualPath

    init(_ typedFile: TypedVirtualPath) {
      assert( typedFile.type == .swiftDeps ||
              typedFile.type == .swiftModule
      )
      self.typedFile = typedFile
    }
    init(_ file: VirtualPath) {
      let ext = file.extension
      let type =
        ext == FileType.swiftDeps  .rawValue ? FileType.swiftDeps :
        ext == FileType.swiftModule.rawValue ? FileType.swiftModule
        : nil
      guard let type = type else {
        fatalError("unexpected dependencySource extension: \(String(describing: ext))")
      }
      self.init(TypedVirtualPath(file: file, type: type))
    }
    /*@_spi(Testing)*/ public init(mock i: Int) {
      self.init(try! VirtualPath(path: String(i) + "." + FileType.swiftDeps.rawValue))
    }
    /*@_spi(Testing)*/ public var mockID: Int {
       Int(file.basenameWithoutExt)!
    }
    var file: VirtualPath { typedFile.file }

    public var description: String {
      file.description
    }
  }
}

// MARK: - testing
extension ModuleDependencyGraph.DependencySource {
  /*@_spi(Testing)*/
  public var sourceFileProvideNameForMockDependencySource: String {
    file.name
  }
  /*@_spi(Testing)*/
  public var interfaceHashForMockDependencySource: String {
    file.name
  }
}
// MARK: - comparing
extension ModuleDependencyGraph.DependencySource: Comparable {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.file.name < rhs.file.name
  }
}
