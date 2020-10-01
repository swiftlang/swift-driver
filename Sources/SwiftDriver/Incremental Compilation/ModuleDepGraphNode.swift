//===---------- ModuleDepGraphNode.swift ----------------------------------===//
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

/// TODO: Incremental  privatize, organize _spi's

/// A node in the per-module (i.e. the driver) dependency graph
/// Each node represents a \c Decl from the frontend.
/// If a file references a \c Decl we haven't seen yet, the node's \c swiftDeps will be nil, otherwise
/// it will hold the name of the swiftdeps file from which the node was read.
/// A dependency is represented by an arc, in the `usesByDefs` map.
/// (Cargo-culted and modified from the legacy driver.)

@_spi(Testing) public final class ModuleDepGraphNode {
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
  private var fingerprint: String?


  /// The swiftDeps file that holds this entity iff the entities .swiftdeps is known.
  /// If more than one source file has the same DependencyKey, then there
  /// will be one node for each in the driver, distinguished by this field.
  /// Nodes can move from file to file when the driver reads the result of a
  /// compilation.
  /// Empty string represents a node with no known residance
  var swiftDeps: String
  var isExpat: Bool { swiftDeps == Self.expatSwiftDeps }


  /// When finding transitive dependents, this node has been traversed.
  internal private(set) var hasBeenTraced = false

  init(key: DependencyKey, fingerprint: String?, swiftDeps: String) {
    self.dependencyKey = key
    self.fingerprint = fingerprint
    self.swiftDeps = swiftDeps
  }
}

// MARK: - Tracing
extension ModuleDepGraphNode {
  func   setHasBeenTraced() { hasBeenTraced = true }
  func clearHasBeenTraced() { hasBeenTraced = false }
}

// MARK: - Fingerprinting
extension ModuleDepGraphNode {
  /// Integrate \p integrand's fingerprint into \p dn.
  /// \returns true if there was a change requiring recompilation.
  func integrateFingerprintFrom(_ integrand: SourceFileDependencyGraph.Node) -> Bool {
    if fingerprint == integrand.fingerprint {
      return false
    }
    fingerprint = integrand.fingerprint
    return true
  }
}







extension ModuleDepGraphNode {



  /// Return true if this node describes a definition for which the job is known

  static let expatSwiftDeps = ""

  var nodeMapKey: (String, DependencyKey) {
    (swiftDeps, dependencyKey)
  }
}


extension ModuleDepGraphNode: Equatable, Hashable {
  /// Excludes hasBeenTraced...
  static public func == (lhs: ModuleDepGraphNode, rhs: ModuleDepGraphNode) -> Bool {
    // TODO is fingerprint righ tin here?
    lhs.dependencyKey == rhs.dependencyKey && lhs.fingerprint == rhs.fingerprint
      && lhs.swiftDeps == rhs.swiftDeps
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(dependencyKey)
    hasher.combine(fingerprint)
    hasher.combine(swiftDeps)
  }
}


extension ModuleDepGraphNode: CustomStringConvertible {
  public var description: String {
    "\(dependencyKey)\( swiftDeps)"
  }
}

extension ModuleDepGraphNode {
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
