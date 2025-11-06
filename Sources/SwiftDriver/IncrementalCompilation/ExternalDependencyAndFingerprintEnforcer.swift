//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
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
