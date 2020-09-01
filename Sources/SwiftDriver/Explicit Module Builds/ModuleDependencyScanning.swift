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

extension Driver {
  /// Precompute the dependencies for a given Swift compilation, producing a
  /// dependency graph including all Swift and C module files and
  /// source files.
  mutating func dependencyScanningJob() throws -> Job {
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    if parsedOptions.hasArgument(.parseStdlib) {
       commandLine.appendFlag(.disableObjcAttrRequiresFoundationModule)
    }
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)
    // FIXME: MSVC runtime flags

    // Pass in external dependencies to be treated as placeholder dependencies by the scanner
    if let externalDependencyArtifactMap = externalDependencyArtifactMap {
      let dependencyPlaceholderMapFile =
        try serializeExternalDependencyArtifacts(externalDependencyArtifactMap:
                                                  externalDependencyArtifactMap)
      commandLine.appendFlag("-placeholder-dependency-module-map-file")
      commandLine.appendPath(dependencyPlaceholderMapFile)
    }

    // Pass on the input files
    commandLine.append(contentsOf: inputFiles.map { .path($0.file)})

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: VirtualPath.absolute(try toolchain.getToolPath(.swiftCompiler)),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               outputs: [TypedVirtualPath(file: .standardOutput, type: .jsonDependencies)],
               supportsResponseFiles: true)
  }

  /// Serialize a map of placeholder (external) dependencies for the dependency scanner.
  func serializeExternalDependencyArtifacts(externalDependencyArtifactMap: ExternalDependencyArtifactMap)
  throws -> AbsolutePath {
    let temporaryDirectory = try determineTempDirectory()
    let placeholderMapFilePath =
      temporaryDirectory.appending(component: "\(moduleOutputInfo.name)-placeholder-modules.json")

    var placeholderArtifacts: [SwiftModuleArtifactInfo] = []
    for (moduleId, dependencyInfo) in externalDependencyArtifactMap {
      placeholderArtifacts.append(
          SwiftModuleArtifactInfo(name: moduleId.moduleName,
                                  modulePath: dependencyInfo.0.description))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(placeholderArtifacts)
    try fileSystem.writeFileContents(placeholderMapFilePath, bytes: ByteString(contents))
    return placeholderMapFilePath
  }

  /// Compute the dependencies for a given Clang module, by invoking the Clang dependency scanning action
  /// with the given module's name and a set of arguments (including the target version)
  mutating func clangDependencyScanningJob(moduleId: ModuleDependencyId,
                                           pcmArgs: [String]) throws -> Job {
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-clang-dependencies")

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)

    // Ensure the `-target` option is inherited from the dependent Swift module's PCM args
    if let targetOptionIndex = pcmArgs.firstIndex(of: Option.target.spelling) {
      // PCM args are formulated as Clang command line options specified with:
      // -Xcc <option> -Xcc <option_value>
      assert(pcmArgs.count > targetOptionIndex + 1 && pcmArgs[targetOptionIndex + 1] == "-Xcc")
      let pcmArgTriple = Triple(pcmArgs[targetOptionIndex + 2])
      // Override the invocation's default target argument by appending the one extracted from
      // the pcmArgs
      commandLine.appendFlag(.target)
      commandLine.appendFlag(pcmArgTriple.triple)
    }

    // Add the PCM args specific to this scan
    pcmArgs.forEach { commandLine.appendFlags($0) }

    // This action does not require any input files, but all frontend actions require
    // at least one input so pick any input of the current compilation.
    let inputFile = inputFiles.first { $0.type == .swift }
    commandLine.appendPath(inputFile!.file)
    inputs.append(inputFile!)

    commandLine.appendFlags("-module-name", moduleId.moduleName)
    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanClangDependencies,
               tool: VirtualPath.absolute(try toolchain.getToolPath(.swiftCompiler)),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               outputs: [TypedVirtualPath(file: .standardOutput, type: .jsonDependencies)],
               supportsResponseFiles: true)
  }

  mutating func scanClangModule(moduleId: ModuleDependencyId, pcmArgs: [String])
  throws -> InterModuleDependencyGraph {
    let clangDependencyScannerJob = try clangDependencyScanningJob(moduleId: moduleId,
                                                                   pcmArgs: pcmArgs)
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)

    let dependencyGraph =
      try self.executor.execute(job: clangDependencyScannerJob,
                                capturingJSONOutputAs: InterModuleDependencyGraph.self,
                                forceResponseFiles: forceResponseFiles,
                                recordedInputModificationDates: recordedInputModificationDates)
    return dependencyGraph
  }
}
