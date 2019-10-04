import TSCBasic

extension Driver {
  mutating func mergeModuleJob(inputs allInputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [VirtualPath] = []
    var outputs: [VirtualPath] = [moduleOutput!.outputPath]

    commandLine.appendFlags("-frontend", "-merge-modules", "-emit-module")

    // FIXME: Input file list.

    // Add the inputs.
    for input in allInputs {
      assert(input.type == .swiftModule)
      commandLine.append(.path(input.file))
      inputs.append(input.file)
    }

    // Tell all files to parse as library, which is necessary to load them as
    // serialized ASTs.
    commandLine.appendFlag(.parse_as_library)

    // Merge serialized SIL from partial modules.
    commandLine.appendFlag(.sil_merge_partial_modules)

    // Disable SIL optimization passes; we've already optimized the code in each
    // partial mode.
    commandLine.appendFlag(.disable_diagnostic_passes)
    commandLine.appendFlag(.disable_sil_perf_optzns)

    try addCommonFrontendOptions(commandLine: &commandLine)
    // FIXME: Add MSVC runtime library flags

    // Add suppplementable outputs.
    func addSupplementalOutput(path: VirtualPath?, flag: String) {
      guard let path = path else { return }

      commandLine.appendFlag(flag)
      commandLine.appendPath(path)
      outputs.append(path)
    }

    addSupplementalOutput(path: moduleDocOutputPath, flag: "-emit-module-doc-path")
    addSupplementalOutput(path: swiftInterfacePath, flag: "-emit-module-interface-path")
    addSupplementalOutput(path: serializedDiagnosticsFilePath, flag: "-serialize-diagnostics-path")
    addSupplementalOutput(path: objcGeneratedHeaderPath, flag: "-emit-objc-header-path")
    addSupplementalOutput(path: tbdPath, flag: "-emit-tbd-path")

    commandLine.appendFlag(.o)
    commandLine.appendPath(moduleOutput!.outputPath)

    return Job(
      kind: .mergeModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }
}
