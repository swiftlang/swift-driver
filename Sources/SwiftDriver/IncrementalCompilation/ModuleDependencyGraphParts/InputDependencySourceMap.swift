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

/// Maps input source files to- and from- `DependencySource`s containing the swiftdeps paths.
/// Deliberately at the level of specific intention, for clarity and to facilitate restructuring later.
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

  /// Holds the mapping for now. To be replaced later.
  public typealias BiMap = BidirectionalMap<TypedVirtualPath, DependencySource>
  @_spi(Testing) public var biMap = BiMap()
}

// MARK: - Accessing
extension InputDependencySourceMap {
  /// Find where the swiftdeps are stored for a given source file.
  ///
  /// - Parameter input: A source file path
  /// - Returns: the corresponding `DependencySource`, or nil if none known.
  @_spi(Testing) public func sourceIfKnown(for input: TypedVirtualPath) -> DependencySource? {
    biMap[input]
  }

  /// Find where the source file is for a given swiftdeps file.
  ///
  /// - Parameter source: A `DependencySource` (containing a swiftdeps file)
  /// - Returns: the corresponding input source file, or nil if none known.
  @_spi(Testing) public func input(ifKnownFor source: DependencySource) -> TypedVirtualPath? {
    biMap[source]
  }

  /// Enumerate the input <-> dependency source pairs to be serialized
  ///
  /// - Parameter eachFn: a function to be called for each pair
  @_spi(Testing) public func enumerateToSerializePriors(
    _ eachFn: (TypedVirtualPath, DependencySource) -> Void
  ) {
    biMap.forEach(eachFn)
  }
}

// MARK: - Populating
extension InputDependencySourceMap {
  /// For structural modifications-to-come, reify the various reasons to add an entry.
  public enum AdditionPurpose {
    /// For unit testing
    case mocking

    /// When building a graph from swiftDeps files without priors
    case buildingFromSwiftDeps

    /// Deserializing the map stored with the priors
    case readingPriors

    /// After reading the priors, used to add entries for any inputs that might not have been in the priors.
    case inputsAddedSincePriors
  }

  /// Add a mapping to & from input source file to swiftDeps file path
  ///
  /// - Parameter input: the source file path
  /// - Parameter dependencySource: the dependency source (holding the swiftdeps path)
  /// - Parameter why: the purpose for this addition. Will be used for future restructuring.
  @_spi(Testing) public mutating func addEntry(_ input: TypedVirtualPath,
                                               _ dependencySource: DependencySource,
                                               for why: AdditionPurpose) {
    assert(input.type == .swift && dependencySource.typedFile.type == .swiftDeps)
    biMap[input] = dependencySource
  }
}
