//===--------------- IncrementalImportTests.swift - Swift Testing ---------===//
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

struct Expectation<Source: SourceProtocol> {
  private let withIncrementalImports: [Source]
  private let withoutIncrementalImports: [Source]

  private init(with: [Source], without: [Source]) {
    self.withIncrementalImports = with
    self.withoutIncrementalImports = without
  }

  static func expecting(with: [Source], without: [Source]) -> Self {
    self.init(with: with, without: without)
  }

//xxx  static func expecting(with: [Source]) -> Self {
//    self.init(with: with, without: Source.originals)
//  }


  private func expecting(_ context: TestContext) -> [Source] {
    context.withIncrementalImports ? withIncrementalImports : withoutIncrementalImports
  }

  func check(against actual: [Source], _ context: TestContext, stepName: String) {
    let expected = expecting(context)

    XCTAssertEqual(
      actual   .map {$0.name} .sorted(),
      expected .map {$0.name} .sorted(),
      "Actual != Expected, \(context), step \(stepName)",
      file: context.testFile, line: context.testLine)
  }
}
