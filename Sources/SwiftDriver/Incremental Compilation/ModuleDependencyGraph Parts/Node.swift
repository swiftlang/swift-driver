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
  /// Each node represents a \c Decl from the frontend.
  /// If a file references a \c Decl we haven't seen yet, the node's \c swiftDeps will be nil, otherwise
  /// it will hold the name of the swiftdeps file from which the node was read.
  /// A dependency is represented by an arc, in the `usesByDefs` map.
  /// (Cargo-culted and modified from the legacy driver.)
  ///
  /// Use a class, not a struct because otherwise it would be duplicated for each thing it uses

  @_spi(Testing) public final class Node {

    @_spi(Testing) public typealias Graph = ModuleDependencyGraph

    /// Def->use arcs go by DependencyKey. There may be >1 node for a given key.
    let dependencyKey: DependencyKey

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


    /// The swiftDeps file that holds this entity iff the entities .swiftdeps is known.
    /// If more than one source file has the same DependencyKey, then there
    /// will be one node for each in the driver, distinguished by this field.
    /// Nodes can move from file to file when the driver reads the result of a
    /// compilation.
    /// Nil represents a node with no known residance
    let swiftDeps: SwiftDeps?
    var isExpat: Bool { swiftDeps == nil }

    /// This swiftDeps is the file where the swiftDeps was read, not necessarily anything in the
    /// SourceFileDependencyGraph or the DependencyKeys
    init(key: DependencyKey, fingerprint: String?, swiftDeps: SwiftDeps?) {
      self.dependencyKey = key
      self.fingerprint = fingerprint
      self.swiftDeps = swiftDeps
    }
  }
}
// MARK: - comparing, hashing
extension ModuleDependencyGraph.Node: Equatable, Hashable {
  /// Excludes hasBeenTraced...
  public static func == (lhs: Graph.Node, rhs: Graph.Node ) -> Bool {
    lhs.dependencyKey == rhs.dependencyKey && lhs.fingerprint == rhs.fingerprint
      && lhs.swiftDeps == rhs.swiftDeps
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(dependencyKey)
    hasher.combine(fingerprint)
    hasher.combine(swiftDeps)
  }
}


extension ModuleDependencyGraph.Node: CustomStringConvertible {
  public var description: String {
    "\(dependencyKey)\( swiftDeps?.description ?? "<expat>")"
  }
}

extension ModuleDependencyGraph.Node {
  public func verify() {
    verifyExpatsHaveNoFingerprints()
    dependencyKey.verify()
  }
  
  public func verifyExpatsHaveNoFingerprints() {
    if isExpat && fingerprint != nil {
      fatalError(#function)
    }
  }
}
