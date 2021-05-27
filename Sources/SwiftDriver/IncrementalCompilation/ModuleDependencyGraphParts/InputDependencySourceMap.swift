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
import TSCBasic

@_spi(Testing) public struct InputDependencySourceMap: Equatable {
  
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
}

// MARK: - Accessing
extension InputDependencySourceMap {
  @_spi(Testing) public func getSourceIfKnown(for input: TypedVirtualPath) -> DependencySource? {
    biMap[input]
  }

  @_spi(Testing) public func getInputIfKnown(for source: DependencySource) -> TypedVirtualPath? {
    biMap[source]
  }

  @_spi(Testing) public func enumerateToSerializePriors(
    _ eachFn: (TypedVirtualPath, DependencySource) -> Void
  ) {
    biMap.forEach(eachFn)
  }
}

// MARK: - Populating
extension InputDependencySourceMap {
  public enum AdditionPurpose {
    case mocking,
         buildingFromSwiftDeps,
         readingPriors,
         inputsAddedSincePriors }
  @_spi(Testing) public mutating func addEntry(_ input: TypedVirtualPath,
                                               _ dependencySource: DependencySource,
                                               `for` _ : AdditionPurpose) {
    assert(input.type == .swift && dependencySource.typedFile.type == .swiftDeps)
    biMap[input] = dependencySource
  }
}
