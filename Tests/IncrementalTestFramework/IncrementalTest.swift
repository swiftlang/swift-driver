//===------------- PhasedTest.swift - Swift Testing ---------------------===//
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
  ///   - file: Determines where any test failure messages will appear in Xcode
  ///   - line: Ditto
  public static func perform(
    _ steps: [Step],
    verbose: Bool = false,
    file: StaticString = #file,
    line: UInt = #line
  ) throws {
    try perform(steps: steps,
                verbose: verbose,
                file: file,
                line: line)
  }
  private static func perform(steps: [Step],
                              verbose: Bool,
                              file: StaticString,
                              line: UInt
  ) throws {
    try withTemporaryDirectory { rootDir in
      try localFileSystem.changeCurrentWorkingDirectory(to: rootDir)
      for file in try localFileSystem.getDirectoryContents(rootDir) {
        try localFileSystem.removeFileTree(rootDir.appending(component: file))
      }
      try Self(steps: steps,
               context: Context(rootDir: rootDir,
                                verbose: verbose,
                                stepIndex: 0,
                                file: file,
                                line: line))
        .performSteps()
    }
  }

  private init(steps: [Step], context: Context) {
    self.steps = steps
    self.context = context
  }
  private func performSteps() throws {
    for (index, step) in steps.enumerated() {
      if context.verbose {
        print("\(index)", terminator: " ")
      }
      try step.perform(stepIndex: index, in: context)
    }
    if context.verbose {
      print("")
    }
  }
}

