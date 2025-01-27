//===- APIDigesterJobs.swift - Baseline Generation and API/ABI Comparison -===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

enum DigesterMode: String {
  case api, abi

  var baselineFileType: FileType {
    switch self {
    case .api:
      return .jsonAPIBaseline
    case .abi:
      return .jsonABIBaseline
    }
  }

  var baselineGenerationJobKind: Job.Kind {
    switch self {
    case .api:
      return .generateAPIBaseline
    case .abi:
      return .generateABIBaseline
    }
  }

  var baselineComparisonJobKind: Job.Kind {
    switch self {
    case .api:
      return .compareAPIBaseline
    case .abi:
      return .compareABIBaseline
    }
  }
}

extension Driver {
  mutating func digesterBaselineGenerationJob(modulePath: VirtualPath.Handle, outputPath: VirtualPath.Handle, mode: DigesterMode) throws -> Job {
    var commandLine = [Job.ArgTemplate]()
    commandLine.appendFlag("-dump-sdk")

    try addCommonDigesterOptions(&commandLine,
      modulePath: modulePath,
      swiftModuleInterfacePath: self.moduleOutputPaths.swiftInterfacePath,
      mode: mode)

    commandLine.appendFlag(.o)
    commandLine.appendPath(VirtualPath.lookup(outputPath))

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: mode.baselineGenerationJobKind,
      tool: try toolchain.resolvedTool(.swiftAPIDigester),
      commandLine: commandLine,
      inputs: [.init(file: modulePath, type: .swiftModule)],
      primaryInputs: [],
      outputs: [.init(file: outputPath, type: mode.baselineFileType)]
    )
  }

  mutating func digesterDiagnosticsJob(modulePath: VirtualPath.Handle, baselinePath:
                                              VirtualPath.Handle, mode: DigesterMode) throws -> Job {
    func getDescriptorPath(for mode: DigesterMode) -> TypedVirtualPath? {
      switch mode {
      case .api:
        return nil
      case .abi:
        return moduleOutputPaths.abiDescriptorFilePath
      }
    }
    guard let currentABI = getDescriptorPath(for: mode) else {
      // we don't have existing descriptor to use so we have to load the module from interface/swiftmodule
      return try digesterCompareToBaselineJob(
        modulePath: modulePath,
        swiftModuleInterfacePath: self.moduleOutputPaths.swiftInterfacePath,
        baselinePath: baselinePath,
        mode: digesterMode)
    }
    var commandLine = [Job.ArgTemplate]()
    commandLine.appendFlag("-diagnose-sdk")
    commandLine.appendFlag("-input-paths")
    commandLine.appendPath(VirtualPath.lookup(baselinePath))
    commandLine.appendFlag("-input-paths")
    commandLine.appendPath(currentABI.file)
    if mode == .abi {
      commandLine.appendFlag("-abi")
    }
    if let arg = parsedOptions.getLastArgument(.digesterBreakageAllowlistPath)?.asSingle {
      let path = try VirtualPath(path: arg)
      commandLine.appendFlag("-breakage-allowlist-path")
      commandLine.appendPath(path)
    }
    commandLine.appendFlag("-serialize-diagnostics-path")
    let diag = TypedVirtualPath(file: currentABI.file.parentDirectory.appending(component: currentABI.file.basename + ".dia").intern(), type: .diagnostics)
    commandLine.appendPath(diag.file)
    let inputs: [TypedVirtualPath] = [currentABI]
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .compareABIBaseline,
      tool: try toolchain.resolvedTool(.swiftAPIDigester),
      commandLine: commandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: [diag]
    )
  }

  mutating func digesterCompareToBaselineJob(modulePath: VirtualPath.Handle,
    swiftModuleInterfacePath: VirtualPath.Handle?,
    baselinePath: VirtualPath.Handle,
    mode: DigesterMode) throws -> Job {
    var commandLine = [Job.ArgTemplate]()
    commandLine.appendFlag("-diagnose-sdk")
    commandLine.appendFlag("-disable-fail-on-error")
    commandLine.appendFlag("-baseline-path")
    commandLine.appendPath(VirtualPath.lookup(baselinePath))

    try addCommonDigesterOptions(&commandLine,
      modulePath: modulePath,
      swiftModuleInterfacePath: swiftModuleInterfacePath,
      mode: mode)

    var serializedDiagnosticsPath: VirtualPath.Handle?
    if let arg = parsedOptions.getLastArgument(.serializeBreakingChangesPath)?.asSingle {
      let path = try VirtualPath.intern(path: arg)
      commandLine.appendFlag("-serialize-diagnostics-path")
      commandLine.appendPath(VirtualPath.lookup(path))
      serializedDiagnosticsPath = path
    }
    if let arg = parsedOptions.getLastArgument(.digesterBreakageAllowlistPath)?.asSingle {
      let path = try VirtualPath(path: arg)
      commandLine.appendFlag("-breakage-allowlist-path")
      commandLine.appendPath(path)
    }

    var inputs: [TypedVirtualPath] = [.init(file: modulePath, type: .swiftModule),
                                      .init(file: baselinePath, type: mode.baselineFileType)]
    // If a module interface was emitted, treat it as an input in ABI mode.
    if let interfacePath = swiftModuleInterfacePath, mode == .abi {
      inputs.append(.init(file: interfacePath, type: .swiftInterface))
    }

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: mode.baselineComparisonJobKind,
      tool: try toolchain.resolvedTool(.swiftAPIDigester),
      commandLine: commandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: [.init(file: serializedDiagnosticsPath ?? VirtualPath.Handle.standardOutput, type: .diagnostics)]
    )
  }

  private mutating func addCommonDigesterOptions(_ commandLine: inout [Job.ArgTemplate],
                                                 modulePath: VirtualPath.Handle,
                                                 swiftModuleInterfacePath: VirtualPath.Handle?,
                                                 mode: DigesterMode) throws {
    commandLine.appendFlag("-module")
    commandLine.appendFlag(moduleOutputInfo.name)
    if mode == .abi {
      commandLine.appendFlag("-abi")
      commandLine.appendFlag("-use-interface-for-module")
      commandLine.appendFlag(moduleOutputInfo.name)
    }

    // Add a search path for the emitted module, and its module interface if there is one.
    let searchPath = VirtualPath.lookup(modulePath).parentDirectory
    commandLine.appendFlag(.I)
    commandLine.appendPath(searchPath)
    if let interfacePath = swiftModuleInterfacePath {
      let interfaceSearchPath = VirtualPath.lookup(interfacePath).parentDirectory
      if interfaceSearchPath != searchPath {
        commandLine.appendFlag(.I)
        commandLine.appendPath(interfaceSearchPath)
      }
    }

    commandLine.appendFlag(.target)
    commandLine.appendFlag(targetTriple.triple)

    if let sdkPath = frontendTargetInfo.sdkPath?.path {
      commandLine.appendFlag(.sdk)
      commandLine.append(.path(VirtualPath.lookup(sdkPath)))
    }

    commandLine.appendFlag(.resourceDir)
    commandLine.appendPath(VirtualPath.lookup(frontendTargetInfo.runtimeResourcePath.path))

    try commandLine.appendAll(.I, from: &parsedOptions)
    try commandLine.appendAll(.F, from: &parsedOptions)
    for systemFramework in parsedOptions.arguments(for: .Fsystem) {
      commandLine.appendFlag(.iframework)
      commandLine.appendFlag(systemFramework.argument.asSingle)
    }

    try commandLine.appendLast(.swiftVersion, from: &parsedOptions)
  }
}
