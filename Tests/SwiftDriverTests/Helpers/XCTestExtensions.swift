//===-------- AssertDiagnostics.swift - Diagnostic Test Assertions --------===//
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

import XCTest
import SwiftDriver

internal func XCTAssertCommandLineContains(_ commandline: [Job.ArgTemplate],
                                           _ subsequence: Job.ArgTemplate...,
                                           file: StaticString = #file,
                                           line: UInt = #line) {
  if !commandline.contains(subsequence: subsequence) {
    XCTFail("\(commandline) does not contain \(subsequence)", file: file, line: line)
  }
}

internal func XCTAssertJobInvocationMatches(_ job: Job,
                                            _ subsequence: Job.ArgTemplate...,
                                            file: StaticString = #file,
                                            line: UInt = #line) {
  if !job.commandLine.contains(subsequence: subsequence) {
    XCTFail("\(job.commandLine) does not contain \(subsequence)", file: file, line: line)
  }
}
