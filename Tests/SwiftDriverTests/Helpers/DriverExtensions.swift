//===-------- DriverExtensions.swift - Driver Testing Extensions ----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import TSCBasic
import XCTest

extension Driver {
  /// Initializer which creates an executor suitable for use in tests.
  init(
    args: [String],
    env: [String: String] = ProcessEnv.vars,
    diagnosticsEngine: DiagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
    fileSystem: FileSystem = localFileSystem
  ) throws {
    let executor = try SwiftDriverExecutor(diagnosticsEngine: diagnosticsEngine,
                                       processSet: ProcessSet(),
                                       fileSystem: fileSystem,
                                       env: env)
    var augmentedArgs = args
    // Color codes in diagnostics cause mismatches
    augmentedArgs.append("-no-color-diagnostics")
    // The frontend fails to load the standard library because it cannot
    // find it relative to the execution path used by the Swift Driver.
    // So, pass in the sdk path explicitly.
    if !args.contains("-sdk") {
      augmentedArgs.append(contentsOf: ["-sdk", try cachedSDKPath.get()])
    }

    try self.init(
      args: augmentedArgs,
      env: env,
      diagnosticsEngine: diagnosticsEngine,
      fileSystem: fileSystem,
      executor: executor)
  }
}

private let cachedSDKPath = Result<String, Error> {
  if let pathFromEnv = ProcessEnv.vars["SDKROOT"] {
    return pathFromEnv
  }
  let process = Process(arguments: ["xcrun", "-sdk", "macosx", "--show-sdk-path"])
  try process.launch()
  let result = try process.waitUntilExit()
  guard result.exitStatus == .terminated(code: EXIT_SUCCESS) else {
    enum XCRunFailure: LocalizedError {
      case xcrunFailure
    }
    throw XCRunFailure.xcrunFailure
  }
  return try XCTUnwrap(String(bytes: try result.output.get(), encoding: .utf8))
    .spm_chomp()
}
