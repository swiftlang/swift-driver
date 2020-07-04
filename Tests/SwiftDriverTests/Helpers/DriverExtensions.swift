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

import SwiftDriver
import TSCBasic

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
    try self.init(args: args,
                  env: env,
                  diagnosticsEngine: diagnosticsEngine,
                  fileSystem: fileSystem,
                  executor: executor)
  }
}
