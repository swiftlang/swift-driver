//===-------------- swift -------------===//
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
import XCTest
import TSCBasic

public struct ExpectedProcessResult {
  let output: String
  let stderrOutput: String
  let expectedExitCode: Int32

  public init(output: String = "", stderrOutput: String = "", exitCode: Int32 = 0) {
    self.output = output
    self.stderrOutput = stderrOutput
    self.expectedExitCode = exitCode
  }

  func check(against actual: ProcessResult?, step: Step, in context: Context) throws {
    guard let actual = actual else {
      context.fail("No result", step)
      return
    }
    guard case let .terminated(actualExitCode) = actual.exitStatus
    else {
      context.fail("failed to run", step)
      return
    }
    XCTAssertEqual(actualExitCode, expectedExitCode,
                   context.failMessage(step),
                   file: context.file, line: context.line)
    try XCTAssertEqual(output, actual.utf8Output().spm_chomp(),
                       context.failMessage(step),
                   file: context.file, line: context.line)
    try XCTAssertEqual(stderrOutput, actual.utf8stderrOutput().spm_chomp(),
                       context.failMessage(step),
                   file: context.file, line: context.line)
  }
}
