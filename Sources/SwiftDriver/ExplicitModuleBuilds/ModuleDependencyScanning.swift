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

import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath
import struct TSCBasic.Diagnostic
import var TSCBasic.localFileSystem
import var TSCBasic.stdoutStream

import SwiftOptions
import struct Foundation.Data
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder
import var Foundation.EXIT_SUCCESS

extension Diagnostic.Message {
  static func warn_scan_dylib_not_found() -> Diagnostic.Message {
    .warning("Unable to locate libSwiftScan. Fallback to `swift-frontend` dependency scanner invocation.")
  }
  static func warn_scan_dylib_load_failed(_ libPath: String) -> Diagnostic.Message {
    .warning("In-process dependency scan query failed due to incompatible libSwiftScan (\(libPath)). Fallback to `swift-frontend` dependency scanner invocation. Specify '-nonlib-dependency-scanner' to silence this warning.")
  }
  static func error_caching_enabled_libswiftscan_load_failure(_ libPath: String) -> Diagnostic.Message {
    .error("Swift Caching enabled - libSwiftScan load failed (\(libPath)).")
  }
  static func scanner_diagnostic_error(_ message: String) -> Diagnostic.Message {
    return .error(message)
  }
  static func scanner_diagnostic_warn(_ message: String) -> Diagnostic.Message {
    .warning(message)
  }
  static func scanner_diagnostic_note(_ message: String) -> Diagnostic.Message {
    .note(message)
  }
  static func scanner_diagnostic_remark(_ message: String) -> Diagnostic.Message {
    .remark(message)
  }
}

@_spi(Testing) public extension Driver {
  /// Scan the current module's input source-files to compute its direct and transitive
  /// module dependencies.
  mutating func gatherModuleDependencies()
  throws -> InterModuleDependencyGraph {
    var dependencyGraph = try performDependencyScan()

    if parsedOptions.hasArgument(.printPreprocessedExplicitDependencyGraph) {
      try stdoutStream.send(dependencyGraph.toJSONString())
      stdoutStream.flush()
    }

    if let externalTargetDetails = externalTargetModuleDetailsMap {
      // Resolve external dependencies in the dependency graph, if any.
      try dependencyGraph.resolveExternalDependencies(for: externalTargetDetails)
    }

    // Re-scan Clang modules at all the targets they will be built against.
    // This is currently disabled because we are investigating it being unnecessary
    // try resolveVersionedClangDependencies(dependencyGraph: &dependencyGraph)

    // Set dependency modules' paths to be saved in the module cache.
    // try resolveDependencyModulePaths(dependencyGraph: &dependencyGraph)

    if parsedOptions.hasArgument(.printExplicitDependencyGraph) {
      let outputFormat = parsedOptions.getLastArgument(.explicitDependencyGraphFormat)?.asSingle
      if outputFormat == nil || outputFormat == "json" {
        try stdoutStream.send(dependencyGraph.toJSONString())
      } else if outputFormat == "dot" {
        DOTModuleDependencyGraphSerializer(dependencyGraph).writeDOT(to: &stdoutStream)
      }
      stdoutStream.flush()
    }

    return dependencyGraph
  }
}

