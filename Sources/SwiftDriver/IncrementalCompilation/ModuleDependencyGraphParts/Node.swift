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

// MARK: - ModuleDependencyGraph.Node
extension ModuleDependencyGraph {
  
  /// A node in the per-module (i.e. the driver) dependency graph
  /// Each node represents a `Decl` from the frontend.
  /// If a file references a `Decl` we haven't seen yet, the node's `dependencySource` will be nil,
  /// otherwise it will hold the name of the dependencySource file from which the node was read.
  /// A dependency is represented by an arc, in the `usesByDefs` map.
  /// (Cargo-culted and modified from the legacy driver.)
  ///
  /// Use a class, not a struct because otherwise it would be duplicated for each thing it uses
  ///
  /// Neither the `fingerprint`, nor the `isTraced` value is part of the node's identity.
  /// Neither of these must be considered for equality testing or hashing because their
  /// value is subject to change during integration and tracing.

  public final class Node {

    /*@_spi(Testing)*/ public typealias Graph = ModuleDependencyGraph

    /// Hold these where an invariant can be checked.
    /// Must be able to change the fingerprint
    private(set) var keyAndFingerprint: KeyAndFingerprintHolder

    var key: DependencyKey { keyAndFingerprint.key }
    /*@_spi(Testing)*/ public var fingerprint: String? { keyAndFingerprint.fingerprint }

    /// The dependencySource file that holds this entity iff the entities .swiftdeps (or in future, .swiftmodule) is known.
    /// If more than one source file has the same DependencyKey, then there
    /// will be one node for each in the driver, distinguished by this field.
    /// Nodes can move from file to file when the driver reads the result of a
    /// compilation.
    /// Nil represents a node with no known residance
    @_spi(Testing) public let dependencySource: DependencySource?
    var isExpat: Bool { dependencySource == nil }

    /// When integrating a change, the driver finds untraced nodes so it can kick off jobs that have not been
    /// kicked off yet. (Within any one driver invocation, compiling a source file is idempotent.)
    /// When reading a serialized, prior graph, *don't* recover this state, since it will be a new driver
    /// invocation that has not kicked off any compiles yet.
    @_spi(Testing) public private(set) var isTraced: Bool = false

    public let hashValue: Int

    /// This dependencySource is the file where the swiftDeps, etc. was read, not necessarily anything in the
    /// SourceFileDependencyGraph or the DependencyKeys
    init(key: DependencyKey, fingerprint: String?,
         dependencySource: DependencySource?,
         hashValue: Int? = nil) {
      self.keyAndFingerprint = try! KeyAndFingerprintHolder(key, fingerprint)
      self.dependencySource = dependencySource
      self.hashValue = hashValue ?? Self.computeHash(key, dependencySource)
      assert(hashValue.map {$0 == self.hashValue} ?? true)
    }
  }
}

// MARK: - Setting fingerprint
extension ModuleDependencyGraph.Node {
  func setFingerprint(_ newFP: String?) {
    keyAndFingerprint = try! KeyAndFingerprintHolder(key, newFP)
  }
}

// MARK: - trace status
extension ModuleDependencyGraph.Node {
  var isUntraced: Bool { !isTraced }
  func setTraced() { isTraced = true }
  @_spi(Testing) public func setUntraced() { isTraced = false }
}

// MARK: - comparing, hashing
extension ModuleDependencyGraph.Node: Equatable, Hashable {
  public static func ==(lhs: ModuleDependencyGraph.Node, rhs: ModuleDependencyGraph.Node) -> Bool {
    lhs.keyAndFingerprint.key == rhs.keyAndFingerprint.key &&
    lhs.dependencySource == rhs.dependencySource
  }
  static private func computeHash(_ key: DependencyKey, _ source: DependencySource?) -> Int {
    var h = Hasher()
    h.combine(key)
    h.combine(source)
    return h.finalize()
  }
}

extension ModuleDependencyGraph.Node: Comparable {
  public static func < (lhs: ModuleDependencyGraph.Node, rhs: ModuleDependencyGraph.Node) -> Bool {
    func lt<T: Comparable> (_ a: T?, _ b: T?) -> Bool {
      switch (a, b) {
      case let (x?, y?): return x < y
      case (nil, nil): return false
      case (nil, _?): return true
      case (_?, nil): return false
      }
    }
    return lhs.key != rhs.key ? lhs.key < rhs.key :
      lhs.dependencySource != rhs.dependencySource
        ? lt(lhs.dependencySource, rhs.dependencySource)
        : lt(lhs.fingerprint, rhs.fingerprint)
  }
}


extension ModuleDependencyGraph.Node: CustomStringConvertible {
  public var description: String {
    "\(key) \( dependencySource.map { "in \($0.description)" } ?? "<expat>" )"
  }
}

extension ModuleDependencyGraph.Node {
  public func verify() {
    verifyExpatsHaveNoFingerprints()
    key.verify()
  }
  
  public func verifyExpatsHaveNoFingerprints() {
    if isExpat && fingerprint != nil {
      fatalError(#function)
    }
  }
}
