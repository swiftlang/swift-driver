//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(Testing) import SwiftDriver
import SwiftOptions
import TSCBasic
import TestUtilities
import Testing

// MARK: - Build Configuration

enum TestBuildConfig: CaseIterable, CustomStringConvertible, Sendable {
  case implicitModule
  case explicitModule
  case cachingBuild
  case cachingPrefixMapped

  var description: String {
    switch self {
    case .implicitModule: "implicit"
    case .explicitModule: "explicit"
    case .cachingBuild: "caching"
    case .cachingPrefixMapped: "cachingPrefixMapped"
    }
  }

  var isExplicitModuleBuild: Bool { self != .implicitModule }
  var requiresCaching: Bool { self == .cachingBuild || self == .cachingPrefixMapped }

  static var explicitConfigs: [TestBuildConfig] {
    allCases.filter(\.isExplicitModuleBuild)
  }

  /// Filter configs to only those supported by the current environment.
  static func available(_ configs: [TestBuildConfig]) -> [TestBuildConfig] {
    configs.filter { !$0.requiresCaching || cachingFeatureSupported }
  }

  /// All explicit module build configs that are available.
  static var availableExplicitConfigs: [TestBuildConfig] {
    available(explicitConfigs)
  }

  /// Explicit-only (no caching) configs.
  static var explicitOnlyConfigs: [TestBuildConfig] {
    available([.explicitModule])
  }

  /// Caching configs only.
  static var cachingConfigs: [TestBuildConfig] {
    available([.cachingBuild, .cachingPrefixMapped])
  }

  /// Not prefix mapped explicit build.
  static var explicitNonPrefixed: [TestBuildConfig] {
    available([.explicitModule, .cachingBuild])
  }
}

extension TestBuildConfig: CustomTestStringConvertible {
  var testDescription: String { description }
}

// MARK: Testing Traits

private func hostOS() -> Set<Triple.OS> {
  #if os(Windows)
  return [.win32]
  #elseif os(Linux)
  return [.linux]
  #elseif os(macOS)
  return [.macosx, .darwin]
  #elseif os(iOS)
  return [.ios, .darwin]
  #elseif os(tvOS)
  return [.tvos, .darwin]
  #elseif os(watchOS)
  return [.watchos, .darwin]
  #elseif os(visionOS)
  return [.visionos, .darwin]
  #else
  return []  // unsupported.
  #endif
}

extension Trait where Self == Testing.ConditionTrait {
  package static func requireHostOS(_ os: Triple.OS..., comment: Comment? = nil) -> Self {
    enabled(comment ?? "This test requires host OS: \(os)", { os.allSatisfy { hostOS().contains($0) } })
  }

  package static func skipHostOS(_ os: Triple.OS..., comment: Comment? = nil) -> Self {
    disabled(comment ?? "This test cannot run on host OS: \(os)", { os.allSatisfy { hostOS().contains($0) } })
  }

  /// Requires ObjC Runtime to run.
  package static func requireObjCRuntime(_ comment: Comment? = nil) -> Self {
    #if _runtime(_ObjC)
    enabled(if: true)
    #else
    disabled(comment ?? "This test requires ObjC Runtime")
    #endif
  }

  /// Requires that the Swift frontend supports a specific argument.
  package static func requireFrontendArgSupport(
    _ option: Option,
    _ comment: Comment? = nil
  ) -> Self {
    let supported = _featureCheckDriver?.isFrontendArgSupported(option) ?? false
    return enabled(
      if: supported,
      comment ?? Comment(rawValue: "Frontend does not support '\(option.spelling)'")
    )
  }

  /// Requires that libSwiftScan supports link library reporting.
  package static func requireScannerSupportsLinkLibraries(_ comment: Comment? = nil) -> Self {
    let supported = (try? _scannerOracle?.supportsLinkLibraries()) ?? false
    return enabled(if: supported, comment ?? "libSwiftScan does not support link library reporting")
  }

