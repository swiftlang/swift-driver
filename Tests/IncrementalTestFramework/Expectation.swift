//===-- Expectation.swift - Swift Testing ----===//
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

/// Everything expected from a step.
public struct Expectation {
  let compilations: ExpectedCompilations

  /// If non-nil, the step produces an executable, and running it should produce this result.
  let output: ExpectedProcessResult?

  init(_ compilations: ExpectedCompilations, _ output: ExpectedProcessResult? = nil) {
    self.compilations = compilations
    self.output = output
  }

  public static func expecting(_ compilations: ExpectedCompilations,
                               _ output: ExpectedProcessResult? = nil
  ) -> Self {
    self.init(compilations, output)
  }

  public static func expecting(_ compilations: ExpectedCompilations, _ output: String
  ) -> Self {
    self.init(compilations, ExpectedProcessResult(output: output))
  }
}
