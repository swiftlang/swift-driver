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

/// TODO: Incremental  privatize, organize
@_spi(Testing) public final class ModuleDepGraphNode {
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
  var fingerprint: String?


    /// The swiftDeps file that holds this entity iff this is a provides node.
    /// If more than one source file has the same DependencyKey, then there
    /// will be one node for each in the driver, distinguished by this field.
  var swiftDeps: String?

  /// When finding transitive dependents, this node has been traversed.
  var hasBeenTracedAsADependent = false

  init(key: DependencyKey, fingerprint: String?, swiftDeps: String?) {
    self.key = key
    self.fingerprint = fingerprint
    self.swiftDeps = swiftDeps
  }

  var hasBeenTraced: Bool { hasBeenTracedAsADependent }
  func setHasBeenTraced() { hasBeenTracedAsADependent = true }
  func clearHasBeenTraced() { hasBeenTracedAsADependent = false }

    /// Integrate \p integrand's fingerprint into \p dn.
    /// \returns true if there was a change requiring recompilation.
  func integrateFingerprintFrom(_ integrand: SourceFileDependencyGraph.Node) -> Bool {
    if fingerprint == integrand.fingerprint {
        return false
      }
    fingerprint = integrand.fingerprint
    return true
    }


    /// Nodes can move from file to file when the driver reads the result of a
    /// compilation.
  func setSwiftDeps(s: String?) { swiftDeps = s }

  var isProvides: Bool {swiftDeps != nil}

    /// Return true if this node describes a definition for which the job is known
  var isDefinedInAKnownFile: Bool { isProvides }

  static let expatSwiftDeps = ""

  var nodeMapKey: (String, DependencyKey) {
    (swiftDeps ?? Self.expatSwiftDeps, key)
  }

  var doesNodeProvideAnInterface: Bool {
    key.aspect == .interface && isProvides
    }

  func assertImplementationMustBeInAFile() -> Bool {
    assert(isDefinedInAKnownFile || key.aspect != .implementation,
             "Implementations must be in some file.")
      return true;
    }
}


extension ModuleDepGraphNode: Equatable, Hashable {
  /// Excludes hasBeenTraced...
  static public func == (lhs: ModuleDepGraphNode, rhs: ModuleDepGraphNode) -> Bool {
    lhs.key == rhs.key && lhs.fingerprint == rhs.fingerprint
      && lhs.swiftDeps == rhs.swiftDeps
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(key)
    hasher.combine(fingerprint)
    hasher.combine(swiftDeps)
  }
}


extension ModuleDepGraphNode: CustomStringConvertible {
  public var description: String {
    "\(key)\( swiftDeps.map {" \($0)"} ?? "" )"
  }
}
