import TSCBasic

extension Driver {
  mutating func mergeModuleJob(inputs allInputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [VirtualPath] = []

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

    #if false
    // FIXME: Add outputs for module docs, interface, serialize diags, objc headers, TBDs, etc.
    #endif

    // FIXME: import-objc-header

    commandLine.appendFlag("-o")
    commandLine.append(.path(moduleOutput!.outputPath))

    return Job(
      kind: .mergeModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: [moduleOutput!.outputPath]
    )
  }
}
