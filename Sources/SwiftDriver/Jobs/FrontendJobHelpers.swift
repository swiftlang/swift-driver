import TSCBasic

/// Whether we should produce color diagnostics by default.
fileprivate func shouldColorDiagnostics() -> Bool {
  guard let stderrStream = stderrStream.stream as? LocalFileOutputByteStream else {
    return false
  }

  return TerminalController.isTTY(stderrStream)
}

extension Driver {
  /// Add frontend options that are common to different frontend invocations.
  mutating func addCommonFrontendOptions(commandLine: inout [Job.ArgTemplate]) throws {
    // Handle the CPU and its preferences.
    try commandLine.appendLast(.target_cpu, from: &parsedOptions)

    if let sdkPath = sdkPath {
      commandLine.appendFlag("-sdk")
      commandLine.append(.path(try .init(path: sdkPath)))
    }

    try commandLine.appendAll(.I, from: &parsedOptions)
    try commandLine.appendAll(.F, .Fsystem, from: &parsedOptions)

    try commandLine.appendLast(.AssertConfig, from: &parsedOptions)
    try commandLine.appendLast(.autolink_force_load, from: &parsedOptions)

    if let colorOption = parsedOptions.last(where: { $0.option == .color_diagnostics || $0.option == .no_color_diagnostics }) {
      commandLine.appendFlag(colorOption.option)
    } else if shouldColorDiagnostics() {
      commandLine.appendFlag(.color_diagnostics)
    }
    try commandLine.appendLast(.fixit_all, from: &parsedOptions)
    try commandLine.appendLast(.warn_swift3_objc_inference_minimal, .warn_swift3_objc_inference_complete, from: &parsedOptions)
    try commandLine.appendLast(.warn_implicit_overrides, from: &parsedOptions)
    try commandLine.appendLast(.typo_correction_limit, from: &parsedOptions)
    try commandLine.appendLast(.typo_correction_limit, from: &parsedOptions)
    try commandLine.appendLast(.enable_app_extension, from: &parsedOptions)
    try commandLine.appendLast(.enable_library_evolution, from: &parsedOptions)
    try commandLine.appendLast(.enable_testing, from: &parsedOptions)
    try commandLine.appendLast(.enable_private_imports, from: &parsedOptions)
    try commandLine.appendLast(.enable_cxx_interop, from: &parsedOptions)
    try commandLine.appendLast(in: .g, from: &parsedOptions)
    try commandLine.appendLast(.debug_info_format, from: &parsedOptions)
    try commandLine.appendLast(.import_underlying_module, from: &parsedOptions)
    try commandLine.appendLast(.module_cache_path, from: &parsedOptions)
    try commandLine.appendLast(.module_link_name, from: &parsedOptions)
    try commandLine.appendLast(.nostdimport, from: &parsedOptions)
    try commandLine.appendLast(.parse_stdlib, from: &parsedOptions)
    try commandLine.appendLast(.resource_dir, from: &parsedOptions)
    try commandLine.appendLast(.solver_memory_threshold, from: &parsedOptions)
    try commandLine.appendLast(.value_recursion_threshold, from: &parsedOptions)
    try commandLine.appendLast(.warn_swift3_objc_inference, from: &parsedOptions)
    try commandLine.appendLast(.Rpass_EQ, from: &parsedOptions)
    try commandLine.appendLast(.Rpass_missed_EQ, from: &parsedOptions)
    try commandLine.appendLast(.suppress_warnings, from: &parsedOptions)
    try commandLine.appendLast(.profile_generate, from: &parsedOptions)
    try commandLine.appendLast(.profile_use, from: &parsedOptions)
    try commandLine.appendLast(.profile_coverage_mapping, from: &parsedOptions)
    try commandLine.appendLast(.warnings_as_errors, from: &parsedOptions)
    try commandLine.appendLast(.sanitize_EQ, from: &parsedOptions)
    try commandLine.appendLast(.sanitize_coverage_EQ, from: &parsedOptions)
    try commandLine.appendLast(.static, from: &parsedOptions)
    try commandLine.appendLast(.swift_version, from: &parsedOptions)
    try commandLine.appendLast(.enforce_exclusivity_EQ, from: &parsedOptions)
    try commandLine.appendLast(.stats_output_dir, from: &parsedOptions)
    try commandLine.appendLast(.trace_stats_events, from: &parsedOptions)
    try commandLine.appendLast(.profile_stats_events, from: &parsedOptions)
    try commandLine.appendLast(.profile_stats_entities, from: &parsedOptions)
    try commandLine.appendLast(.solver_shrink_unsolved_threshold, from: &parsedOptions)
    try commandLine.appendLast(in: .O, from: &parsedOptions)
    try commandLine.appendLast(.RemoveRuntimeAsserts, from: &parsedOptions)
    try commandLine.appendLast(.AssumeSingleThreaded, from: &parsedOptions)
    try commandLine.appendLast(.enable_experimental_dependencies, from: &parsedOptions)
    try commandLine.appendLast(.experimental_dependency_include_intrafile, from: &parsedOptions)
    try commandLine.appendLast(.package_description_version, from: &parsedOptions)
    try commandLine.appendLast(.serialize_diagnostics_path, from: &parsedOptions)
    try commandLine.appendLast(.debug_diagnostic_names, from: &parsedOptions)
    try commandLine.appendLast(.enable_astscope_lookup, from: &parsedOptions)
    try commandLine.appendLast(.disable_astscope_lookup, from: &parsedOptions)
    try commandLine.appendLast(.disable_parser_lookup, from: &parsedOptions)
    try commandLine.appendAll(.D, from: &parsedOptions)
    try commandLine.appendAllArguments(.debug_prefix_map, from: &parsedOptions)
    try commandLine.appendAllArguments(.Xfrontend, from: &parsedOptions)
  }
}
