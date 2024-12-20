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
import protocol Foundation.LocalizedError
import var Foundation.EXIT_SUCCESS

extension Driver {
  /// Initializer which creates an executor suitable for use in tests.
  public init(
    args: [String],
    env: [String: String] = ProcessEnv.vars,
    diagnosticsEngine: DiagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
    fileSystem: FileSystem = localFileSystem,
    integratedDriver: Bool = true,
    interModuleDependencyOracle: InterModuleDependencyOracle? = nil
  ) throws {
    let executor = try SwiftDriverExecutor(diagnosticsEngine: diagnosticsEngine,
                                       processSet: ProcessSet(),
                                       fileSystem: fileSystem,
                                       env: env)
    try self.init(args: args,
                  env: env,
                  diagnosticsOutput: .engine(diagnosticsEngine),
                  fileSystem: fileSystem,
                  executor: executor,
                  integratedDriver: integratedDriver,
                  interModuleDependencyOracle: interModuleDependencyOracle)
  }

  /// For tests that need to set the sdk path.
  /// Only works on hosts with `xcrun`, so return nil if cannot work on current host.
  public static func sdkArgumentsForTesting() throws -> [String]? {
    try cachedSDKPath.map {["-sdk", try $0.get()]}
  }
}

/// Set to nil if cannot perform on this host
private let cachedSDKPath: Result<String, Error>? = {
  #if os(Windows)
  if let sdk = ProcessEnv.block["SDKROOT"] {
    return Result{sdk}
  }
  // Assume that if neither of the environment variables are set, we are
  // using a build-tree version of the swift frontend, and so we do not set
  // `-sdk`.
  return nil
  #elseif os(macOS)
  return Result {
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
    guard let path = String(bytes: try result.output.get(), encoding: .utf8)
    else {
      enum Error: LocalizedError {
        case couldNotUnwrapSDKPath
      }
      throw Error.couldNotUnwrapSDKPath
    }
    return path.spm_chomp()
  }
  #else
  return nil
  #endif
}()