  /// Requires that libSwiftScan supports import info reporting.
  package static func requireScannerSupportsImportInfos(_ comment: Comment? = nil) -> Self {
    let supported = (try? _scannerOracle?.supportsImportInfos()) ?? false
    return enabled(if: supported, comment ?? "libSwiftScan does not support import details reporting")
  }

  /// Requires that libSwiftScan supports library level reporting.
  package static func requireScannerSupportsLibraryLevel(_ comment: Comment? = nil) -> Self {
    let supported = (try? _scannerOracle?.supportsLibraryLevel()) ?? false
    return enabled(if: supported, comment ?? "libSwiftScan does not support library level reporting")
  }

  /// Requires that libSwiftScan supports per-scan diagnostics.
  package static func requireScannerSupportsPerScanDiagnostics(_ comment: Comment? = nil) -> Self {
    let supported = (try? _scannerOracle?.supportsPerScanDiagnostics()) ?? false
    return enabled(if: supported, comment ?? "libSwiftScan does not support diagnostics queries")
  }

  /// Requires that libSwiftScan supports binary framework dependency reporting.
  package static func requireScannerSupportsBinaryFrameworkDependencies(_ comment: Comment? = nil) -> Self {
    let supported = (try? _scannerOracle?.supportsBinaryFrameworkDependencies()) ?? false
    return enabled(if: supported, comment ?? "libSwiftScan does not support framework binary dependency reporting")
  }

  /// Requires that libSwiftScan supports binary module header dependencies.
  package static func requireScannerSupportsBinaryModuleHeaderDependencies(_ comment: Comment? = nil) -> Self {
    let supported = (try? _scannerOracle?.supportsBinaryModuleHeaderDependencies()) ?? false
    return enabled(if: supported, comment ?? "libSwiftScan does not support binary module header dependencies")
  }

  /// Requires that explicit module verify interface is supported.
  package static func requireExplicitModuleVerifyInterface(_ comment: Comment? = nil) -> Self {
    let supported = _featureCheckDriver?.isFrontendArgSupported(.inputFileKey) ?? false
    return enabled(if: supported, comment ?? "-typecheck-module-from-interface doesn't support explicit build")
  }
}

package struct KnownIssueTestTrait: TestTrait & SuiteTrait & TestScoping {
  let comment: Comment
  let isIntermittent: Bool
  let sourceLocation: SourceLocation

  package var isRecursive: Bool {
    true
  }

  package func provideScope(
    for test: Testing.Test,
    testCase: Testing.Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    if testCase == nil || test.isSuite {
      try await function()
    } else {
      await withKnownIssue(comment, isIntermittent: isIntermittent, sourceLocation: sourceLocation) {
        try await function()
      }
    }
  }
}

extension Trait where Self == KnownIssueTestTrait {
  /// Causes a test to be marked as a (nondeterministic) expected failure if it throws any error or records any issue.
  package static func flaky(_ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation) -> Self {
    Self(comment: comment, isIntermittent: true, sourceLocation: sourceLocation)
  }

  /// Causes a test to be marked as a (deterministic) expected failure by requiring it to throw an error or record an issue.
  package static func knownIssue(_ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation) -> Self {
    Self(comment: comment, isIntermittent: false, sourceLocation: sourceLocation)
  }
}

// MARK: - Feature availability

/// A shared Driver instance used for checking feature support at test discovery time.
private let _featureCheckDriver: TestDriver? = try? TestDriver(args: ["swiftc", "test.swift"])

/// A shared scanner oracle for checking scanner feature support.
private let _scannerOracle: InterModuleDependencyOracle? = {
  guard let driver = _featureCheckDriver,
    let scanLibPath = try? driver.getSwiftScanLibPath()
  else { return nil }
  let oracle = InterModuleDependencyOracle()
  try? oracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanLibPath)
  return oracle
}()

let sdkArgumentsAvailable: Bool = {
  do {
    return try Driver.sdkArgumentsForTesting() != nil
  } catch {
    return false
  }
}()

let cachingFeatureSupported: Bool = {
  guard let driver = try? TestDriver(args: ["swiftc"]) else { return false }
  return driver.isFeatureSupported(.compilation_caching)
}()
