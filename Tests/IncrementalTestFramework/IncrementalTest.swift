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

/// Performs a test of the incremental logic and incremental import logic in the driver.
/// Runs the test with incremental imports enabled and then disabled.
/// Eacn test is a series of `Step`s.
public struct IncrementalTest {
  /// The `Step`s to run, in order.
  let steps: [Step]

  let context: Context

  /// Runs the test.
  /// - Parameters:
  ///   - steps: The `Step` to run.
  ///   - verbose: Pass `true` to debug a test. Otherwise, omit.
  ///   - sourceLocation: Determines where any test failure messages will appear
  public static func perform(
    _ steps: [Step],
    verbose: Bool = false,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    try await perform(steps: steps,
                verbose: verbose,
                sourceLocation: sourceLocation)
  }
  private static func perform(steps: [Step],
                              verbose: Bool,
                              sourceLocation: SourceLocation
  ) async throws {
    try await withTemporaryDirectory(removeTreeOnDeinit: true) { rootDir in
      for file in try localFileSystem.getDirectoryContents(rootDir) {
        try localFileSystem.removeFileTree(rootDir.appending(component: file))
      }
      try await Self(steps: steps,
               context: Context(rootDir: rootDir,
                                verbose: verbose,
                                stepIndex: 0,
                                sourceLocation: sourceLocation))
        .performSteps()
    }
  }

  private init(steps: [Step], context: Context) {
    self.steps = steps
    self.context = context
  }
  private func performSteps() async throws {
    for (index, step) in steps.enumerated() {
      if context.verbose {
        print("\(index)", terminator: " ")
      }
      try await step.perform(stepIndex: index, in: context)
    }
    if context.verbose {
      print("")
    }
  }
}

