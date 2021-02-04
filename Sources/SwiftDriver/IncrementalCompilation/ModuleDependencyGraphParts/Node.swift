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

  /*@_spi(Testing)*/
  public final class Node: KeyAndFingerprintEnforcer {

    /*@_spi(Testing)*/ public typealias Graph = ModuleDependencyGraph

    /// Def->use arcs go by DependencyKey. There may be >1 node for a given key.
    let key: DependencyKey

    /// The frontend records in the fingerprint, all of the information about an
    /// entity, such that any uses need be rebuilt only if the fingerprint
    /// changes.
    /// When the driver reloads a dependency graph (after a frontend job has run),
    /// it can use the fingerprint to determine if the entity has changed and thus
    /// if uses need to be recompiled.
    ///
    /// However, at present, the frontend does not record this information for
    /// every Decl; it only records it for the source-file-as-a-whole in the
    /// interface hash. The inteface hash is a product of all the tokens that are
    /// not inside of function bodies. Thus, if there is no fingerprint, when the
    /// frontend creates an interface node,
    /// it adds a dependency to it from the implementation source file node (which
    /// has the intefaceHash as its fingerprint).
    let fingerprint: String?


    /// The dependencySource file that holds this entity iff the entities .swiftdeps (or in future, .swiftmodule) is known.
    /// If more than one source file has the same DependencyKey, then there
    /// will be one node for each in the driver, distinguished by this field.
    /// Nodes can move from file to file when the driver reads the result of a
    /// compilation.
    /// Nil represents a node with no known residance
    let dependencySource: DependencySource?
    var isExpat: Bool { dependencySource == nil }

    /// This dependencySource is the file where the swiftDeps, etc. was read, not necessarily anything in the
    /// SourceFileDependencyGraph or the DependencyKeys
    init(key: DependencyKey, fingerprint: String?,
         dependencySource: DependencySource?) {
      self.key = key
      self.fingerprint = fingerprint
      self.dependencySource = dependencySource

      #warning("how best to handle an error here")
      try! verifyKeyAndFingerprint()
    }
  }
}
// MARK: - comparing, hashing
extension ModuleDependencyGraph.Node: Equatable, Hashable {
  public static func == (lhs: Graph.Node, rhs: Graph.Node) -> Bool {
    lhs.key == rhs.key && lhs.fingerprint == rhs.fingerprint
      && lhs.dependencySource == rhs.dependencySource
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(key)
    hasher.combine(fingerprint)
    hasher.combine(dependencySource)
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
