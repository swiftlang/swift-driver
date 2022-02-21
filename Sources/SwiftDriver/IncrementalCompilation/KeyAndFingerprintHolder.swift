//===--------- KeyAndFingerprintHolder.swift ------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//



/// Encapsulates the invariant required for anything with a DependencyKey and an fingerprint
public struct KeyAndFingerprintHolder:
  ExternalDependencyAndFingerprintEnforcer, Equatable, Hashable
{
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
  /// interface hash. The interface hash is a product of all the tokens that are
  /// not inside of function bodies. Thus, if there is no fingerprint, when the
  /// frontend creates an interface node,
  /// it adds a dependency to it from the implementation source file node (which
  /// has the interfaceHash as its fingerprint).
  let fingerprint: InternedString?

  init(_ key: DependencyKey, _ fingerprint: InternedString?) throws {
    self.key = key
    self.fingerprint = fingerprint
    assert(verifyKeyAndFingerprint())
  }
  var externalDependencyToCheck: ExternalDependency? {
    key.designator.externalDependency
  }
  private func verifyKeyAndFingerprint() -> Bool {
    assert(verifyExternalDependencyAndFingerprint())

    if let externalDependency = externalDependencyToCheck, key.aspect != .interface {
        fatalError("Aspect of external dependency must be interface: \(externalDependency)")
    }
    return true
  }
}
