//===--------------- ModuleDependencyScanning.swift -----------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import TSCBasic
import SwiftOptions

internal extension Driver {
  /// Precompute the dependencies for a given Swift compilation, producing a
  /// dependency graph including all Swift and C module files and
  /// source files.
  mutating func dependencyScanningJob() throws -> Job {
    let (inputs, commandLine) = try dependencyScannerInvocationCommand()

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: VirtualPath.absolute(try toolchain.getToolPath(.swiftCompiler)),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               primaryInputs: [],
               outputs: [TypedVirtualPath(file: .standardOutput, type: .jsonDependencies)],
               supportsResponseFiles: true)
  }

  /// Generate a full command-line invocation to be used for the dependency scanning action
  /// on the target module.
  mutating func dependencyScannerInvocationCommand()
  throws -> ([TypedVirtualPath],[Job.ArgTemplate]) {
    // Aggregate the fast dependency scanner arguments
    var inputs: [TypedVirtualPath] = []
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)
    // FIXME: MSVC runtime flags

    // Pass in external target dependencies to be treated as placeholder dependencies by the scanner
    if let externalBuildArtifacts = externalBuildArtifacts {
      let dependencyPlaceholderMapFile =
        try serializeExternalDependencyArtifacts(externalBuildArtifacts: externalBuildArtifacts)
      commandLine.appendFlag("-placeholder-dependency-module-map-file")
      commandLine.appendPath(dependencyPlaceholderMapFile)
    }

    // Pass on the input files
    commandLine.append(contentsOf: inputFiles.map { .path($0.file)})
    return (inputs, commandLine)
  }

  /// Serialize a map of placeholder (external) dependencies for the dependency scanner.
  func serializeExternalDependencyArtifacts(externalBuildArtifacts: ExternalBuildArtifacts)
  throws -> VirtualPath {
    let (externalTargetModulePathMap, externalModuleInfoMap)  = externalBuildArtifacts
    var placeholderArtifacts: [SwiftModuleArtifactInfo] = []

    // Explicit external targets
    for (moduleId, binaryModulePath) in externalTargetModulePathMap {
      placeholderArtifacts.append(
          SwiftModuleArtifactInfo(name: moduleId.moduleName,
                                  modulePath: TextualVirtualPath(path:
                                                    .absolute(binaryModulePath))))
    }

    // All other already-scanned Swift modules
    for (moduleId, moduleInfo) in externalModuleInfoMap
    where !externalTargetModulePathMap.keys.contains(moduleId) {
      guard case .swift(_) = moduleId else { continue }
      placeholderArtifacts.append(
          SwiftModuleArtifactInfo(name: moduleId.moduleName,
                                  modulePath: moduleInfo.modulePath))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(placeholderArtifacts)
    return .temporaryWithKnownContents(.init("\(moduleOutputInfo.name)-placeholder-modules.json"),
                                       contents)
  }

  fileprivate func itemizedJobCommand(of job: Job, forceResponseFiles: Bool,
                                      using resolver: ArgsResolver) throws -> [String] {
    let (args, _) = try resolver.resolveArgumentList(for: job,
                                                     forceResponseFiles: forceResponseFiles,
                                                     quotePaths: true)
    return args
  }

  mutating func performDependencyScan() throws -> InterModuleDependencyGraph {
    let scannerJob = try dependencyScanningJob()
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)
    let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory!
    var command = try itemizedJobCommand(of: scannerJob,
                                         forceResponseFiles: forceResponseFiles,
                                         using: executor.resolver)
    // Remove the tool executable to only leave the arguments
    command.removeFirst()
    let dependencyGraph =
      try interModuleDependencyOracle.getDependencies(workingDirectory: cwd,
                                                      commandLine: command)
    return dependencyGraph
  }

  mutating func performBatchDependencyScan(moduleInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    let batchScanningJob = try batchDependencyScanningJob(for: moduleInfos)
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)
    let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory!
    var command = try itemizedJobCommand(of: batchScanningJob,
                                         forceResponseFiles: forceResponseFiles,
                                         using: executor.resolver)
    // Remove the tool executable to only leave the arguments
    command.removeFirst()
    let moduleVersionedGraphMap =
      try interModuleDependencyOracle.getBatchDependencies(workingDirectory: cwd,
                                                           commandLine: command,
                                                           batchInfos: moduleInfos)
    return moduleVersionedGraphMap
  }

  /// Precompute the dependencies for a given collection of modules using swift frontend's batch scanning mode
  mutating func batchDependencyScanningJob(for moduleInfos: [BatchScanModuleInfo]) throws -> Job {
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    // The dependency scanner automatically operates in batch mode if -batch-scan-input-file
    // is present.
    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)

    let batchScanInputFilePath = try serializeBatchScanningModuleArtifacts(moduleInfos: moduleInfos)
    commandLine.appendFlag("-batch-scan-input-file")
    commandLine.appendPath(batchScanInputFilePath)

    // This action does not require any input files, but all frontend actions require
    // at least one input so pick any input of the current compilation.
    let inputFile = inputFiles.first { $0.type == .swift }
    commandLine.appendPath(inputFile!.file)
    inputs.append(inputFile!)

    // This job's outputs are defined as a set of dependency graph json files
    let outputs: [TypedVirtualPath] = try moduleInfos.map {
      switch $0 {
        case .swift(let swiftModuleBatchScanInfo):
          return TypedVirtualPath(file: try VirtualPath(path: swiftModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
        case .clang(let clangModuleBatchScanInfo):
          return TypedVirtualPath(file: try VirtualPath(path: clangModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
      }
    }

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: VirtualPath.absolute(try toolchain.getToolPath(.swiftCompiler)),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               primaryInputs: [],
               outputs: outputs,
               supportsResponseFiles: true)
  }

  /// Serialize a collection of modules into an input format expected by the batch module dependency scanner.
  func serializeBatchScanningModuleArtifacts(moduleInfos: [BatchScanModuleInfo])
  throws -> VirtualPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(moduleInfos)
    return .temporaryWithKnownContents(.init("\(moduleOutputInfo.name)-batch-module-scan.json"),
                                       contents)
  }
}
