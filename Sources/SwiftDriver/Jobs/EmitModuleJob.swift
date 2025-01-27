//===--------------- EmitModuleJob.swift - Swift Module Emission Job ------===//
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

import SwiftOptions
extension Driver {
  /// Add options that are common to command lines that emit modules, e.g.,
  /// options for the paths of various module files.
  mutating func addCommonModuleOptions(
      commandLine: inout [Job.ArgTemplate],
      outputs: inout [TypedVirtualPath],
      moduleOutputPaths: SupplementalModuleTargetOutputPaths,
      isMergeModule: Bool
  ) throws {
    // Add supplemental outputs.
    func addSupplementalOutput(path: VirtualPath.Handle?, flag: String, type: FileType) {
      guard let path = path else { return }

      commandLine.appendFlag(flag)
      commandLine.appendPath(VirtualPath.lookup(path))
      outputs.append(.init(file: path, type: type))
    }

    addSupplementalOutput(path: moduleOutputPaths.moduleDocOutputPath, flag: "-emit-module-doc-path", type: .swiftDocumentation)
    addSupplementalOutput(path: moduleOutputPaths.moduleSourceInfoPath, flag: "-emit-module-source-info-path", type: .swiftSourceInfoFile)
    addSupplementalOutput(path: moduleOutputPaths.swiftInterfacePath, flag: "-emit-module-interface-path", type: .swiftInterface)
    addSupplementalOutput(path: moduleOutputPaths.swiftPrivateInterfacePath, flag: "-emit-private-module-interface-path", type: .privateSwiftInterface)
    if let pkgName = packageName, !pkgName.isEmpty {
      addSupplementalOutput(path: moduleOutputPaths.swiftPackageInterfacePath, flag: "-emit-package-module-interface-path", type: .packageSwiftInterface)
    }
    addSupplementalOutput(path: objcGeneratedHeaderPath, flag: "-emit-objc-header-path", type: .objcHeader)
    addSupplementalOutput(path: tbdPath, flag: "-emit-tbd-path", type: .tbd)
    addSupplementalOutput(path: moduleOutputPaths.apiDescriptorFilePath, flag: "-emit-api-descriptor-path", type: .jsonAPIDescriptor)

    if isMergeModule {
      return
    }

    addSupplementalOutput(path: emitModuleSerializedDiagnosticsFilePath, flag: "-serialize-diagnostics-path", type: .emitModuleDiagnostics)

    addSupplementalOutput(path: emitModuleDependenciesFilePath, flag: "-emit-dependencies-path", type: .emitModuleDependencies)

    // Skip files created by other jobs when emitting a module and building at the same time
    if emitModuleSeparately && compilerOutputType != .swiftModule {
      return
    }

    // Add outputs that can't be merged
    // Workaround for rdar://85253406
    // Ensure that the separate emit-module job does not emit `.d.` outputs.
    // If we have both individual source files and the emit-module file emit .d files, we
    // are risking collisions in output filenames.
    //
    // In cases where other compile jobs exist, they will produce dependency outputs already.
    // There are currently no cases where this is the only job because even an `-emit-module`
    // driver invocation currently still involves partial compilation jobs.
    // When partial compilation jobs are removed for the `compilerOutputType == .swiftModule`
    // case, this will need to be changed here.
    //
    if emitModuleSeparately {
      return
    }
    if let dependenciesFilePath = dependenciesFilePath {
      var path = dependenciesFilePath
      // FIXME: Hack to workaround the fact that SwiftPM/Xcode don't pass this path right now.
      if parsedOptions.getLastArgument(.emitDependenciesPath) == nil {
        path = try VirtualPath.lookup(moduleOutputInfo.output!.outputPath).replacingExtension(with: .dependencies).intern()
      }
      addSupplementalOutput(path: path, flag: "-emit-dependencies-path", type: .dependencies)
    }
  }

