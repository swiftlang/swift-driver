//===---------- CompiledSourceCollector.swift - Swift Testing -------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
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

  private func getCompiledBasenames(from d: Diagnostic) -> [String] {
    let dd = d.description
    guard let startOfSources = dd.range(of: "Starting Compiling ")?.upperBound
    else {
      return []
    }
    return dd.suffix(from: startOfSources)
      .split(separator: ",")
      .map {$0.drop(while: {$0 == " "})}
      .map { (s: Substring) -> Substring in
        assert(s.hasSuffix(".swift"))
        return s
      }
      .compactMap {String($0)}
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
      XCTFail("Swiftmodule \(dep) read twice")
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
    XCTAssertEqual(Set(collectedCompiledBasenames).count, collectedCompiledBasenames.count,
                   "No file should be compiled twice")
    return collectedCompiledBasenames
  }
}
