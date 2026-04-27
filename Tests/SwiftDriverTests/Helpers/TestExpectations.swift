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

import SwiftDriver
import Testing

internal func expectCommandLineContains(
  _ commandline: [Job.ArgTemplate],
  _ subsequence: Job.ArgTemplate...,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    commandline.contains(subsequence: subsequence),
    "\(commandline) does not contain \(subsequence)",
    sourceLocation: sourceLocation
  )
}

internal func expectJobInvocationMatches(
  _ job: Job,
  _ subsequence: Job.ArgTemplate...,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    job.commandLine.contains(subsequence: subsequence),
    "\(job.commandLine) does not contain \(subsequence)",
    sourceLocation: sourceLocation
  )
}
