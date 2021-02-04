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
/// Points to the source of dependencies, i.e. the file read to obtain the information.
/*@_spi(Testing)*/
public struct DependencySource: Hashable, CustomStringConvertible {

  let typedFile: TypedVirtualPath

  init(_ typedFile: TypedVirtualPath) {
    assert( typedFile.type == .swiftDeps ||
            typedFile.type == .swiftModule)
      self.typedFile = typedFile
  }

  /*@_spi(Testing)*/
  public init(_ file: VirtualPath) {
    let ext = file.extension
    let typeIfExpected =
      ext == FileType.swiftDeps  .rawValue ? FileType.swiftDeps :
      ext == FileType.swiftModule.rawValue ? FileType.swiftModule
      : nil
    guard let type = typeIfExpected else {
      fatalError("unexpected dependencySource extension: \(String(describing: ext))")
    }
    self.init(TypedVirtualPath(file: file, type: type))
  }

  var file: VirtualPath { typedFile.file }

  public var description: String {
    file.description
  }
}

// MARK: - mocking
extension DependencySource {
  /*@_spi(Testing)*/ public init(mock i: Int) {
    self.init(try! VirtualPath(path: String(i) + "." + FileType.swiftDeps.rawValue))
  }

  /*@_spi(Testing)*/ public var mockID: Int {
    Int(file.basenameWithoutExt)!
  }
}

// MARK: - reading
extension DependencySource {
  /// Throws if a read error
  /// Returns nil if no dependency info there.
  public func read(
    in fileSystem: FileSystem,
    reporter: IncrementalCompilationState.Reporter?
  ) -> SourceFileDependencyGraph? {
    let graphIfPresent: SourceFileDependencyGraph?
    do {
      graphIfPresent = try SourceFileDependencyGraph.read(
        from: self,
        on: fileSystem)
    }
    catch {
      let msg = "Could not read \(file) \(error.localizedDescription)"
      reporter?.report(msg, typedFile)
      return nil
    }
    return graphIfPresent
  }
}
// MARK: - testing
extension DependencySource {
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
extension DependencySource: Comparable {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.file.name < rhs.file.name
  }
}
