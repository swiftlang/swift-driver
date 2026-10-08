//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Testing
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

/// Creates a `DiagnosticsEngine` that collects which sources were compiled.
///
/// - seealso: Test
struct CompiledSourceCollector {
  private var collectedCompiledBasenames = [String]()
  private var collectedReadDependencies = Set<String>()

  /// Lifecycle messages for jobs that build a module rather than compile
  /// sources. They share the `Compiling ` prefix with a source compile, so the
  /// text after that prefix is a module description, not a list of files.
  private static let moduleBuildDescriptions = [
    "Swift module",
    "Clang module",
    "bridging header",
  ]

  private func getCompiledBasenames(from d: Diagnostic) -> [String] {
    let dd = d.description
    guard let startOfSources = dd.range(of: "Starting Compiling ")?.upperBound
    else {
      return []
    }
    let sources = dd.suffix(from: startOfSources)
    guard !Self.moduleBuildDescriptions.contains(where: { sources.hasPrefix($0) })
    else {
      return []
    }
    return sources
      .split(separator: ",")
      .map {$0.drop(while: {$0 == " "})}
      .compactMap { (s: Substring) -> String? in
        guard s.hasSuffix(".swift") else {
          Issue.record("Job lifecycle reported compiling '\(s)', which is not a Swift source")
          return nil
        }
        return String(s)
      }
  }

  private func getReadDependencies(from d: Diagnostic) -> String? {
    let dd = d.description
    guard let startOfReading = dd.range(of: "Reading dependencies ")?.upperBound
    else {
      return nil
    }
    return String(dd.suffix(from: startOfReading))
  }

  private mutating func appendReadDependency(_ dep: String) {
    let wasNew = collectedReadDependencies.insert(dep).inserted
    guard wasNew || dep.hasSuffix(FileType.swift.rawValue)
    else {
      Issue.record("Swiftmodule \(dep) read twice")
      return
    }
  }

  /// Process a diagnostic
  mutating func handle(diagnostic d: Diagnostic) {
    collectedCompiledBasenames.append(contentsOf: getCompiledBasenames(from: d))
    getReadDependencies(from: d).map {appendReadDependency($0)}
  }

  /// Returns the basenames of the compiled files, e.g. for `/a/b/foo.swift`, returns `foo.swift`.
  var compiledBasenames: [String] {
    #expect(Set(collectedCompiledBasenames).count == collectedCompiledBasenames.count,
                   "No file should be compiled twice")
    return collectedCompiledBasenames
  }
}
