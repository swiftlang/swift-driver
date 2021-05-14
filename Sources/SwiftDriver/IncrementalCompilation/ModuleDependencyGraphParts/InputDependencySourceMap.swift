//===------------- InputDependencySourceMap.swift ---------------- --------===//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

@_spi(Testing) public struct InputDependencySourceMap: Equatable, Sequence {
  
  /// Maps input files (e.g. .swift) to and from the DependencySource object.
  ///
  // FIXME: The map between swiftdeps and swift files is absolutely *not*
  // a bijection. In particular, more than one swiftdeps file can be encountered
  // in the course of deserializing priors *and* reading the output file map
  // *and* re-reading swiftdeps files after frontends complete
  // that correspond to the same swift file. These cause two problems:
  // - overwrites in this data structure that lose data and
  // - cache misses in `getInput(for:)` that cause the incremental build to
  // turn over when e.g. entries in the output file map change. This should be
  // replaced by a multi-map from swift files to dependency sources,
  // and a regular map from dependency sources to swift files -
  // since that direction really is one-to-one.
  
  public typealias BiMap = BidirectionalMap<TypedVirtualPath, DependencySource>
  @_spi(Testing) public var biMap = BiMap()
  
  @_spi(Testing) public subscript(input: TypedVirtualPath) -> DependencySource? {
    get { biMap[input] }
    set { biMap[input] = newValue }
  }
  
  @_spi(Testing) public private(set) subscript(dependencySource: DependencySource) -> TypedVirtualPath? {
    get { biMap[dependencySource] }
    set { biMap[dependencySource] = newValue }
  }

  public func makeIterator() -> BiMap.Iterator {
    biMap.makeIterator()
  }

}
