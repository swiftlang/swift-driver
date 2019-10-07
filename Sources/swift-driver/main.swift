//===--------------- main.swift - Swift Driver Main Entrypoint ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import SwiftDriver

import TSCLibc
import TSCBasic
import TSCUtility

var intHandler: InterruptHandler?

do {
  let processSet = ProcessSet()
  intHandler = try InterruptHandler {
    processSet.terminate()
  }

  var driver = try Driver(args: CommandLine.arguments)
  let resolver = try ArgsResolver()
  try driver.run(resolver: resolver, processSet: processSet)

  if driver.diagnosticEngine.hasErrors {
    exit(EXIT_FAILURE)
  }
} catch Diagnostics.fatalError {
  exit(EXIT_FAILURE)
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
