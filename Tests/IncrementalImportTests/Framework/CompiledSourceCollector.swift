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

/// Creates a `DiagnosticsEngine` that collects which sources were compiled
/// (See `TestProtocol`.)
struct CompiledSourceCollector<Source: SourceProtocol> {
  private var collectedCompiledSources = [Source]()

  private func getCompiledSources(from d: Diagnostic) -> [Source] {
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
        return s.dropLast(".swift".count)
      }
      .compactMap {Source(rawValue: String($0))}
  }

  mutating func handle(diagnostic d: Diagnostic) {
    collectedCompiledSources.append(contentsOf: getCompiledSources(from: d))
  }

  func compiledSources(_ context: TestContext) ->  [Source] {
    XCTAssertEqual(Set(collectedCompiledSources).count, collectedCompiledSources.count,
                   "No file should be compiled twice",
                   file: context.testFile, line: context.testLine)
    return collectedCompiledSources
  }
}