public extension Driver {
  /// Precompute the dependencies for a given Swift compilation, producing a
  /// dependency graph including all Swift and C module files and
  /// source files.
  mutating func dependencyScanningJob() throws -> Job {
    let (inputs, commandLine) = try dependencyScannerInvocationCommand()

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: try toolchain.resolvedTool(.swiftCompiler),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               primaryInputs: [],
               outputs: [TypedVirtualPath(file: .standardOutput, type: .jsonDependencies)])
  }

  /// Generate a full command-line invocation to be used for the dependency scanning action
  /// on the target module.
  @_spi(Testing) mutating func dependencyScannerInvocationCommand()
  throws -> ([TypedVirtualPath],[Job.ArgTemplate]) {
    // Aggregate the fast dependency scanner arguments
    var inputs: [TypedVirtualPath] = []
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .scanDependencies,
                                 bridgingHeaderHandling: .parsed,
                                 moduleDependencyGraphUse: .dependencyScan)
    // FIXME: MSVC runtime flags

    // Pass in external target dependencies to be treated as placeholder dependencies by the scanner
    if let externalTargetDetailsMap = externalTargetModuleDetailsMap,
       interModuleDependencyOracle.scannerRequiresPlaceholderModules {
      let dependencyPlaceholderMapFile =
      try serializeExternalDependencyArtifacts(externalTargetDependencyDetails: externalTargetDetailsMap)
      commandLine.appendFlag("-placeholder-dependency-module-map-file")
      commandLine.appendPath(dependencyPlaceholderMapFile)
    }

    if isFrontendArgSupported(.clangScannerModuleCachePath) {
      try commandLine.appendLast(.clangScannerModuleCachePath, from: &parsedOptions)
    }

    if isFrontendArgSupported(.scannerPrefixMap) {
      // construct `-scanner-prefix-mapper` for scanner.
      for (key, value) in prefixMapping {
        commandLine.appendFlag(.scannerPrefixMap)
        commandLine.appendFlag(key.pathString + "=" + value.pathString)
      }
    }

    // Pass on the input files
    commandLine.append(contentsOf: inputFiles.filter { $0.type == .swift }.map { .path($0.file) })
    return (inputs, commandLine)
  }

  /// Serialize a map of placeholder (external) dependencies for the dependency scanner.
   private func serializeExternalDependencyArtifacts(externalTargetDependencyDetails: ExternalTargetModuleDetailsMap)
   throws -> VirtualPath {
     var placeholderArtifacts: [SwiftModuleArtifactInfo] = []
     // Explicit external targets
     for (moduleId, dependencyDetails) in externalTargetDependencyDetails {
       let modPath = TextualVirtualPath(path: VirtualPath.absolute(dependencyDetails.path).intern())
       placeholderArtifacts.append(
           SwiftModuleArtifactInfo(name: moduleId.moduleName,
                                   modulePath: modPath))
     }
     let encoder = JSONEncoder()
     encoder.outputFormatting = [.prettyPrinted]
     let contents = try encoder.encode(placeholderArtifacts)
     return try VirtualPath.createUniqueTemporaryFileWithKnownContents(.init(validating: "\(moduleOutputInfo.name)-external-modules.json"),
                                                                       contents)
  }

  /// Returns false if the lib is available and ready to use
  private mutating func initSwiftScanLib() throws -> Bool {
    // `-nonlib-dependency-scanner` was specified
    guard !parsedOptions.hasArgument(.driverScanDependenciesNonLib) else {
      return true
    }

    // If the libSwiftScan library cannot be found,
    // attempt to fallback to using `swift-frontend -scan-dependencies` invocations for dependency
    // scanning.
    guard let scanLibPath = try toolchain.lookupSwiftScanLib(),
          fileSystem.exists(scanLibPath) else {
      diagnosticEngine.emit(.warn_scan_dylib_not_found())
      return true
    }

    do {
      try interModuleDependencyOracle.verifyOrCreateScannerInstance(fileSystem: fileSystem,
                                                                    swiftScanLibPath: scanLibPath)
      if isCachingEnabled {
        self.cas = try interModuleDependencyOracle.getOrCreateCAS(pluginPath: try getCASPluginPath(),
                                                                  onDiskPath: try getOnDiskCASPath(),
                                                                  pluginOptions: try getCASPluginOptions())
      }
    } catch {
      if isCachingEnabled {
        diagnosticEngine.emit(.error_caching_enabled_libswiftscan_load_failure(scanLibPath.description))
      } else {
        diagnosticEngine.emit(.warn_scan_dylib_load_failed(scanLibPath.description))
      }
      return true
    }
    return false
  }

  static func sanitizeCommandForLibScanInvocation(_ command: inout [String]) {
    // Remove the tool executable to only leave the arguments. When passing the
    // command line into libSwiftScan, the library is itself the tool and only
    // needs to parse the remaining arguments.
    command.removeFirst()
    // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
    // able to launch them as standalone jobs. Frontend's argument parser won't recognize
    // -frontend when passed directly.
    if command.first == "-frontend" {
      command.removeFirst()
    }
  }

  mutating func performImportPrescan() throws -> InterModuleDependencyImports {
    let preScanJob = try importPreScanningJob()
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)
    let imports: InterModuleDependencyImports

    let isSwiftScanLibAvailable = !(try initSwiftScanLib())
    if isSwiftScanLibAvailable {
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory!
      var command = try Self.itemizedJobCommand(of: preScanJob,
                                                useResponseFiles: .disabled,
                                                using: executor.resolver)
      Self.sanitizeCommandForLibScanInvocation(&command)
      do {
        imports = try interModuleDependencyOracle.getImports(workingDirectory: cwd,
                                                             moduleAliases: moduleOutputInfo.aliases,
                                                             commandLine: command,
                                                             diagnostics: &scanDiagnostics)
      } catch let DependencyScanningError.dependencyScanFailed(reason) {
        try emitGlobalScannerDiagnostics()
        throw DependencyScanningError.dependencyScanFailed(reason)
      }
      try emitGlobalScannerDiagnostics()
    } else {
      // Fallback to legacy invocation of the dependency scanner with
      // `swift-frontend -scan-dependencies -import-prescan`
      imports =
        try self.executor.execute(job: preScanJob,
                                  capturingJSONOutputAs: InterModuleDependencyImports.self,
                                  forceResponseFiles: forceResponseFiles,
                                  recordedInputModificationDates: recordedInputModificationDates)
    }
    return imports
  }

  internal func emitScannerDiagnostics(_ diagnostics: [ScannerDiagnosticPayload]) throws {
      for diagnostic in diagnostics {
        switch diagnostic.severity {
        case .error:
          diagnosticEngine.emit(.scanner_diagnostic_error(diagnostic.message),
                                location: diagnostic.sourceLocation)
        case .warning:
          diagnosticEngine.emit(.scanner_diagnostic_warn(diagnostic.message),
                                location: diagnostic.sourceLocation)
        case .note:
          diagnosticEngine.emit(.scanner_diagnostic_note(diagnostic.message),
                                location: diagnostic.sourceLocation)
        case .remark:
          diagnosticEngine.emit(.scanner_diagnostic_remark(diagnostic.message),
                                location: diagnostic.sourceLocation)
        case .ignored:
          diagnosticEngine.emit(.scanner_diagnostic_error(diagnostic.message),
                                location: diagnostic.sourceLocation)
        }
      }
  }

  mutating internal func emitGlobalScannerDiagnostics() throws {
    // We only emit global scanner-collected diagnostics as a legacy flow
    // when the scanner does not support per-scan diagnostic output
    guard try !interModuleDependencyOracle.supportsPerScanDiagnostics() else {
      return
    }
    if let diags = try interModuleDependencyOracle.getScannerDiagnostics() {
      try emitScannerDiagnostics(diags)
    }
  }

  mutating func performDependencyScan() throws -> InterModuleDependencyGraph {
    let scannerJob = try dependencyScanningJob()
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)
    let dependencyGraph: InterModuleDependencyGraph

    if parsedOptions.contains(.v) {
      let arguments: [String] = try executor.resolver.resolveArgumentList(for: scannerJob,
                                                                          useResponseFiles: .disabled)
      stdoutStream.send("\(arguments.map { $0.spm_shellEscaped() }.joined(separator: " "))\n")
      stdoutStream.flush()
    }

    let isSwiftScanLibAvailable = !(try initSwiftScanLib())
    if isSwiftScanLibAvailable {
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory!
      var command = try Self.itemizedJobCommand(of: scannerJob,
                                                useResponseFiles: .disabled,
                                                using: executor.resolver)
      Self.sanitizeCommandForLibScanInvocation(&command)
      do {
        dependencyGraph = try interModuleDependencyOracle.getDependencies(workingDirectory: cwd,
                                                                          moduleAliases: moduleOutputInfo.aliases,
                                                                          commandLine: command,
                                                                          diagnostics: &scanDiagnostics)
        try emitScannerDiagnostics(scanDiagnostics)
      } catch let DependencyScanningError.dependencyScanFailed(reason) {
        try emitGlobalScannerDiagnostics()
        throw DependencyScanningError.dependencyScanFailed(reason)
      }
      try emitGlobalScannerDiagnostics()
    } else {
      // Fallback to legacy invocation of the dependency scanner with
      // `swift-frontend -scan-dependencies`
      dependencyGraph =
        try self.executor.execute(job: scannerJob,
                                  capturingJSONOutputAs: InterModuleDependencyGraph.self,
                                  forceResponseFiles: forceResponseFiles,
                                  recordedInputModificationDates: recordedInputModificationDates)
    }
    return dependencyGraph
  }

  mutating internal func performBatchDependencyScan(moduleInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    let batchScanningJob = try batchDependencyScanningJob(for: moduleInfos)
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)
    let moduleVersionedGraphMap: [ModuleDependencyId: [InterModuleDependencyGraph]]

    let isSwiftScanLibAvailable = !(try initSwiftScanLib())
    if isSwiftScanLibAvailable {
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory!
      var command = try Self.itemizedJobCommand(of: batchScanningJob,
                                                useResponseFiles: .disabled,
                                                using: executor.resolver)
      Self.sanitizeCommandForLibScanInvocation(&command)
      moduleVersionedGraphMap =
        try interModuleDependencyOracle.getBatchDependencies(workingDirectory: cwd,
                                                             moduleAliases: moduleOutputInfo.aliases,
                                                             commandLine: command,
                                                             batchInfos: moduleInfos,
                                                             diagnostics: &scanDiagnostics)
    } else {
      // Fallback to legacy invocation of the dependency scanner with
      // `swift-frontend -scan-dependencies`
      moduleVersionedGraphMap = try executeLegacyBatchScan(moduleInfos: moduleInfos,
                                                           batchScanningJob: batchScanningJob,
                                                           forceResponseFiles: forceResponseFiles)
    }
    return moduleVersionedGraphMap
  }

  // Perform a batch scan by invoking the command-line dependency scanner and decoding the resulting
  // JSON.
  fileprivate func executeLegacyBatchScan(moduleInfos: [BatchScanModuleInfo],
                                          batchScanningJob: Job,
                                          forceResponseFiles: Bool)
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    let batchScanResult =
      try self.executor.execute(job: batchScanningJob,
                                forceResponseFiles: forceResponseFiles,
                                recordedInputModificationDates: recordedInputModificationDates)
    let success = batchScanResult.exitStatus == .terminated(code: EXIT_SUCCESS)
    guard success else {
      throw JobExecutionError.jobFailedWithNonzeroExitCode(
        type(of: executor).computeReturnCode(exitStatus: batchScanResult.exitStatus),
        try batchScanResult.utf8stderrOutput())
    }
    // Decode the resulting dependency graphs and build a dictionary from a moduleId to
    // a set of dependency graphs that were built for it
    let moduleVersionedGraphMap =
      try moduleInfos.reduce(into: [ModuleDependencyId: [InterModuleDependencyGraph]]()) {
        let moduleId: ModuleDependencyId
        let dependencyGraphPath: VirtualPath
        switch $1 {
          case .swift(let swiftModuleBatchScanInfo):
            moduleId = .swift(swiftModuleBatchScanInfo.swiftModuleName)
            dependencyGraphPath = try VirtualPath(path: swiftModuleBatchScanInfo.output)
          case .clang(let clangModuleBatchScanInfo):
            moduleId = .clang(clangModuleBatchScanInfo.clangModuleName)
            dependencyGraphPath = try VirtualPath(path: clangModuleBatchScanInfo.output)
        }
        let contents = try fileSystem.readFileContents(dependencyGraphPath)
        let decodedGraph = try JSONDecoder().decode(InterModuleDependencyGraph.self,
                                                    from: Data(contents.contents))
        if $0[moduleId] != nil {
          $0[moduleId]!.append(decodedGraph)
        } else {
          $0[moduleId] = [decodedGraph]
        }
      }
    return moduleVersionedGraphMap
  }

  /// Precompute the set of module names as imported by the current module
  mutating private func importPreScanningJob() throws -> Job {
    // Aggregate the fast dependency scanner arguments
    var inputs: [TypedVirtualPath] = []
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    commandLine.appendFlag("-import-prescan")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .scanDependencies,
                                 bridgingHeaderHandling: .parsed,
                                 moduleDependencyGraphUse: .dependencyScan)
    // FIXME: MSVC runtime flags

    // Pass on the input files
    commandLine.append(contentsOf: inputFiles.map { .path($0.file) })

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: try toolchain.resolvedTool(.swiftCompiler),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               primaryInputs: [],
               outputs: [TypedVirtualPath(file: .standardOutput, type: .jsonDependencies)])
  }

  /// Precompute the dependencies for a given collection of modules using swift frontend's batch scanning mode
  mutating private func batchDependencyScanningJob(for moduleInfos: [BatchScanModuleInfo]) throws -> Job {
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    // The dependency scanner automatically operates in batch mode if -batch-scan-input-file
    // is present.
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .scanDependencies,
                                 bridgingHeaderHandling: .ignored,
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
          return TypedVirtualPath(file: try VirtualPath.intern(path: swiftModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
        case .clang(let clangModuleBatchScanInfo):
          return TypedVirtualPath(file: try VirtualPath.intern(path: clangModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
      }
    }

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: try toolchain.resolvedTool(.swiftCompiler),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               primaryInputs: [],
               outputs: outputs)
  }

  /// Serialize a collection of modules into an input format expected by the batch module dependency scanner.
  func serializeBatchScanningModuleArtifacts(moduleInfos: [BatchScanModuleInfo])
  throws -> VirtualPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(moduleInfos)
    return try VirtualPath.createUniqueTemporaryFileWithKnownContents(.init(validating: "\(moduleOutputInfo.name)-batch-module-scan.json"),
                                                                      contents)
  }

  static func itemizedJobCommand(of job: Job, useResponseFiles: ResponseFileHandling,
                                 using resolver: ArgsResolver) throws -> [String] {
    // Because the command-line passed to libSwiftScan does not go through the shell
    // we must ensure that we generate a shell-escaped string for all arguments/flags that may
    // potentially need it.
    return try resolver.resolveArgumentList(for: job,
                                            useResponseFiles: useResponseFiles).0.map { $0.spm_shellEscaped() }
  }

  static func getRootPath(of toolchain: Toolchain, env: [String: String])
  throws -> AbsolutePath {
    return try toolchain.getToolPath(.swiftCompiler)
      .parentDirectory // bin
      .parentDirectory // toolchain root
  }
}
