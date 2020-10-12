//===------------------ FileTracker.swift ---------------------------------===//
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

extension ModuleDependencyGraph {
  // TODO: Incremental, check the relationship between batching and incremental compilation
  // Must delay batching until *after* incremental decisions

  ///Since the rest of the driver trucks in jobs, the correspondence must be tracked
  @_spi(Testing) public struct FileTracker {

    /// Keyed by swiftdeps filename, so we can get back to source files.
    private(set) var sourceFilesBySwiftDeps: [SwiftDeps: TypedVirtualPath] = [:]
    private(set) var swiftDepsBySourceFile: [TypedVirtualPath: SwiftDeps] = [:]


    @_spi(Testing) public mutating func register(source: TypedVirtualPath,
                                                 swiftDeps: SwiftDeps) {
      sourceFilesBySwiftDeps[swiftDeps] = source
      swiftDepsBySourceFile[source] = swiftDeps
    }

    @_spi(Testing) public func swiftDeps(for sourceFile: TypedVirtualPath
    ) -> SwiftDeps {
      guard let swiftDeps = swiftDepsBySourceFile[sourceFile]
      else {
      fatalError("\(sourceFile) was not registered")
      }
      return swiftDeps
    }

    @_spi(Testing) public func sourceFile(for swiftDeps: SwiftDeps
    ) -> TypedVirtualPath {
      guard let sourceFile = sourceFilesBySwiftDeps[swiftDeps]
      else {
        fatalError("\(swiftDeps) was not registered")
      }
      return sourceFile
    }
  }
}