  /// Form a job that emits a single module
  @_spi(Testing) public mutating func emitModuleJob(pchCompileJob: Job?, isVariantJob: Bool = false) throws -> Job {
    precondition(!isVariantJob || (isVariantJob &&
      variantModuleOutputInfo != nil && variantModuleOutputPaths != nil),
      "target variant module requested without a target variant")

    let moduleOutputPath = isVariantJob ? variantModuleOutputInfo!.output!.outputPath : moduleOutputInfo.output!.outputPath
    let moduleOutputPaths = isVariantJob ? variantModuleOutputPaths! : moduleOutputPaths
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: moduleOutputPath, type: .swiftModule)
    ]

    commandLine.appendFlags("-frontend", "-emit-module", "-experimental-skip-non-inlinable-function-bodies-without-types")

    // Add the inputs.
    for input in self.inputFiles where input.type.isPartOfSwiftCompilation {
      try addPathArgument(input.file, to: &commandLine)
      inputs.append(input)
    }

    if let pchPath = bridgingPrecompiledHeader {
      inputs.append(TypedVirtualPath(file: pchPath, type: .pch))
    }
    try addBridgingHeaderPCHCacheKeyArguments(commandLine: &commandLine, pchCompileJob: pchCompileJob)

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs, kind: .emitModule)
    // FIXME: Add MSVC runtime library flags

    try addCommonModuleOptions(
      commandLine: &commandLine,
      outputs: &outputs,
      moduleOutputPaths: moduleOutputPaths,
      isMergeModule: false)

    try addCommonSymbolGraphOptions(commandLine: &commandLine)

    try commandLine.appendLast(.checkApiAvailabilityOnly, from: &parsedOptions)

    if parsedOptions.hasArgument(.parseAsLibrary, .emitLibrary) {
      commandLine.appendFlag(.parseAsLibrary)
    }

    let outputPath = VirtualPath.lookup(moduleOutputPath)
    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath)
    if let abiPath = moduleOutputPaths.abiDescriptorFilePath {
      commandLine.appendFlag(.emitAbiDescriptorPath)
      commandLine.appendPath(abiPath.file)
      outputs.append(abiPath)
    }
    let cacheContributingInputs = inputs.enumerated().reduce(into: [(TypedVirtualPath, Int)]()) { result, input in
      // only the first swift input contributes cache key to an emit module job.
      guard result.isEmpty, input.element.type == .swift else { return }
      result.append((input.element, input.offset))
    }
    let cacheKeys = try computeOutputCacheKeyForJob(commandLine: commandLine, inputs: cacheContributingInputs)
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .emitModule,
      tool: try toolchain.resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs,
      outputCacheKeys: cacheKeys
    )
  }

  static func computeEmitModuleSeparately(parsedOptions: inout ParsedOptions,
                                          compilerMode: CompilerMode,
                                          compilerOutputType: FileType?,
                                          moduleOutputInfo: ModuleOutputInfo,
                                          inputFiles: [TypedVirtualPath]) -> Bool {
    if moduleOutputInfo.output == nil ||
       !inputFiles.contains(where: { $0.type.isPartOfSwiftCompilation }) {
      return false
    }

    switch (compilerMode) {
    case .standardCompile, .batchCompile(_):
      return parsedOptions.hasFlag(positive: .emitModuleSeparately,
                                   negative: .noEmitModuleSeparately,
                                   default: true)

    case .singleCompile:
      // If cross-module-optimization is done, the module must be emitted in the same
      // swift-frontend invocation which also produces the binary.
      if canDoCrossModuleOptimization(parsedOptions: &parsedOptions) {
        return false
      }

      return parsedOptions.hasFlag(positive: .emitModuleSeparatelyWMO,
                                   negative: .noEmitModuleSeparatelyWMO,
                                   default: true) &&
             compilerOutputType != .swiftModule // The main job already generates only the module files.

    default:
      return false
    }
  }

  static func canDoCrossModuleOptimization(parsedOptions: inout ParsedOptions) -> Bool {
    if !parsedOptions.hasArgument(.enableLibraryEvolution),
       !parsedOptions.hasArgument(.disableCrossModuleOptimization),
       let opt = parsedOptions.getLast(in: .O), opt.option != .Onone {
      return true
    }
    return false
  }
}
