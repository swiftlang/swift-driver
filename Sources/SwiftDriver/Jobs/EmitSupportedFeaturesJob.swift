//===---- EmitSupportedFeatures.swift - Swift Compiler Features Info Job ----===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===////

import SwiftOptions
import struct Foundation.Data
import class Foundation.JSONDecoder
import struct TSCBasic.Diagnostic
import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.FileSystem
import struct TSCBasic.RelativePath
import var TSCBasic.localFileSystem

/// Describes information about the compiler's supported arguments and features
@_spi(Testing) public struct SupportedCompilerFeatures: Codable {
  var SupportedArguments: [String]
  var SupportedFeatures: [String]
}

extension Toolchain {
  func emitSupportedCompilerFeaturesJob(requiresInPlaceExecution: Bool = false,
                                        swiftCompilerPrefixArgs: [String]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    commandLine.append(contentsOf: [.flag("-frontend"),
                                    .flag("-emit-supported-features")])

    // This action does not require any input files, but all frontend actions require
    // at least one so we fake it.
    // FIXME: Teach -emit-supported-features to not expect any inputs, like -print-target-info does.
    let dummyInputPath =
      try VirtualPath.createUniqueTemporaryFileWithKnownContents(.init(validating: "dummyInput.swift"),
                                                                 "".data(using: .utf8)!)
    commandLine.appendPath(dummyInputPath)
    inputs.append(TypedVirtualPath(file: dummyInputPath.intern(), type: .swift))

    return Job(
      moduleName: "",
      kind: .emitSupportedFeatures,
      tool: try resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: [.init(file: .standardOutput, type: .jsonCompilerFeatures)],
      requiresInPlaceExecution: requiresInPlaceExecution
    )
  }
}

extension Driver {

  static func computeSupportedCompilerArgs(of toolchain: Toolchain,
                                           libSwiftScan: SwiftScan?,
                                           parsedOptions: inout ParsedOptions,
                                           diagnosticsEngine: DiagnosticsEngine,
                                           fileSystem: FileSystem,
                                           executor: DriverExecutor)
  throws -> Set<String> {
    if let libSwiftScanInstance = libSwiftScan,
       libSwiftScanInstance.canQuerySupportedArguments() {
      do {
        return try libSwiftScanInstance.querySupportedArguments()
      } catch {
        diagnosticsEngine.emit(.remark_inprocess_supported_features_query_failed(error.localizedDescription))
      }
    }

    // Fallback: Invoke `swift-frontend -emit-supported-features` and decode the output
    let frontendOverride = try FrontendOverride(&parsedOptions, diagnosticsEngine)
    frontendOverride.setUpForTargetInfo(toolchain)
    defer { frontendOverride.setUpForCompilation(toolchain) }
    let frontendFeaturesJob =
      try toolchain.emitSupportedCompilerFeaturesJob(swiftCompilerPrefixArgs:
                                                      frontendOverride.prefixArgsForTargetInfo)
    let decodedSupportedFlagList = try executor.execute(
      job: frontendFeaturesJob,
      capturingJSONOutputAs: SupportedCompilerFeatures.self,
      forceResponseFiles: false,
      recordedInputModificationDates: [:]).SupportedArguments
    return Set(decodedSupportedFlagList)
  }

  static func computeSupportedCompilerFeatures(of toolchain: Toolchain,
                                               env: [String: String]) throws -> Set<String> {
    struct FeatureInfo: Codable {
      var name: String
    }
    struct FeatureList: Codable {
      var features: [FeatureInfo]
    }
    let jsonPath = try getRootPath(of: toolchain, env: env)
      .appending(component: "share")
      .appending(component: "swift")
      .appending(component: "features.json")
    guard localFileSystem.exists(jsonPath) else {
      return Set<String>()
    }
    let content = try localFileSystem.readFileContents(jsonPath)
    let result = try JSONDecoder().decode(FeatureList.self, from: Data(content.contents))
    return Set(result.features.map {$0.name})
  }
}
