//===------- KeyAndFingerprintEnforcer.swift ------------------------------===//
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

/// Encapsulates the invariant required for anything with a DependencyKey and an fingerprint
protocol KeyAndFingerprintEnforcer {
  var key: DependencyKey {get}
  var fingerprint: String? {get}
}
extension KeyAndFingerprintEnforcer {
  func verifyKeyAndFingerprint() throws {
    guard case .externalDepend(let externalDependency) = key.designator
    else {
      return
    }
    guard key.aspect == .interface else {
      throw KeyAndFingerprintEnforcerError.externalDepsMustBeInterface(externalDependency)
    }
    guard let file = externalDependency.file else {
      throw KeyAndFingerprintEnforcerError.noFile(externalDependency)
    }
    guard let fingerprint = self.fingerprint else {
      return
    }
    
    guard file.extension == FileType.swiftModule.rawValue else {
      throw KeyAndFingerprintEnforcerError.onlySwiftModulesHaveFingerprints(externalDependency, fingerprint)
    }
  }
}
enum KeyAndFingerprintEnforcerError: LocalizedError {
  case externalDepsMustBeInterface(ExternalDependency)
  case noFile(ExternalDependency)
  case onlySwiftModulesHaveFingerprints(ExternalDependency, String)

  var errorDescription: String? {
    switch self {
    case let .externalDepsMustBeInterface(externalDependency):
      return "Aspect of external dependency must be interface: \(externalDependency)"
    case let .noFile(externalDependency):
      return "External dependency must point to a file: \(externalDependency)"
    case let .onlySwiftModulesHaveFingerprints(externalDependency, fingerprint):
      return "An external dependency with a fingerprint (\(fingerprint)) must point to a swiftmodule file: \(externalDependency)"
    }
  }
}
