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

  public let typedFile: TypedVirtualPath

  init(_ typedFile: TypedVirtualPath) {
    assert( typedFile.type == .swiftDeps ||
            typedFile.type == .swiftModule)
      self.typedFile = typedFile
  }

  /*@_spi(Testing)*/
  /// Returns nil if cannot be a source
  public init?(_ file: VirtualPath) {
    let ext = file.extension
    guard let type =
      ext == FileType.swiftDeps  .rawValue ? FileType.swiftDeps :
      ext == FileType.swiftModule.rawValue ? FileType.swiftModule
      : nil
    else {
      return nil
    }
    self.init(TypedVirtualPath(file: file, type: type))
  }

  public var file: VirtualPath { typedFile.file }

  public var description: String {
    ExternalDependency(path: file).description
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

// MARK: - comparing
extension DependencySource: Comparable {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.file.name < rhs.file.name
  }
}

// MARK: - describing
extension DependencySource {
  /// Answer a single name; for swift modules, the right thing is one level up
  public var shortDescription: String {
    switch typedFile.type {
    case .swiftDeps:
      return file.basename
    case .swiftModule:
      return file.parentDirectory.basename
    default:
      return file.name
    }
  }
}

