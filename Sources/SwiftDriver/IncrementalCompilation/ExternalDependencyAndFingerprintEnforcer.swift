//===------- FingerprintedExternalHolder.swift ----------------------------===//
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

/// Central place to check an invariant: If an externalDependency has a fingerprint, it should point
/// to a swiftmodule file that contains dependency information.

protocol ExternalDependencyAndFingerprintEnforcer {
  var externalDependencyToCheck: ExternalDependency? {get}
  var fingerprint: InternedString? {get}
}
extension ExternalDependencyAndFingerprintEnforcer {
  func verifyExternalDependencyAndFingerprint() -> Bool {
    if let _ = self.fingerprint,
       let externalDependency = externalDependencyToCheck,
       !externalDependency.isSwiftModule {
      fatalError("An external dependency with a fingerprint must point to a swiftmodule file: \(externalDependency)")
    }
    return true
  }
}
