extension Driver {
  mutating func emitModuleJob() throws -> Job {
    let moduleOutputPath = moduleOutput!.outputPath
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: moduleOutputPath, type: .swiftModule)
    ]

    commandLine.appendFlags("-frontend", "-emit-module")

    let swiftInputFiles = inputFiles.filter { $0.type.isPartOfSwiftCompilation }

    // Add the inputs.
    for input in swiftInputFiles {
      commandLine.append(.path(input.file))
      inputs.append(input)
    }

    try addCommonFrontendOptions(commandLine: &commandLine)
    // FIXME: Add MSVC runtime library flags

    // Add suppplementable outputs.
    func addSupplementalOutput(path: VirtualPath?, flag: String, type: FileType) {
      guard let path = path else { return }

      commandLine.appendFlag(flag)
      commandLine.appendPath(path)
      outputs.append(.init(file: path, type: type))
    }

    addSupplementalOutput(path: moduleDocOutputPath, flag: "-emit-module-doc-path", type: .swiftDocumentation)
    addSupplementalOutput(path: swiftInterfacePath, flag: "-emit-module-interface-path", type: .swiftInterface)
    addSupplementalOutput(path: serializedDiagnosticsFilePath, flag: "-serialize-diagnostics-path", type: .diagnostics)
    addSupplementalOutput(path: objcGeneratedHeaderPath, flag: "-emit-objc-header-path", type: .objcHeader)
    addSupplementalOutput(path: tbdPath, flag: "-emit-tbd-path", type: .tbd)

    if let dependenciesFilePath = dependenciesFilePath {
      var path = dependenciesFilePath
      // FIXME: Hack to workaround the fact that SwiftPM/Xcode don't pass this path right now.
      if parsedOptions.getLastArgument(.emitDependenciesPath) == nil {
        path = try moduleOutputPath.replacingExtension(with: .dependencies)
      }
      addSupplementalOutput(path: path, flag: "-emit-dependencies-path", type: .dependencies)
    }

    commandLine.appendFlag(.o)
    commandLine.appendPath(moduleOutputPath)

    return Job(
      kind: .emitModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }

  /// Returns true if the emit module job should be created.
  var shouldCreateEmitModuleJob: Bool {
    return forceEmitModuleInSingleInvocation
      && compilerOutputType != .swiftModule
      && moduleOutput != nil
  }
}
