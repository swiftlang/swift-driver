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
import struct TSCBasic.RelativePath
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
    try addRuntimeLibraryFlags(commandLine: &commandLine)

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
    if isFrontendArgSupported(.sdkModuleCachePath) {
      try commandLine.appendLast(.sdkModuleCachePath, from: &parsedOptions)
    }

    if isFrontendArgSupported(.scannerModuleValidation) {
      commandLine.appendFlag(.scannerModuleValidation)
    }

    if isFrontendArgSupported(.scannerPrefixMap) {
      // construct `-scanner-prefix-mapper` for scanner.
      for (key, value) in prefixMapping {
        commandLine.appendFlag(.scannerPrefixMap)
        commandLine.appendFlag(key.pathString + "=" + value.pathString)
      }
    }

    if (parsedOptions.contains(.driverShowIncremental) ||
        parsedOptions.contains(.dependencyScanCacheRemarks)) &&
       isFrontendArgSupported(.dependencyScanCacheRemarks) {
      commandLine.appendFlag(.dependencyScanCacheRemarks)
    }

    if shouldAttemptIncrementalCompilation &&
       parsedOptions.contains(.incrementalDependencyScan) {
      if let serializationPath = buildRecordInfo?.dependencyScanSerializedResultPath {
        if isFrontendArgSupported(.validatePriorDependencyScanCache) {
          // Any compiler which supports "-validate-prior-dependency-scan-cache"
          // also supports "-load-dependency-scan-cache"
          // and "-serialize-dependency-scan-cache" and "-dependency-scan-cache-path"
          commandLine.appendFlag(.dependencyScanCachePath)
          commandLine.appendPath(serializationPath)
          commandLine.appendFlag(.reuseDependencyScanCache)
          commandLine.appendFlag(.validatePriorDependencyScanCache)
          commandLine.appendFlag(.serializeDependencyScanCache)
        }
      }
    }

    if isFrontendArgSupported(.autoBridgingHeaderChaining) {
      if parsedOptions.hasFlag(positive: .autoBridgingHeaderChaining,
                               negative: .noAutoBridgingHeaderChaining,
                               default: false) || isCachingEnabled {
        if producePCHJob {
          commandLine.appendFlag(.autoBridgingHeaderChaining)
        } else {
          diagnosticEngine.emit(.warning("-auto-bridging-header-chaining requires generatePCH job, no chaining will be performed"))
          commandLine.appendFlag(.noAutoBridgingHeaderChaining)
        }
      } else {
        commandLine.appendFlag(.noAutoBridgingHeaderChaining)
      }
    }

    // Provide a directory to path to scanner for where the chained bridging header will be.
    // Prefer writing next to pch output, otherwise next to module output path before fallback to temp directory for non-caching build.
    if isFrontendArgSupported(.scannerOutputDir) {
      if let outputDir = try? computePrecompiledBridgingHeaderDir(&parsedOptions,
                                                                  compilerMode: compilerMode) {
        commandLine.appendFlag(.scannerOutputDir)
        commandLine.appendPath(outputDir)
      } else {
        commandLine.appendFlag(.scannerOutputDir)
        commandLine.appendPath(VirtualPath.temporary(try RelativePath(validating: "scanner")))
      }
    }

    if isFrontendArgSupported(.resolvedPluginVerification) {
      commandLine.appendFlag(.resolvedPluginVerification)
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

    if supportInProcessSwiftScanQueries {
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      guard let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory else {
        throw DependencyScanningError.dependencyScanFailed("cannot determine working directory")
      }
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

    if supportInProcessSwiftScanQueries {
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      guard let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory else {
        throw DependencyScanningError.dependencyScanFailed("cannot determine working directory")
      }
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
    try addRuntimeLibraryFlags(commandLine: &commandLine)

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

extension Driver {
  var supportInProcessSwiftScanQueries: Bool { return self.swiftScanLibInstance != nil }
}
