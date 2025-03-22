//===- VerifyModuleInterface.swift - Swift Module Interface Verification --===//
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

extension Driver {
  mutating func computeCacheKeyForInterface(emitModuleJob: Job,
                                            interfaceKind: FileType) throws -> String? {
    assert(interfaceKind == .swiftInterface || interfaceKind == .privateSwiftInterface || interfaceKind == .packageSwiftInterface,
           "only expect interface output kind")
    let isNeeded = emitModuleJob.outputs.contains { $0.type == interfaceKind }
    guard isCachingEnabled && isNeeded else { return nil }

    // Assume swiftinterface file is always the supplementary output for first input file.
    let key =  try computeOutputCacheKey(commandLine: emitModuleJob.commandLine,
                                         index: 0)
    return key
  }

  @_spi(Testing)
  public func supportExplicitModuleVerifyInterface() -> Bool {
    // swift-frontend that has -input-file-key option can support explicit module build for verify interface.
    return isFrontendArgSupported(.inputFileKey)
  }

  mutating func verifyModuleInterfaceJob(interfaceInput: TypedVirtualPath, emitModuleJob: Job, reportAsError: Bool) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = [interfaceInput]
    commandLine.appendFlags("-frontend", "-typecheck-module-from-interface")
    try addPathArgument(interfaceInput.file, to: &commandLine)
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .verifyModuleInterface, bridgingHeaderHandling: .ignored)
    try addRuntimeLibraryFlags(commandLine: &commandLine)

    // Output serialized diagnostics for this job, if specifically requested
    var outputs: [TypedVirtualPath] = []
    if let outputPath = try outputFileMap?.existingOutput(inputFile: interfaceInput.fileHandle,
                                                      outputType: .diagnostics) {
      outputs.append(TypedVirtualPath(file: outputPath, type: .diagnostics))
    }

    if parsedOptions.contains(.driverExplicitModuleBuild) && supportExplicitModuleVerifyInterface() {
      commandLine.appendFlag("-explicit-interface-module-build")
      if let key = try computeCacheKeyForInterface(emitModuleJob: emitModuleJob, interfaceKind: interfaceInput.type) {
        commandLine.appendFlag("-input-file-key")
        commandLine.appendFlag(key)
      }
    }

    // TODO: remove this because we'd like module interface errors to fail the build.
    if isFrontendArgSupported(.downgradeTypecheckInterfaceError) &&
        (!reportAsError ||
         // package interface is new and should not be a blocker for now
         interfaceInput.type == .packageSwiftInterface) {
      commandLine.appendFlag(.downgradeTypecheckInterfaceError)
    }

    let cacheKeys = try computeOutputCacheKeyForJob(commandLine: commandLine, inputs: [(interfaceInput, 0)])
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .verifyModuleInterface,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [interfaceInput],
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs,
      outputCacheKeys: cacheKeys
    )
  }
}
