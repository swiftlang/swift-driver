
public enum Option {
  case INPUT(String)
  case api_diff_data_dir(String)
  case api_diff_data_file(String)
  case enable_app_extension
  case AssertConfig(String)
  case AssumeSingleThreaded
  case autolink_force_load
  case autolink_library(String)
  case bypass_batch_mode_checks
  case check_onone_completeness
  case code_complete_call_pattern_heuristics
  case code_complete_inits_in_postfix_expr
  case color_diagnostics
  case compile_module_from_interface
  case continue_building_after_errors
  case crosscheck_unqualified_lookup
  case debug_assert_after_parse
  case debug_assert_immediately
  case debug_constraints_attempt(String)
  case debug_constraints_on_line(String)
  case debug_constraints
  case debug_crash_after_parse
  case debug_crash_immediately
  case debug_cycles
  case debug_diagnostic_names
  case debug_forbid_typecheck_prefix(String)
  case debug_generic_signatures
  case debug_info_format(String)
  case debug_info_store_invocation
  case debug_prefix_map(String)
  case debug_time_compilation
  case debug_time_expression_type_checking
  case debug_time_function_bodies
  case debugger_support
  case debugger_testing_transform
  case deprecated_integrated_repl
  case diagnostics_editor_mode
  case disable_access_control
  case disable_arc_opts
  case disable_astscope_lookup
  case disable_autolink_framework(String)
  case disable_autolinking_runtime_compatibility_dynamic_replacements
  case disable_autolinking_runtime_compatibility
  case disable_availability_checking
  case disable_batch_mode
  case disable_bridging_pch
  case disable_constraint_solver_performance_hacks
  case disable_deserialization_recovery
  case disable_diagnostic_passes
  case disable_function_builder_one_way_constraints
  case disable_incremental_llvm_codegeneration
  case disable_legacy_type_info
  case disable_llvm_optzns
  case disable_llvm_slp_vectorizer
  case disable_llvm_value_names
  case disable_llvm_verify
  case disable_migrator_fixits
  case disable_modules_validate_system_headers
  case disable_named_lazy_member_loading
  case disable_nonfrozen_enum_exhaustivity_diagnostics
  case disable_nskeyedarchiver_diagnostics
  case disable_objc_attr_requires_foundation_module
  case disable_objc_interop
  case disable_parser_lookup
  case disable_playground_transform
  case disable_previous_implementation_calls_in_dynamic_replacements
  case disable_reflection_metadata
  case disable_reflection_names
  case disable_serialization_nested_type_lookup_table
  case disable_sil_ownership_verifier
  case disable_sil_partial_apply
  case disable_sil_perf_optzns
  case disable_swift_bridge_attr
  case disable_swift_specific_llvm_optzns
  case disable_swift3_objc_inference
  case disable_target_os_checking
  case disable_testable_attr_requires_testable_module
  case disable_tsan_inout_instrumentation
  case disable_typo_correction
  case disable_verify_exclusivity
  case driver_always_rebuild_dependents
  case driver_batch_count(String)
  case driver_batch_seed(String)
  case driver_batch_size_limit(String)
  case driver_emit_experimental_dependency_dot_file_after_every_import
  case driver_filelist_threshold(String)
  case driver_force_response_files
  case driver_mode(String)
  case driver_print_actions
  case driver_print_bindings
  case driver_print_derived_output_file_map
  case driver_print_jobs
  case driver_print_output_file_map
  case driver_show_incremental
  case driver_show_job_lifecycle
  case driver_skip_execution
  case driver_time_compilation
  case driver_use_filelists
  case driver_use_frontend_path(String)
  case driver_verify_experimental_dependency_graph_after_every_import
  case dump_api_path(String)
  case dump_ast
  case dump_clang_diagnostics
  case dump_interface_hash
  case dump_migration_states_dir(String)
  case dump_parse
  case dump_scope_maps(String)
  case dump_type_info
  case dump_type_refinement_contexts
  case dump_usr
  case D(String)
  case embed_bitcode_marker
  case embed_bitcode
  case emit_assembly
  case emit_bc
  case emit_dependencies_path(String)
  case emit_dependencies
  case emit_executable
  case emit_fixits_path(String)
  case emit_imported_modules
  case emit_ir
  case emit_library
  case emit_loaded_module_trace_path(String)
  case emit_loaded_module_trace
  case emit_migrated_file_path(String)
  case emit_module_doc_path(String)
  case emit_module_doc
  case emit_module_interface_path(String)
  case emit_module_interface
  case emit_module_path(String)
  case emit_module
  case emit_objc_header_path(String)
  case emit_objc_header
  case emit_object
  case emit_pch
  case emit_reference_dependencies_path(String)
  case emit_reference_dependencies
  case emit_remap_file_path(String)
  case emit_sibgen
  case emit_sib
  case emit_silgen
  case emit_sil
  case emit_sorted_sil
  case stack_promotion_checks
  case emit_syntax
  case emit_tbd_path(String)
  case emit_tbd
  case emit_verbose_sil
  case enable_access_control
  case enable_anonymous_context_mangled_names
  case enable_astscope_lookup
  case enable_batch_mode
  case enable_bridging_pch
  case enable_cxx_interop
  case enable_deserialization_recovery
  case enable_dynamic_replacement_chaining
  case enable_experimental_dependencies
  case enable_experimental_static_assert
  case enable_function_builder_one_way_constraints
  case enable_implicit_dynamic
  case enable_infer_import_as_member
  case enable_large_loadable_types
  case enable_library_evolution
  case enable_llvm_value_names
  case enable_nonfrozen_enum_exhaustivity_diagnostics
  case enable_nskeyedarchiver_diagnostics
  case enable_objc_attr_requires_foundation_module
  case enable_objc_interop
  case enable_operator_designated_types
  case enable_ownership_stripping_after_serialization
  case enable_private_imports
  case enable_resilience
  case enable_sil_opaque_values
  case enable_source_import
  case enable_swift3_objc_inference
  case enable_swiftcall
  case enable_target_os_checking
  case enable_testable_attr_requires_testable_module
  case enable_testing
  case enable_throw_without_try
  case enable_verify_exclusivity
  case enforce_exclusivity_EQ(String)
  case experimental_dependency_include_intrafile
  case external_pass_pipeline_filename(String)
  case filelist(String)
  case fixit_all
  case force_public_linkage
  case framework(String)
  case Fsystem(String)
  case F(String)
  case gdwarf_types
  case gline_tables_only
  case gnone
  case group_info_path(String)
  case debug_on_sil
  case g
  case help_hidden
  case help
  case import_cf_types
  case import_module(String)
  case import_objc_header(String)
  case import_underlying_module
  case in_place
  case incremental
  case indent_switch_case
  case indent_width(String)
  case index_file_path(String)
  case index_file
  case index_ignore_system_modules
  case index_store_path(String)
  case index_system_modules
  case interpret
  case I(String)
  case i
  case j(String)
  case lazy_astscopes
  case libc(String)
  case line_range(String)
  case link_objc_runtime
  case lldb_repl
  case L(String)
  case l(String)
  case merge_modules
  case migrate_keep_objc_visibility
  case migrator_update_sdk
  case migrator_update_swift
  case module_cache_path(String)
  case module_interface_preserve_types_as_written
  case module_link_name(String)
  case module_name(String)
  case no_clang_module_breadcrumbs
  case no_color_diagnostics
  case no_link_objc_runtime
  case no_serialize_debugging_options
  case no_static_executable
  case no_static_stdlib
  case no_stdlib_rpath
  case no_toolchain_stdlib_rpath
  case nostdimport
  case num_threads(String)
  case Onone
  case Oplayground
  case Osize
  case Ounchecked
  case output_file_map(String)
  case output_filelist(String)
  case output_request_graphviz(String)
  case O
  case o(String)
  case package_description_version(String)
  case parse_as_library
  case parse_sil
  case parse_stdlib
  case parseable_output
  case parse
  case pc_macro
  case pch_disable_validation
  case pch_output_dir(String)
  case playground_high_performance
  case playground
  case prebuilt_module_cache_path(String)
  case primary_filelist(String)
  case primary_file(String)
  case print_ast
  case print_clang_stats
  case print_inst_counts
  case print_llvm_inline_tree
  case print_stats
  case profile_coverage_mapping
  case profile_generate
  case profile_stats_entities
  case profile_stats_events
  case profile_use([String])
  case read_legacy_type_info_path_EQ(String)
  case RemoveRuntimeAsserts
  case repl
  case report_errors_to_debugger
  case require_explicit_availability_target(String)
  case require_explicit_availability
  case resolve_imports
  case resource_dir(String)
  case Rmodule_interface_rebuild
  case Rpass_missed_EQ(String)
  case Rpass_EQ(String)
  case runtime_compatibility_version(String)
  case sanitize_coverage_EQ([String])
  case sanitize_EQ([String])
  case save_optimization_record_path(String)
  case save_optimization_record
  case save_temps
  case sdk(String)
  case serialize_debugging_options
  case serialize_diagnostics_path(String)
  case serialize_diagnostics
  case serialize_module_interface_dependency_hashes
  case show_diagnostics_after_fatal
  case sil_debug_serialization
  case sil_inline_caller_benefit_reduction_factor(String)
  case sil_inline_threshold(String)
  case sil_merge_partial_modules
  case sil_unroll_threshold(String)
  case sil_verify_all
  case solver_disable_shrink
  case solver_enable_operator_designated_types
  case solver_expression_time_threshold_EQ(String)
  case solver_memory_threshold(String)
  case solver_shrink_unsolved_threshold(String)
  case stack_promotion_limit(String)
  case static_executable
  case static_stdlib
  case static
  case stats_output_dir(String)
  case stress_astscope_lookup
  case supplementary_output_file_map(String)
  case suppress_static_exclusivity_swap
  case suppress_warnings
  case swift_version(String)
  case switch_checking_invocation_threshold_EQ(String)
  case tab_width(String)
  case target_cpu(String)
  case target(String)
  case tbd_compatibility_version(String)
  case tbd_current_version(String)
  case tbd_install_name(String)
  case toolchain_stdlib_rpath
  case tools_directory(String)
  case trace_stats_events
  case track_system_dependencies
  case type_info_dump_filter_EQ(String)
  case typecheck
  case typo_correction_limit(String)
  case update_code
  case use_jit
  case use_ld(String)
  case use_malloc
  case use_tabs
  case validate_tbd_against_ir_EQ(String)
  case value_recursion_threshold(String)
  case verify_apply_fixes
  case verify_debug_info
  case verify_generic_signatures(String)
  case verify_ignore_unknown
  case verify_syntax_tree
  case verify_type_layout(String)
  case verify
  case version
  case vfsoverlay(String)
  case v
  case warn_if_astscope_lookup
  case warn_implicit_overrides
  case warn_long_expression_type_checking(String)
  case warn_long_function_bodies(String)
  case warn_swift3_objc_inference_complete
  case warn_swift3_objc_inference_minimal
  case warnings_as_errors
  case whole_module_optimization
  case working_directory(String)
  case Xcc(String)
  case Xclang_linker(String)
  case Xfrontend(String)
  case Xlinker(String)
  case Xllvm(String)
  case _DASH_DASH([String])
}
public enum Option.Group {
  case O
  case code_formatting
  case debug_crash
  case g
  case `internal`
  case internal_debug
  case linker_option
  case modes
}

extension Option.Group {
  public var name: String {
    switch self {
      case .O:
        return "<optimization level options>"
      case .code_formatting:
        return "<code formatting options>"
      case .debug_crash:
        return "<automatic crashing options>"
      case .g:
        return "<debug info options>"
      case .internal:
        return "<swift internal options>"
      case .internal_debug:
        return "<swift debug/development internal options>"
      case .linker_option:
        return "<linker-specific options>"
      case .modes:
        return "<mode options>"
    }
  }
}

extension Option.Group {
  public var helpText: String? {
    switch self {
      case .O:
        return nil
      case .code_formatting:
        return nil
      case .debug_crash:
        return nil
      case .g:
        return nil
      case .internal:
        return nil
      case .internal_debug:
        return "DEBUG/DEVELOPMENT OPTIONS"
      case .linker_option:
        return nil
      case .modes:
        return "MODES"
    }
  }
}

extension OptionParser {
  public static var driverOptions: OptionParser {
    var parser = OptionParser()
      parser.addAlias(spelling: "-###", generator: Generator.flag { Option._HASH_HASH_HASH($0) }, isHidden: false)
      parser.addOption(spelling: "-api-diff-data-dir", generator: Generator.separate { Option.api_diff_data_dir($0) }, isHidden: false, metaVar: nil, helpText: "Load platform and version specific API migration data files from <path>. Ignored if -api-diff-data-file is specified.")
      parser.addOption(spelling: "-api-diff-data-file", generator: Generator.separate { Option.api_diff_data_file($0) }, isHidden: false, metaVar: nil, helpText: "API migration data is from <path>")
      parser.addOption(spelling: "-application-extension", generator: Generator.flag { Option.enable_app_extension($0) }, isHidden: false, metaVar: nil, helpText: "Restrict code to those available for App Extensions")
      parser.addOption(spelling: "-assert-config", generator: Generator.separate { Option.AssertConfig($0) }, isHidden: false, metaVar: nil, helpText: "Specify the assert_configuration replacement. Possible values are Debug, Release, Unchecked, DisableReplacement.")
      parser.addOption(spelling: "-assume-single-threaded", generator: Generator.flag { Option.AssumeSingleThreaded($0) }, isHidden: true, metaVar: nil, helpText: "Assume that code will be executed in a single-threaded environment")
      parser.addOption(spelling: "-autolink-force-load", generator: Generator.flag { Option.autolink_force_load($0) }, isHidden: true, metaVar: nil, helpText: "Force ld to link against this module even if no symbols are used")
      parser.addOption(spelling: "-color-diagnostics", generator: Generator.flag { Option.color_diagnostics($0) }, isHidden: false, metaVar: nil, helpText: "Print diagnostics in color")
      parser.addOption(spelling: "-continue-building-after-errors", generator: Generator.flag { Option.continue_building_after_errors($0) }, isHidden: false, metaVar: nil, helpText: "Continue building, even after errors are encountered")
      parser.addAlias(spelling: "-c", generator: Generator.flag { Option.c($0) }, isHidden: false)
      parser.addOption(spelling: "-debug-diagnostic-names", generator: Generator.flag { Option.debug_diagnostic_names($0) }, isHidden: true, metaVar: nil, helpText: "Include diagnostic names when printing")
      parser.addOption(spelling: "-debug-info-format=", generator: Generator.joined { Option.debug_info_format($0) }, isHidden: false, metaVar: nil, helpText: "Specify the debug info format type to either 'dwarf' or 'codeview'")
      parser.addOption(spelling: "-debug-info-store-invocation", generator: Generator.flag { Option.debug_info_store_invocation($0) }, isHidden: false, metaVar: nil, helpText: "Emit the compiler invocation in the debug info.")
      parser.addOption(spelling: "-debug-prefix-map", generator: Generator.separate { Option.debug_prefix_map($0) }, isHidden: false, metaVar: nil, helpText: "Remap source paths in debug info")
      parser.addOption(spelling: "-deprecated-integrated-repl", generator: Generator.flag { Option.deprecated_integrated_repl($0) }, isHidden: false, metaVar: nil, helpText: nil)
      parser.addOption(spelling: "-disable-astscope-lookup", generator: Generator.flag { Option.disable_astscope_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Disable ASTScope-based unqualified name lookup")
      parser.addOption(spelling: "-disable-autolinking-runtime-compatibility-dynamic-replacements", generator: Generator.flag { Option.disable_autolinking_runtime_compatibility_dynamic_replacements($0) }, isHidden: false, metaVar: nil, helpText: "Do not use autolinking for the dynamic replacement runtime compatibility library")
      parser.addOption(spelling: "-disable-autolinking-runtime-compatibility", generator: Generator.flag { Option.disable_autolinking_runtime_compatibility($0) }, isHidden: false, metaVar: nil, helpText: "Do not use autolinking for runtime compatibility libraries")
      parser.addOption(spelling: "-disable-batch-mode", generator: Generator.flag { Option.disable_batch_mode($0) }, isHidden: true, metaVar: nil, helpText: "Disable combining frontend jobs into batches")
      parser.addOption(spelling: "-disable-bridging-pch", generator: Generator.flag { Option.disable_bridging_pch($0) }, isHidden: true, metaVar: nil, helpText: "Disable automatic generation of bridging PCH files")
      parser.addOption(spelling: "-disable-migrator-fixits", generator: Generator.flag { Option.disable_migrator_fixits($0) }, isHidden: false, metaVar: nil, helpText: "Disable the Migrator phase which automatically applies fix-its")
      parser.addOption(spelling: "-disable-parser-lookup", generator: Generator.flag { Option.disable_parser_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Disable parser lookup & use ast scope lookup only (experimental)")
      parser.addOption(spelling: "-disable-swift-bridge-attr", generator: Generator.flag { Option.disable_swift_bridge_attr($0) }, isHidden: true, metaVar: nil, helpText: "Disable using the swift bridge attribute")
      parser.addOption(spelling: "-driver-always-rebuild-dependents", generator: Generator.flag { Option.driver_always_rebuild_dependents($0) }, isHidden: true, metaVar: nil, helpText: "Always rebuild dependents of files that have been modified")
      parser.addOption(spelling: "-driver-batch-count", generator: Generator.separate { Option.driver_batch_count($0) }, isHidden: true, metaVar: nil, helpText: "Use the given number of batch-mode partitions, rather than partitioning dynamically")
      parser.addOption(spelling: "-driver-batch-seed", generator: Generator.separate { Option.driver_batch_seed($0) }, isHidden: true, metaVar: nil, helpText: "Use the given seed value to randomize batch-mode partitions")
      parser.addOption(spelling: "-driver-batch-size-limit", generator: Generator.separate { Option.driver_batch_size_limit($0) }, isHidden: true, metaVar: nil, helpText: "Use the given number as the upper limit on dynamic batch-mode partition size")
      parser.addOption(spelling: "-driver-emit-experimental-dependency-dot-file-after-every-import", generator: Generator.flag { Option.driver_emit_experimental_dependency_dot_file_after_every_import($0) }, isHidden: true, metaVar: nil, helpText: "Emit dot files every time driver imports an experimental swiftdeps file.")
      parser.addAlias(spelling: "-driver-filelist-threshold=", generator: Generator.joined { Option.driver_filelist_threshold_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-driver-filelist-threshold", generator: Generator.separate { Option.driver_filelist_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Pass input or output file names as filelists if there are more than <n>")
      parser.addOption(spelling: "-driver-force-response-files", generator: Generator.flag { Option.driver_force_response_files($0) }, isHidden: true, metaVar: nil, helpText: "Force the use of response files for testing")
      parser.addOption(spelling: "--driver-mode=", generator: Generator.joined { Option.driver_mode($0) }, isHidden: true, metaVar: nil, helpText: "Set the driver mode to either 'swift' or 'swiftc'")
      parser.addOption(spelling: "-driver-print-actions", generator: Generator.flag { Option.driver_print_actions($0) }, isHidden: true, metaVar: nil, helpText: "Dump list of actions to perform")
      parser.addOption(spelling: "-driver-print-bindings", generator: Generator.flag { Option.driver_print_bindings($0) }, isHidden: true, metaVar: nil, helpText: "Dump list of job inputs and outputs")
      parser.addOption(spelling: "-driver-print-derived-output-file-map", generator: Generator.flag { Option.driver_print_derived_output_file_map($0) }, isHidden: true, metaVar: nil, helpText: "Dump the contents of the derived output file map")
      parser.addOption(spelling: "-driver-print-jobs", generator: Generator.flag { Option.driver_print_jobs($0) }, isHidden: true, metaVar: nil, helpText: "Dump list of jobs to execute")
      parser.addOption(spelling: "-driver-print-output-file-map", generator: Generator.flag { Option.driver_print_output_file_map($0) }, isHidden: true, metaVar: nil, helpText: "Dump the contents of the output file map")
      parser.addOption(spelling: "-driver-show-incremental", generator: Generator.flag { Option.driver_show_incremental($0) }, isHidden: true, metaVar: nil, helpText: "With -v, dump information about why files are being rebuilt")
      parser.addOption(spelling: "-driver-show-job-lifecycle", generator: Generator.flag { Option.driver_show_job_lifecycle($0) }, isHidden: true, metaVar: nil, helpText: "Show every step in the lifecycle of driver jobs")
      parser.addOption(spelling: "-driver-skip-execution", generator: Generator.flag { Option.driver_skip_execution($0) }, isHidden: true, metaVar: nil, helpText: "Skip execution of subtasks when performing compilation")
      parser.addOption(spelling: "-driver-time-compilation", generator: Generator.flag { Option.driver_time_compilation($0) }, isHidden: false, metaVar: nil, helpText: "Prints the total time it took to execute all compilation tasks")
      parser.addOption(spelling: "-driver-use-filelists", generator: Generator.flag { Option.driver_use_filelists($0) }, isHidden: true, metaVar: nil, helpText: "Pass input files as filelists whenever possible")
      parser.addOption(spelling: "-driver-use-frontend-path", generator: Generator.separate { Option.driver_use_frontend_path($0) }, isHidden: true, metaVar: nil, helpText: "Use the given executable to perform compilations. Arguments can be passed as a ';' separated list")
      parser.addOption(spelling: "-driver-verify-experimental-dependency-graph-after-every-import", generator: Generator.flag { Option.driver_verify_experimental_dependency_graph_after_every_import($0) }, isHidden: true, metaVar: nil, helpText: "Debug DriverGraph by verifying it after every import")
      parser.addOption(spelling: "-dump-ast", generator: Generator.flag { Option.dump_ast($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s) and dump AST(s)")
      parser.addOption(spelling: "-dump-migration-states-dir", generator: Generator.separate { Option.dump_migration_states_dir($0) }, isHidden: false, metaVar: nil, helpText: "Dump the input text, output text, and states for migration to <path>")
      parser.addOption(spelling: "-dump-parse", generator: Generator.flag { Option.dump_parse($0) }, isHidden: false, metaVar: nil, helpText: "Parse input file(s) and dump AST(s)")
      parser.addOption(spelling: "-dump-scope-maps", generator: Generator.separate { Option.dump_scope_maps($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s) and dump the scope map(s)")
      parser.addOption(spelling: "-dump-type-info", generator: Generator.flag { Option.dump_type_info($0) }, isHidden: false, metaVar: nil, helpText: "Output YAML dump of fixed-size types from all imported modules")
      parser.addOption(spelling: "-dump-type-refinement-contexts", generator: Generator.flag { Option.dump_type_refinement_contexts($0) }, isHidden: false, metaVar: nil, helpText: "Type-check input file(s) and dump type refinement contexts(s)")
      parser.addOption(spelling: "-dump-usr", generator: Generator.flag { Option.dump_usr($0) }, isHidden: false, metaVar: nil, helpText: "Dump USR for each declaration reference")
      parser.addOption(spelling: "-D", generator: Generator.joinedOrSeparate { Option.D($0) }, isHidden: false, metaVar: nil, helpText: "Marks a conditional compilation flag as true")
      parser.addOption(spelling: "-embed-bitcode-marker", generator: Generator.flag { Option.embed_bitcode_marker($0) }, isHidden: false, metaVar: nil, helpText: "Embed placeholder LLVM IR data as a marker")
      parser.addOption(spelling: "-embed-bitcode", generator: Generator.flag { Option.embed_bitcode($0) }, isHidden: false, metaVar: nil, helpText: "Embed LLVM IR bitcode as data")
      parser.addOption(spelling: "-emit-assembly", generator: Generator.flag { Option.emit_assembly($0) }, isHidden: false, metaVar: nil, helpText: "Emit assembly file(s) (-S)")
      parser.addOption(spelling: "-emit-bc", generator: Generator.flag { Option.emit_bc($0) }, isHidden: false, metaVar: nil, helpText: "Emit LLVM BC file(s)")
      parser.addOption(spelling: "-emit-dependencies", generator: Generator.flag { Option.emit_dependencies($0) }, isHidden: false, metaVar: nil, helpText: "Emit basic Make-compatible dependencies files")
      parser.addOption(spelling: "-emit-executable", generator: Generator.flag { Option.emit_executable($0) }, isHidden: false, metaVar: nil, helpText: "Emit a linked executable")
      parser.addOption(spelling: "-emit-imported-modules", generator: Generator.flag { Option.emit_imported_modules($0) }, isHidden: false, metaVar: nil, helpText: "Emit a list of the imported modules")
      parser.addOption(spelling: "-emit-ir", generator: Generator.flag { Option.emit_ir($0) }, isHidden: false, metaVar: nil, helpText: "Emit LLVM IR file(s)")
      parser.addOption(spelling: "-emit-library", generator: Generator.flag { Option.emit_library($0) }, isHidden: false, metaVar: nil, helpText: "Emit a linked library")
      parser.addAlias(spelling: "-emit-loaded-module-trace-path=", generator: Generator.joined { Option.emit_loaded_module_trace_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-emit-loaded-module-trace-path", generator: Generator.separate { Option.emit_loaded_module_trace_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit the loaded module trace JSON to <path>")
      parser.addOption(spelling: "-emit-loaded-module-trace", generator: Generator.flag { Option.emit_loaded_module_trace($0) }, isHidden: false, metaVar: nil, helpText: "Emit a JSON file containing information about what modules were loaded")
      parser.addOption(spelling: "-emit-module-interface-path", generator: Generator.separate { Option.emit_module_interface_path($0) }, isHidden: false, metaVar: nil, helpText: "Output module interface file to <path>")
      parser.addOption(spelling: "-emit-module-interface", generator: Generator.flag { Option.emit_module_interface($0) }, isHidden: false, metaVar: nil, helpText: "Output module interface file")
      parser.addAlias(spelling: "-emit-module-path=", generator: Generator.joined { Option.emit_module_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-emit-module-path", generator: Generator.separate { Option.emit_module_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit an importable module to <path>")
      parser.addOption(spelling: "-emit-module", generator: Generator.flag { Option.emit_module($0) }, isHidden: false, metaVar: nil, helpText: "Emit an importable module")
      parser.addOption(spelling: "-emit-objc-header-path", generator: Generator.separate { Option.emit_objc_header_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit an Objective-C header file to <path>")
      parser.addOption(spelling: "-emit-objc-header", generator: Generator.flag { Option.emit_objc_header($0) }, isHidden: false, metaVar: nil, helpText: "Emit an Objective-C header file")
      parser.addOption(spelling: "-emit-object", generator: Generator.flag { Option.emit_object($0) }, isHidden: false, metaVar: nil, helpText: "Emit object file(s) (-c)")
      parser.addAlias(spelling: "-emit-parseable-module-interface-path", generator: Generator.separate { Option.emit_parseable_module_interface_path($0) }, isHidden: true)
      parser.addAlias(spelling: "-emit-parseable-module-interface", generator: Generator.flag { Option.emit_parseable_module_interface($0) }, isHidden: true)
      parser.addOption(spelling: "-emit-sibgen", generator: Generator.flag { Option.emit_sibgen($0) }, isHidden: false, metaVar: nil, helpText: "Emit serialized AST + raw SIL file(s)")
      parser.addOption(spelling: "-emit-sib", generator: Generator.flag { Option.emit_sib($0) }, isHidden: false, metaVar: nil, helpText: "Emit serialized AST + canonical SIL file(s)")
      parser.addOption(spelling: "-emit-silgen", generator: Generator.flag { Option.emit_silgen($0) }, isHidden: false, metaVar: nil, helpText: "Emit raw SIL file(s)")
      parser.addOption(spelling: "-emit-sil", generator: Generator.flag { Option.emit_sil($0) }, isHidden: false, metaVar: nil, helpText: "Emit canonical SIL file(s)")
      parser.addAlias(spelling: "-emit-tbd-path=", generator: Generator.joined { Option.emit_tbd_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-emit-tbd-path", generator: Generator.separate { Option.emit_tbd_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit the TBD file to <path>")
      parser.addOption(spelling: "-emit-tbd", generator: Generator.flag { Option.emit_tbd($0) }, isHidden: false, metaVar: nil, helpText: "Emit a TBD file")
      parser.addOption(spelling: "-enable-astscope-lookup", generator: Generator.flag { Option.enable_astscope_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Enable ASTScope-based unqualified name lookup")
      parser.addOption(spelling: "-enable-batch-mode", generator: Generator.flag { Option.enable_batch_mode($0) }, isHidden: true, metaVar: nil, helpText: "Enable combining frontend jobs into batches")
      parser.addOption(spelling: "-enable-bridging-pch", generator: Generator.flag { Option.enable_bridging_pch($0) }, isHidden: true, metaVar: nil, helpText: "Enable automatic generation of bridging PCH files")
      parser.addOption(spelling: "-enable-experimental-dependencies", generator: Generator.flag { Option.enable_experimental_dependencies($0) }, isHidden: true, metaVar: nil, helpText: "Experimental work-in-progress to be more selective about incremental recompilation")
      parser.addOption(spelling: "-enable-library-evolution", generator: Generator.flag { Option.enable_library_evolution($0) }, isHidden: false, metaVar: nil, helpText: "Build the module to allow binary-compatible library evolution")
      parser.addOption(spelling: "-enable-private-imports", generator: Generator.flag { Option.enable_private_imports($0) }, isHidden: true, metaVar: nil, helpText: "Allows this module's internal and private API to be accessed")
      parser.addOption(spelling: "-enable-testing", generator: Generator.flag { Option.enable_testing($0) }, isHidden: true, metaVar: nil, helpText: "Allows this module's internal API to be accessed for testing")
      parser.addOption(spelling: "-enforce-exclusivity=", generator: Generator.joined { Option.enforce_exclusivity_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Enforce law of exclusivity")
      parser.addOption(spelling: "-experimental-dependency-include-intrafile", generator: Generator.flag { Option.experimental_dependency_include_intrafile($0) }, isHidden: true, metaVar: nil, helpText: "Include within-file dependencies.")
      parser.addAlias(spelling: "-F=", generator: Generator.joined { Option.F_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-fixit-all", generator: Generator.flag { Option.fixit_all($0) }, isHidden: false, metaVar: nil, helpText: "Apply all fixits from diagnostics without any filtering")
      parser.addAlias(spelling: "-force-single-frontend-invocation", generator: Generator.flag { Option.force_single_frontend_invocation($0) }, isHidden: true)
      parser.addOption(spelling: "-framework", generator: Generator.separate { Option.framework($0) }, isHidden: false, metaVar: nil, helpText: "Specifies a framework which should be linked against")
      parser.addOption(spelling: "-Fsystem", generator: Generator.separate { Option.Fsystem($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to system framework search path")
      parser.addOption(spelling: "-F", generator: Generator.joinedOrSeparate { Option.F($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to framework search path")
      parser.addOption(spelling: "-gdwarf-types", generator: Generator.flag { Option.gdwarf_types($0) }, isHidden: false, metaVar: nil, helpText: "Emit full DWARF type info.")
      parser.addOption(spelling: "-gline-tables-only", generator: Generator.flag { Option.gline_tables_only($0) }, isHidden: false, metaVar: nil, helpText: "Emit minimal debug info for backtraces only")
      parser.addOption(spelling: "-gnone", generator: Generator.flag { Option.gnone($0) }, isHidden: false, metaVar: nil, helpText: "Don't emit debug info")
      parser.addOption(spelling: "-g", generator: Generator.flag { Option.g($0) }, isHidden: false, metaVar: nil, helpText: "Emit debug info. This is the preferred setting for debugging with LLDB.")
      parser.addOption(spelling: "-help-hidden", generator: Generator.flag { Option.help_hidden($0) }, isHidden: true, metaVar: nil, helpText: "Display available options, including hidden options")
      parser.addAlias(spelling: "--help-hidden", generator: Generator.flag { Option.help_hidden($0) }, isHidden: true)
      parser.addOption(spelling: "-help", generator: Generator.flag { Option.help($0) }, isHidden: false, metaVar: nil, helpText: "Display available options")
      parser.addAlias(spelling: "--help", generator: Generator.flag { Option.help($0) }, isHidden: false)
      parser.addAlias(spelling: "-h", generator: Generator.flag { Option.h($0) }, isHidden: false)
      parser.addAlias(spelling: "-I=", generator: Generator.joined { Option.I_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-import-cf-types", generator: Generator.flag { Option.import_cf_types($0) }, isHidden: true, metaVar: nil, helpText: "Recognize and import CF types as class types")
      parser.addOption(spelling: "-import-objc-header", generator: Generator.separate { Option.import_objc_header($0) }, isHidden: true, metaVar: nil, helpText: "Implicitly imports an Objective-C header file")
      parser.addOption(spelling: "-import-underlying-module", generator: Generator.flag { Option.import_underlying_module($0) }, isHidden: false, metaVar: nil, helpText: "Implicitly imports the Objective-C half of a module")
      parser.addOption(spelling: "-in-place", generator: Generator.flag { Option.in_place($0) }, isHidden: false, metaVar: nil, helpText: "Overwrite input file with formatted file.")
      parser.addOption(spelling: "-incremental", generator: Generator.flag { Option.incremental($0) }, isHidden: true, metaVar: nil, helpText: "Perform an incremental build if possible")
      parser.addOption(spelling: "-indent-switch-case", generator: Generator.flag { Option.indent_switch_case($0) }, isHidden: false, metaVar: nil, helpText: "Indent cases in switch statements.")
      parser.addOption(spelling: "-indent-width", generator: Generator.separate { Option.indent_width($0) }, isHidden: false, metaVar: nil, helpText: "Number of characters to indent.")
      parser.addOption(spelling: "-index-file-path", generator: Generator.separate { Option.index_file_path($0) }, isHidden: false, metaVar: nil, helpText: "Produce index data for file <path>")
      parser.addOption(spelling: "-index-file", generator: Generator.flag { Option.index_file($0) }, isHidden: false, metaVar: nil, helpText: "Produce index data for a source file")
      parser.addOption(spelling: "-index-ignore-system-modules", generator: Generator.flag { Option.index_ignore_system_modules($0) }, isHidden: false, metaVar: nil, helpText: "Avoid indexing system modules")
      parser.addOption(spelling: "-index-store-path", generator: Generator.separate { Option.index_store_path($0) }, isHidden: false, metaVar: nil, helpText: "Store indexing data to <path>")
      parser.addOption(spelling: "-I", generator: Generator.joinedOrSeparate { Option.I($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to the import search path")
      parser.addOption(spelling: "-i", generator: Generator.flag { Option.i($0) }, isHidden: false, metaVar: nil, helpText: nil)
      parser.addOption(spelling: "-j", generator: Generator.joinedOrSeparate { Option.j($0) }, isHidden: false, metaVar: nil, helpText: "Number of commands to execute in parallel")
      parser.addAlias(spelling: "-L=", generator: Generator.joined { Option.L_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-libc", generator: Generator.separate { Option.libc($0) }, isHidden: false, metaVar: nil, helpText: "libc runtime library to use")
      parser.addOption(spelling: "-line-range", generator: Generator.separate { Option.line_range($0) }, isHidden: false, metaVar: nil, helpText: "<start line>:<end line>. Formats a range of lines (1-based). Can only be used with one input file.")
      parser.addOption(spelling: "-link-objc-runtime", generator: Generator.flag { Option.link_objc_runtime($0) }, isHidden: false, metaVar: nil, helpText: nil)
      parser.addOption(spelling: "-lldb-repl", generator: Generator.flag { Option.lldb_repl($0) }, isHidden: true, metaVar: nil, helpText: "LLDB-enhanced REPL mode")
      parser.addOption(spelling: "-L", generator: Generator.joinedOrSeparate { Option.L($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to library link search path")
      parser.addOption(spelling: "-l", generator: Generator.joined { Option.l($0) }, isHidden: false, metaVar: nil, helpText: "Specifies a library which should be linked against")
      parser.addOption(spelling: "-migrate-keep-objc-visibility", generator: Generator.flag { Option.migrate_keep_objc_visibility($0) }, isHidden: false, metaVar: nil, helpText: "When migrating, add '@objc' to declarations that would've been implicitly visible in Swift 3")
      parser.addOption(spelling: "-migrator-update-sdk", generator: Generator.flag { Option.migrator_update_sdk($0) }, isHidden: false, metaVar: nil, helpText: "Does nothing. Temporary compatibility flag for Xcode.")
      parser.addOption(spelling: "-migrator-update-swift", generator: Generator.flag { Option.migrator_update_swift($0) }, isHidden: false, metaVar: nil, helpText: "Does nothing. Temporary compatibility flag for Xcode.")
      parser.addOption(spelling: "-module-cache-path", generator: Generator.separate { Option.module_cache_path($0) }, isHidden: false, metaVar: nil, helpText: "Specifies the Clang module cache path")
      parser.addAlias(spelling: "-module-link-name=", generator: Generator.joined { Option.module_link_name_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-module-link-name", generator: Generator.separate { Option.module_link_name($0) }, isHidden: false, metaVar: nil, helpText: "Library to link against when using this module")
      parser.addAlias(spelling: "-module-name=", generator: Generator.joined { Option.module_name_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-module-name", generator: Generator.separate { Option.module_name($0) }, isHidden: false, metaVar: nil, helpText: "Name of the module to build")
      parser.addOption(spelling: "-no-color-diagnostics", generator: Generator.flag { Option.no_color_diagnostics($0) }, isHidden: false, metaVar: nil, helpText: "Do not print diagnostics in color")
      parser.addOption(spelling: "-no-link-objc-runtime", generator: Generator.flag { Option.no_link_objc_runtime($0) }, isHidden: true, metaVar: nil, helpText: "Don't link in additions to the Objective-C runtime")
      parser.addOption(spelling: "-no-static-executable", generator: Generator.flag { Option.no_static_executable($0) }, isHidden: true, metaVar: nil, helpText: "Don't statically link the executable")
      parser.addOption(spelling: "-no-static-stdlib", generator: Generator.flag { Option.no_static_stdlib($0) }, isHidden: true, metaVar: nil, helpText: "Don't statically link the Swift standard library")
      parser.addOption(spelling: "-no-stdlib-rpath", generator: Generator.flag { Option.no_stdlib_rpath($0) }, isHidden: true, metaVar: nil, helpText: "Don't add any rpath entries.")
      parser.addOption(spelling: "-no-toolchain-stdlib-rpath", generator: Generator.flag { Option.no_toolchain_stdlib_rpath($0) }, isHidden: true, metaVar: nil, helpText: "Do not add an rpath entry for the toolchain's standard library (default)")
      parser.addOption(spelling: "-nostdimport", generator: Generator.flag { Option.nostdimport($0) }, isHidden: false, metaVar: nil, helpText: "Don't search the standard library import path for modules")
      parser.addOption(spelling: "-num-threads", generator: Generator.separate { Option.num_threads($0) }, isHidden: false, metaVar: nil, helpText: "Enable multi-threading and specify number of threads")
      parser.addOption(spelling: "-Onone", generator: Generator.flag { Option.Onone($0) }, isHidden: false, metaVar: nil, helpText: "Compile without any optimization")
      parser.addOption(spelling: "-Oplayground", generator: Generator.flag { Option.Oplayground($0) }, isHidden: true, metaVar: nil, helpText: "Compile with optimizations appropriate for a playground")
      parser.addOption(spelling: "-Osize", generator: Generator.flag { Option.Osize($0) }, isHidden: false, metaVar: nil, helpText: "Compile with optimizations and target small code size")
      parser.addOption(spelling: "-Ounchecked", generator: Generator.flag { Option.Ounchecked($0) }, isHidden: false, metaVar: nil, helpText: "Compile with optimizations and remove runtime safety checks")
      parser.addAlias(spelling: "-output-file-map=", generator: Generator.joined { Option.output_file_map_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-output-file-map", generator: Generator.separate { Option.output_file_map($0) }, isHidden: false, metaVar: nil, helpText: "A file which specifies the location of outputs")
      parser.addOption(spelling: "-O", generator: Generator.flag { Option.O($0) }, isHidden: false, metaVar: nil, helpText: "Compile with optimizations")
      parser.addOption(spelling: "-o", generator: Generator.joinedOrSeparate { Option.o($0) }, isHidden: false, metaVar: nil, helpText: "Write output to <file>")
      parser.addOption(spelling: "-package-description-version", generator: Generator.separate { Option.package_description_version($0) }, isHidden: true, metaVar: nil, helpText: "The version number to be applied on the input for the PackageDescription availability kind")
      parser.addOption(spelling: "-parse-as-library", generator: Generator.flag { Option.parse_as_library($0) }, isHidden: false, metaVar: nil, helpText: "Parse the input file(s) as libraries, not scripts")
      parser.addOption(spelling: "-parse-sil", generator: Generator.flag { Option.parse_sil($0) }, isHidden: false, metaVar: nil, helpText: "Parse the input file as SIL code, not Swift source")
      parser.addOption(spelling: "-parse-stdlib", generator: Generator.flag { Option.parse_stdlib($0) }, isHidden: true, metaVar: nil, helpText: "Parse the input file(s) as the Swift standard library")
      parser.addOption(spelling: "-parseable-output", generator: Generator.flag { Option.parseable_output($0) }, isHidden: false, metaVar: nil, helpText: "Emit textual output in a parseable format")
      parser.addOption(spelling: "-parse", generator: Generator.flag { Option.parse($0) }, isHidden: false, metaVar: nil, helpText: "Parse input file(s)")
      parser.addOption(spelling: "-pch-output-dir", generator: Generator.separate { Option.pch_output_dir($0) }, isHidden: true, metaVar: nil, helpText: "Directory to persist automatically created precompiled bridging headers")
      parser.addOption(spelling: "-print-ast", generator: Generator.flag { Option.print_ast($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s) and pretty print AST(s)")
      parser.addOption(spelling: "-profile-coverage-mapping", generator: Generator.flag { Option.profile_coverage_mapping($0) }, isHidden: false, metaVar: nil, helpText: "Generate coverage data for use with profiled execution counts")
      parser.addOption(spelling: "-profile-generate", generator: Generator.flag { Option.profile_generate($0) }, isHidden: false, metaVar: nil, helpText: "Generate instrumented code to collect execution counts")
      parser.addOption(spelling: "-profile-stats-entities", generator: Generator.flag { Option.profile_stats_entities($0) }, isHidden: true, metaVar: nil, helpText: "Profile changes to stats in -stats-output-dir, subdivided by source entity")
      parser.addOption(spelling: "-profile-stats-events", generator: Generator.flag { Option.profile_stats_events($0) }, isHidden: true, metaVar: nil, helpText: "Profile changes to stats in -stats-output-dir")
      parser.addOption(spelling: "-profile-use=", generator: Generator.commaJoined { Option.profile_use($0) }, isHidden: false, metaVar: nil, helpText: "Supply a profdata file to enable profile-guided optimization")
      parser.addOption(spelling: "-remove-runtime-asserts", generator: Generator.flag { Option.RemoveRuntimeAsserts($0) }, isHidden: false, metaVar: nil, helpText: "Remove runtime safety checks.")
      parser.addOption(spelling: "-repl", generator: Generator.flag { Option.repl($0) }, isHidden: true, metaVar: nil, helpText: "REPL mode (the default if there is no input file)")
      parser.addOption(spelling: "-require-explicit-availability-target", generator: Generator.separate { Option.require_explicit_availability_target($0) }, isHidden: false, metaVar: nil, helpText: "Suggest fix-its adding @available(<target>, *) to public declarations without availability")
      parser.addOption(spelling: "-require-explicit-availability", generator: Generator.flag { Option.require_explicit_availability($0) }, isHidden: false, metaVar: nil, helpText: "Require explicit availability on public declarations")
      parser.addOption(spelling: "-resolve-imports", generator: Generator.flag { Option.resolve_imports($0) }, isHidden: false, metaVar: nil, helpText: "Parse and resolve imports in input file(s)")
      parser.addOption(spelling: "-resource-dir", generator: Generator.separate { Option.resource_dir($0) }, isHidden: true, metaVar: nil, helpText: "The directory that holds the compiler resource files")
      parser.addOption(spelling: "-Rpass-missed=", generator: Generator.joined { Option.Rpass_missed_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Report missed transformations by optimization passes whose name matches the given POSIX regular expression")
      parser.addOption(spelling: "-Rpass=", generator: Generator.joined { Option.Rpass_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Report performed transformations by optimization passes whose name matches the given POSIX regular expression")
      parser.addOption(spelling: "-runtime-compatibility-version", generator: Generator.separate { Option.runtime_compatibility_version($0) }, isHidden: false, metaVar: nil, helpText: "Link compatibility library for Swift runtime version, or 'none'")
      parser.addOption(spelling: "-sanitize-coverage=", generator: Generator.commaJoined { Option.sanitize_coverage_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Specify the type of coverage instrumentation for Sanitizers and additional options separated by commas")
      parser.addOption(spelling: "-sanitize=", generator: Generator.commaJoined { Option.sanitize_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Turn on runtime checks for erroneous behavior.")
      parser.addOption(spelling: "-save-optimization-record-path", generator: Generator.separate { Option.save_optimization_record_path($0) }, isHidden: false, metaVar: nil, helpText: "Specify the file name of any generated YAML optimization record")
      parser.addOption(spelling: "-save-optimization-record", generator: Generator.flag { Option.save_optimization_record($0) }, isHidden: false, metaVar: nil, helpText: "Generate a YAML optimization record file")
      parser.addOption(spelling: "-save-temps", generator: Generator.flag { Option.save_temps($0) }, isHidden: false, metaVar: nil, helpText: "Save intermediate compilation results")
      parser.addOption(spelling: "-sdk", generator: Generator.separate { Option.sdk($0) }, isHidden: false, metaVar: nil, helpText: "Compile against <sdk>")
      parser.addAlias(spelling: "-serialize-diagnostics-path=", generator: Generator.joined { Option.serialize_diagnostics_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-serialize-diagnostics-path", generator: Generator.separate { Option.serialize_diagnostics_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit a serialized diagnostics file to <path>")
      parser.addOption(spelling: "-serialize-diagnostics", generator: Generator.flag { Option.serialize_diagnostics($0) }, isHidden: false, metaVar: nil, helpText: "Serialize diagnostics in a binary format")
      parser.addOption(spelling: "-solver-memory-threshold", generator: Generator.separate { Option.solver_memory_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Set the upper bound for memory consumption, in bytes, by the constraint solver")
      parser.addOption(spelling: "-solver-shrink-unsolved-threshold", generator: Generator.separate { Option.solver_shrink_unsolved_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Set The upper bound to number of sub-expressions unsolved before termination of the shrink phrase")
      parser.addOption(spelling: "-static-executable", generator: Generator.flag { Option.static_executable($0) }, isHidden: false, metaVar: nil, helpText: "Statically link the executable")
      parser.addOption(spelling: "-static-stdlib", generator: Generator.flag { Option.static_stdlib($0) }, isHidden: false, metaVar: nil, helpText: "Statically link the Swift standard library")
      parser.addOption(spelling: "-static", generator: Generator.flag { Option.static($0) }, isHidden: false, metaVar: nil, helpText: "Make this module statically linkable and make the output of -emit-library a static library.")
      parser.addOption(spelling: "-stats-output-dir", generator: Generator.separate { Option.stats_output_dir($0) }, isHidden: true, metaVar: nil, helpText: "Directory to write unified compilation-statistics files to")
      parser.addOption(spelling: "-suppress-warnings", generator: Generator.flag { Option.suppress_warnings($0) }, isHidden: false, metaVar: nil, helpText: "Suppress all warnings")
      parser.addOption(spelling: "-swift-version", generator: Generator.separate { Option.swift_version($0) }, isHidden: false, metaVar: nil, helpText: "Interpret input according to a specific Swift language version number")
      parser.addAlias(spelling: "-S", generator: Generator.flag { Option.S($0) }, isHidden: false)
      parser.addOption(spelling: "-tab-width", generator: Generator.separate { Option.tab_width($0) }, isHidden: false, metaVar: nil, helpText: "Width of tab character.")
      parser.addOption(spelling: "-target-cpu", generator: Generator.separate { Option.target_cpu($0) }, isHidden: false, metaVar: nil, helpText: "Generate code for a particular CPU variant")
      parser.addAlias(spelling: "--target=", generator: Generator.joined { Option.target_legacy_spelling($0) }, isHidden: false)
      parser.addOption(spelling: "-target", generator: Generator.separate { Option.target($0) }, isHidden: false, metaVar: nil, helpText: "Generate code for the given target <triple>, such as x86_64-apple-macos10.9")
      parser.addOption(spelling: "-toolchain-stdlib-rpath", generator: Generator.flag { Option.toolchain_stdlib_rpath($0) }, isHidden: true, metaVar: nil, helpText: "Add an rpath entry for the toolchain's standard library, rather than the OS's")
      parser.addOption(spelling: "-tools-directory", generator: Generator.separate { Option.tools_directory($0) }, isHidden: false, metaVar: nil, helpText: "Look for external executables (ld, clang, binutils) in <directory>")
      parser.addOption(spelling: "-trace-stats-events", generator: Generator.flag { Option.trace_stats_events($0) }, isHidden: true, metaVar: nil, helpText: "Trace changes to stats in -stats-output-dir")
      parser.addOption(spelling: "-track-system-dependencies", generator: Generator.flag { Option.track_system_dependencies($0) }, isHidden: false, metaVar: nil, helpText: "Track system dependencies while emitting Make-style dependencies")
      parser.addOption(spelling: "-typecheck", generator: Generator.flag { Option.typecheck($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s)")
      parser.addOption(spelling: "-typo-correction-limit", generator: Generator.separate { Option.typo_correction_limit($0) }, isHidden: true, metaVar: nil, helpText: "Limit the number of times the compiler will attempt typo correction to <n>")
      parser.addOption(spelling: "-update-code", generator: Generator.flag { Option.update_code($0) }, isHidden: true, metaVar: nil, helpText: "Update Swift code")
      parser.addOption(spelling: "-use-ld=", generator: Generator.joined { Option.use_ld($0) }, isHidden: false, metaVar: nil, helpText: "Specifies the linker to be used")
      parser.addOption(spelling: "-use-tabs", generator: Generator.flag { Option.use_tabs($0) }, isHidden: false, metaVar: nil, helpText: "Use tabs for indentation.")
      parser.addOption(spelling: "-value-recursion-threshold", generator: Generator.separate { Option.value_recursion_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Set the maximum depth for direct recursion in value types")
      parser.addOption(spelling: "-verify-debug-info", generator: Generator.flag { Option.verify_debug_info($0) }, isHidden: false, metaVar: nil, helpText: "Verify the binary representation of debug output.")
      parser.addOption(spelling: "-version", generator: Generator.flag { Option.version($0) }, isHidden: false, metaVar: nil, helpText: "Print version information and exit")
      parser.addAlias(spelling: "--version", generator: Generator.flag { Option.version($0) }, isHidden: false)
      parser.addAlias(spelling: "-vfsoverlay=", generator: Generator.joined { Option.vfsoverlay_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-vfsoverlay", generator: Generator.joinedOrSeparate { Option.vfsoverlay($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to VFS overlay file")
      parser.addOption(spelling: "-v", generator: Generator.flag { Option.v($0) }, isHidden: false, metaVar: nil, helpText: "Show commands to run and use verbose output")
      parser.addOption(spelling: "-warn-implicit-overrides", generator: Generator.flag { Option.warn_implicit_overrides($0) }, isHidden: false, metaVar: nil, helpText: "Warn about implicit overrides of protocol members")
      parser.addOption(spelling: "-warn-swift3-objc-inference-complete", generator: Generator.flag { Option.warn_swift3_objc_inference_complete($0) }, isHidden: false, metaVar: nil, helpText: "Warn about deprecated @objc inference in Swift 3 for every declaration that will no longer be inferred as @objc in Swift 4")
      parser.addOption(spelling: "-warn-swift3-objc-inference-minimal", generator: Generator.flag { Option.warn_swift3_objc_inference_minimal($0) }, isHidden: false, metaVar: nil, helpText: "Warn about deprecated @objc inference in Swift 3 based on direct uses of the Objective-C entrypoint")
      parser.addAlias(spelling: "-warn-swift3-objc-inference", generator: Generator.flag { Option.warn_swift3_objc_inference($0) }, isHidden: true)
      parser.addOption(spelling: "-warnings-as-errors", generator: Generator.flag { Option.warnings_as_errors($0) }, isHidden: false, metaVar: nil, helpText: "Treat warnings as errors")
      parser.addOption(spelling: "-whole-module-optimization", generator: Generator.flag { Option.whole_module_optimization($0) }, isHidden: false, metaVar: nil, helpText: "Optimize input files together instead of individually")
      parser.addAlias(spelling: "-wmo", generator: Generator.flag { Option.wmo($0) }, isHidden: true)
      parser.addAlias(spelling: "-working-directory=", generator: Generator.joined { Option.working_directory_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-working-directory", generator: Generator.separate { Option.working_directory($0) }, isHidden: false, metaVar: nil, helpText: "Resolve file paths relative to the specified directory")
      parser.addOption(spelling: "-Xcc", generator: Generator.separate { Option.Xcc($0) }, isHidden: false, metaVar: nil, helpText: "Pass <arg> to the C/C++/Objective-C compiler")
      parser.addOption(spelling: "-Xclang-linker", generator: Generator.separate { Option.Xclang_linker($0) }, isHidden: true, metaVar: nil, helpText: "Pass <arg> to Clang when it is use for linking.")
      parser.addOption(spelling: "-Xfrontend", generator: Generator.separate { Option.Xfrontend($0) }, isHidden: true, metaVar: nil, helpText: "Pass <arg> to the Swift frontend")
      parser.addOption(spelling: "-Xlinker", generator: Generator.separate { Option.Xlinker($0) }, isHidden: false, metaVar: nil, helpText: "Specifies an option which should be passed to the linker")
      parser.addOption(spelling: "-Xllvm", generator: Generator.separate { Option.Xllvm($0) }, isHidden: true, metaVar: nil, helpText: "Pass <arg> to LLVM.")
      parser.addOption(spelling: "--", generator: Generator.remaining { Option._DASH_DASH($0) }, isHidden: false, metaVar: nil, helpText: nil)
    return parser
  }
}

extension OptionParser {
  public static var frontendOptions: OptionParser {
    var parser = OptionParser()
      parser.addOption(spelling: "-api-diff-data-dir", generator: Generator.separate { Option.api_diff_data_dir($0) }, isHidden: false, metaVar: nil, helpText: "Load platform and version specific API migration data files from <path>. Ignored if -api-diff-data-file is specified.")
      parser.addOption(spelling: "-api-diff-data-file", generator: Generator.separate { Option.api_diff_data_file($0) }, isHidden: false, metaVar: nil, helpText: "API migration data is from <path>")
      parser.addOption(spelling: "-application-extension", generator: Generator.flag { Option.enable_app_extension($0) }, isHidden: false, metaVar: nil, helpText: "Restrict code to those available for App Extensions")
      parser.addOption(spelling: "-assert-config", generator: Generator.separate { Option.AssertConfig($0) }, isHidden: false, metaVar: nil, helpText: "Specify the assert_configuration replacement. Possible values are Debug, Release, Unchecked, DisableReplacement.")
      parser.addOption(spelling: "-assume-single-threaded", generator: Generator.flag { Option.AssumeSingleThreaded($0) }, isHidden: true, metaVar: nil, helpText: "Assume that code will be executed in a single-threaded environment")
      parser.addOption(spelling: "-autolink-force-load", generator: Generator.flag { Option.autolink_force_load($0) }, isHidden: true, metaVar: nil, helpText: "Force ld to link against this module even if no symbols are used")
      parser.addOption(spelling: "-autolink-library", generator: Generator.separate { Option.autolink_library($0) }, isHidden: false, metaVar: nil, helpText: "Add dependent library")
      parser.addAlias(spelling: "-build-module-from-parseable-interface", generator: Generator.flag { Option.build_module_from_parseable_interface($0) }, isHidden: true)
      parser.addOption(spelling: "-bypass-batch-mode-checks", generator: Generator.flag { Option.bypass_batch_mode_checks($0) }, isHidden: true, metaVar: nil, helpText: "Bypass checks for batch-mode errors.")
      parser.addOption(spelling: "-check-onone-completeness", generator: Generator.flag { Option.check_onone_completeness($0) }, isHidden: true, metaVar: nil, helpText: "Print errors if the compile OnoneSupport module is missing symbols")
      parser.addOption(spelling: "-code-complete-call-pattern-heuristics", generator: Generator.flag { Option.code_complete_call_pattern_heuristics($0) }, isHidden: true, metaVar: nil, helpText: "Use heuristics to guess whether we want call pattern completions")
      parser.addOption(spelling: "-code-complete-inits-in-postfix-expr", generator: Generator.flag { Option.code_complete_inits_in_postfix_expr($0) }, isHidden: true, metaVar: nil, helpText: "Include initializers when completing a postfix expression")
      parser.addOption(spelling: "-color-diagnostics", generator: Generator.flag { Option.color_diagnostics($0) }, isHidden: false, metaVar: nil, helpText: "Print diagnostics in color")
      parser.addOption(spelling: "-compile-module-from-interface", generator: Generator.flag { Option.compile_module_from_interface($0) }, isHidden: true, metaVar: nil, helpText: "Treat the (single) input as a swiftinterface and produce a module")
      parser.addOption(spelling: "-continue-building-after-errors", generator: Generator.flag { Option.continue_building_after_errors($0) }, isHidden: false, metaVar: nil, helpText: "Continue building, even after errors are encountered")
      parser.addOption(spelling: "-crosscheck-unqualified-lookup", generator: Generator.flag { Option.crosscheck_unqualified_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Compare legacy DeclContext- to ASTScope-based unqualified name lookup (for debugging)")
      parser.addAlias(spelling: "-c", generator: Generator.flag { Option.c($0) }, isHidden: false)
      parser.addOption(spelling: "-debug-assert-after-parse", generator: Generator.flag { Option.debug_assert_after_parse($0) }, isHidden: true, metaVar: nil, helpText: "Force an assertion failure after parsing")
      parser.addOption(spelling: "-debug-assert-immediately", generator: Generator.flag { Option.debug_assert_immediately($0) }, isHidden: true, metaVar: nil, helpText: "Force an assertion failure immediately")
      parser.addOption(spelling: "-debug-constraints-attempt", generator: Generator.separate { Option.debug_constraints_attempt($0) }, isHidden: true, metaVar: nil, helpText: "Debug the constraint solver at a given attempt")
      parser.addAlias(spelling: "-debug-constraints-on-line=", generator: Generator.joined { Option.debug_constraints_on_line_EQ($0) }, isHidden: true)
      parser.addOption(spelling: "-debug-constraints-on-line", generator: Generator.separate { Option.debug_constraints_on_line($0) }, isHidden: true, metaVar: nil, helpText: "Debug the constraint solver for expressions on <line>")
      parser.addOption(spelling: "-debug-constraints", generator: Generator.flag { Option.debug_constraints($0) }, isHidden: true, metaVar: nil, helpText: "Debug the constraint-based type checker")
      parser.addOption(spelling: "-debug-crash-after-parse", generator: Generator.flag { Option.debug_crash_after_parse($0) }, isHidden: true, metaVar: nil, helpText: "Force a crash after parsing")
      parser.addOption(spelling: "-debug-crash-immediately", generator: Generator.flag { Option.debug_crash_immediately($0) }, isHidden: true, metaVar: nil, helpText: "Force a crash immediately")
      parser.addOption(spelling: "-debug-cycles", generator: Generator.flag { Option.debug_cycles($0) }, isHidden: true, metaVar: nil, helpText: "Print out debug dumps when cycles are detected in evaluation")
      parser.addOption(spelling: "-debug-diagnostic-names", generator: Generator.flag { Option.debug_diagnostic_names($0) }, isHidden: true, metaVar: nil, helpText: "Include diagnostic names when printing")
      parser.addOption(spelling: "-debug-forbid-typecheck-prefix", generator: Generator.separate { Option.debug_forbid_typecheck_prefix($0) }, isHidden: true, metaVar: nil, helpText: "Triggers llvm fatal_error if typechecker tries to typecheck a decl with the provided prefix name")
      parser.addOption(spelling: "-debug-generic-signatures", generator: Generator.flag { Option.debug_generic_signatures($0) }, isHidden: true, metaVar: nil, helpText: "Debug generic signatures")
      parser.addOption(spelling: "-debug-info-format=", generator: Generator.joined { Option.debug_info_format($0) }, isHidden: false, metaVar: nil, helpText: "Specify the debug info format type to either 'dwarf' or 'codeview'")
      parser.addOption(spelling: "-debug-info-store-invocation", generator: Generator.flag { Option.debug_info_store_invocation($0) }, isHidden: false, metaVar: nil, helpText: "Emit the compiler invocation in the debug info.")
      parser.addOption(spelling: "-debug-prefix-map", generator: Generator.separate { Option.debug_prefix_map($0) }, isHidden: false, metaVar: nil, helpText: "Remap source paths in debug info")
      parser.addOption(spelling: "-debug-time-compilation", generator: Generator.flag { Option.debug_time_compilation($0) }, isHidden: true, metaVar: nil, helpText: "Prints the time taken by each compilation phase")
      parser.addOption(spelling: "-debug-time-expression-type-checking", generator: Generator.flag { Option.debug_time_expression_type_checking($0) }, isHidden: true, metaVar: nil, helpText: "Dumps the time it takes to type-check each expression")
      parser.addOption(spelling: "-debug-time-function-bodies", generator: Generator.flag { Option.debug_time_function_bodies($0) }, isHidden: true, metaVar: nil, helpText: "Dumps the time it takes to type-check each function body")
      parser.addOption(spelling: "-debugger-support", generator: Generator.flag { Option.debugger_support($0) }, isHidden: true, metaVar: nil, helpText: "Process swift code as if running in the debugger")
      parser.addOption(spelling: "-debugger-testing-transform", generator: Generator.flag { Option.debugger_testing_transform($0) }, isHidden: true, metaVar: nil, helpText: "Instrument the code with calls to an intrinsic that record the expected values of local variables so they can be compared against the results from the debugger.")
      parser.addOption(spelling: "-deprecated-integrated-repl", generator: Generator.flag { Option.deprecated_integrated_repl($0) }, isHidden: false, metaVar: nil, helpText: nil)
      parser.addOption(spelling: "-diagnostics-editor-mode", generator: Generator.flag { Option.diagnostics_editor_mode($0) }, isHidden: true, metaVar: nil, helpText: "Diagnostics will be used in editor")
      parser.addOption(spelling: "-disable-access-control", generator: Generator.flag { Option.disable_access_control($0) }, isHidden: true, metaVar: nil, helpText: "Don't respect access control restrictions")
      parser.addOption(spelling: "-disable-arc-opts", generator: Generator.flag { Option.disable_arc_opts($0) }, isHidden: true, metaVar: nil, helpText: "Don't run SIL ARC optimization passes.")
      parser.addOption(spelling: "-disable-astscope-lookup", generator: Generator.flag { Option.disable_astscope_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Disable ASTScope-based unqualified name lookup")
      parser.addOption(spelling: "-disable-autolink-framework", generator: Generator.separate { Option.disable_autolink_framework($0) }, isHidden: true, metaVar: nil, helpText: "Disable autolinking against the provided framework")
      parser.addOption(spelling: "-disable-autolinking-runtime-compatibility-dynamic-replacements", generator: Generator.flag { Option.disable_autolinking_runtime_compatibility_dynamic_replacements($0) }, isHidden: false, metaVar: nil, helpText: "Do not use autolinking for the dynamic replacement runtime compatibility library")
      parser.addOption(spelling: "-disable-autolinking-runtime-compatibility", generator: Generator.flag { Option.disable_autolinking_runtime_compatibility($0) }, isHidden: false, metaVar: nil, helpText: "Do not use autolinking for runtime compatibility libraries")
      parser.addOption(spelling: "-disable-availability-checking", generator: Generator.flag { Option.disable_availability_checking($0) }, isHidden: true, metaVar: nil, helpText: "Disable checking for potentially unavailable APIs")
      parser.addOption(spelling: "-disable-batch-mode", generator: Generator.flag { Option.disable_batch_mode($0) }, isHidden: true, metaVar: nil, helpText: "Disable combining frontend jobs into batches")
      parser.addOption(spelling: "-disable-constraint-solver-performance-hacks", generator: Generator.flag { Option.disable_constraint_solver_performance_hacks($0) }, isHidden: true, metaVar: nil, helpText: "Disable all the hacks in the constraint solver")
      parser.addOption(spelling: "-disable-deserialization-recovery", generator: Generator.flag { Option.disable_deserialization_recovery($0) }, isHidden: true, metaVar: nil, helpText: "Don't attempt to recover from missing xrefs (etc) in swiftmodules")
      parser.addOption(spelling: "-disable-diagnostic-passes", generator: Generator.flag { Option.disable_diagnostic_passes($0) }, isHidden: true, metaVar: nil, helpText: "Don't run diagnostic passes")
      parser.addOption(spelling: "-disable-function-builder-one-way-constraints", generator: Generator.flag { Option.disable_function_builder_one_way_constraints($0) }, isHidden: true, metaVar: nil, helpText: "Disable one-way constraints in the function builder transformation")
      parser.addOption(spelling: "-disable-incremental-llvm-codegen", generator: Generator.flag { Option.disable_incremental_llvm_codegeneration($0) }, isHidden: true, metaVar: nil, helpText: "Disable incremental llvm code generation.")
      parser.addOption(spelling: "-disable-legacy-type-info", generator: Generator.flag { Option.disable_legacy_type_info($0) }, isHidden: true, metaVar: nil, helpText: "Completely disable legacy type layout")
      parser.addOption(spelling: "-disable-llvm-optzns", generator: Generator.flag { Option.disable_llvm_optzns($0) }, isHidden: true, metaVar: nil, helpText: "Don't run LLVM optimization passes")
      parser.addOption(spelling: "-disable-llvm-slp-vectorizer", generator: Generator.flag { Option.disable_llvm_slp_vectorizer($0) }, isHidden: true, metaVar: nil, helpText: "Don't run LLVM SLP vectorizer")
      parser.addOption(spelling: "-disable-llvm-value-names", generator: Generator.flag { Option.disable_llvm_value_names($0) }, isHidden: true, metaVar: nil, helpText: "Don't add names to local values in LLVM IR")
      parser.addOption(spelling: "-disable-llvm-verify", generator: Generator.flag { Option.disable_llvm_verify($0) }, isHidden: true, metaVar: nil, helpText: "Don't run the LLVM IR verifier.")
      parser.addOption(spelling: "-disable-migrator-fixits", generator: Generator.flag { Option.disable_migrator_fixits($0) }, isHidden: false, metaVar: nil, helpText: "Disable the Migrator phase which automatically applies fix-its")
      parser.addOption(spelling: "-disable-modules-validate-system-headers", generator: Generator.flag { Option.disable_modules_validate_system_headers($0) }, isHidden: true, metaVar: nil, helpText: "Disable validating system headers in the Clang importer")
      parser.addOption(spelling: "-disable-named-lazy-member-loading", generator: Generator.flag { Option.disable_named_lazy_member_loading($0) }, isHidden: true, metaVar: nil, helpText: "Disable per-name lazy member loading")
      parser.addOption(spelling: "-disable-nonfrozen-enum-exhaustivity-diagnostics", generator: Generator.flag { Option.disable_nonfrozen_enum_exhaustivity_diagnostics($0) }, isHidden: true, metaVar: nil, helpText: "Allow switches over non-frozen enums without catch-all cases")
      parser.addOption(spelling: "-disable-nskeyedarchiver-diagnostics", generator: Generator.flag { Option.disable_nskeyedarchiver_diagnostics($0) }, isHidden: true, metaVar: nil, helpText: "Allow classes with unstable mangled names to adopt NSCoding")
      parser.addOption(spelling: "-disable-objc-attr-requires-foundation-module", generator: Generator.flag { Option.disable_objc_attr_requires_foundation_module($0) }, isHidden: true, metaVar: nil, helpText: "Disable requiring uses of @objc to require importing the Foundation module")
      parser.addOption(spelling: "-disable-objc-interop", generator: Generator.flag { Option.disable_objc_interop($0) }, isHidden: true, metaVar: nil, helpText: "Disable Objective-C interop code generation and config directives")
      parser.addOption(spelling: "-disable-parser-lookup", generator: Generator.flag { Option.disable_parser_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Disable parser lookup & use ast scope lookup only (experimental)")
      parser.addOption(spelling: "-disable-playground-transform", generator: Generator.flag { Option.disable_playground_transform($0) }, isHidden: true, metaVar: nil, helpText: "Disable playground transformation")
      parser.addOption(spelling: "-disable-previous-implementation-calls-in-dynamic-replacements", generator: Generator.flag { Option.disable_previous_implementation_calls_in_dynamic_replacements($0) }, isHidden: true, metaVar: nil, helpText: "Disable calling the previous implementation in dynamic replacements")
      parser.addOption(spelling: "-disable-reflection-metadata", generator: Generator.flag { Option.disable_reflection_metadata($0) }, isHidden: true, metaVar: nil, helpText: "Disable emission of reflection metadata for nominal types")
      parser.addOption(spelling: "-disable-reflection-names", generator: Generator.flag { Option.disable_reflection_names($0) }, isHidden: true, metaVar: nil, helpText: "Disable emission of names of stored properties and enum cases inreflection metadata")
      parser.addOption(spelling: "-disable-serialization-nested-type-lookup-table", generator: Generator.flag { Option.disable_serialization_nested_type_lookup_table($0) }, isHidden: false, metaVar: nil, helpText: "Force module merging to use regular lookups to find nested types")
      parser.addOption(spelling: "-disable-sil-ownership-verifier", generator: Generator.flag { Option.disable_sil_ownership_verifier($0) }, isHidden: true, metaVar: nil, helpText: "Do not verify ownership invariants during SIL Verification ")
      parser.addOption(spelling: "-disable-sil-partial-apply", generator: Generator.flag { Option.disable_sil_partial_apply($0) }, isHidden: true, metaVar: nil, helpText: "Disable use of partial_apply in SIL generation")
      parser.addOption(spelling: "-disable-sil-perf-optzns", generator: Generator.flag { Option.disable_sil_perf_optzns($0) }, isHidden: true, metaVar: nil, helpText: "Don't run SIL performance optimization passes")
      parser.addOption(spelling: "-disable-swift-bridge-attr", generator: Generator.flag { Option.disable_swift_bridge_attr($0) }, isHidden: true, metaVar: nil, helpText: "Disable using the swift bridge attribute")
      parser.addOption(spelling: "-disable-swift-specific-llvm-optzns", generator: Generator.flag { Option.disable_swift_specific_llvm_optzns($0) }, isHidden: true, metaVar: nil, helpText: "Don't run Swift specific LLVM optimization passes.")
      parser.addOption(spelling: "-disable-swift3-objc-inference", generator: Generator.flag { Option.disable_swift3_objc_inference($0) }, isHidden: true, metaVar: nil, helpText: "Disable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 4 behavior)")
      parser.addOption(spelling: "-disable-target-os-checking", generator: Generator.flag { Option.disable_target_os_checking($0) }, isHidden: false, metaVar: nil, helpText: "Disable checking the target OS of serialized modules")
      parser.addOption(spelling: "-disable-testable-attr-requires-testable-module", generator: Generator.flag { Option.disable_testable_attr_requires_testable_module($0) }, isHidden: false, metaVar: nil, helpText: "Disable checking of @testable")
      parser.addOption(spelling: "-disable-tsan-inout-instrumentation", generator: Generator.flag { Option.disable_tsan_inout_instrumentation($0) }, isHidden: true, metaVar: nil, helpText: "Disable treatment of inout parameters as Thread Sanitizer accesses")
      parser.addOption(spelling: "-disable-typo-correction", generator: Generator.flag { Option.disable_typo_correction($0) }, isHidden: false, metaVar: nil, helpText: "Disable typo correction")
      parser.addOption(spelling: "-disable-verify-exclusivity", generator: Generator.flag { Option.disable_verify_exclusivity($0) }, isHidden: true, metaVar: nil, helpText: "Diable verification of access markers used to enforce exclusivity.")
      parser.addOption(spelling: "-dump-api-path", generator: Generator.separate { Option.dump_api_path($0) }, isHidden: true, metaVar: nil, helpText: "The path to output swift interface files for the compiled source files")
      parser.addOption(spelling: "-dump-ast", generator: Generator.flag { Option.dump_ast($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s) and dump AST(s)")
      parser.addOption(spelling: "-dump-clang-diagnostics", generator: Generator.flag { Option.dump_clang_diagnostics($0) }, isHidden: true, metaVar: nil, helpText: "Dump Clang diagnostics to stderr")
      parser.addOption(spelling: "-dump-interface-hash", generator: Generator.flag { Option.dump_interface_hash($0) }, isHidden: true, metaVar: nil, helpText: "Parse input file(s) and dump interface token hash(es)")
      parser.addOption(spelling: "-dump-migration-states-dir", generator: Generator.separate { Option.dump_migration_states_dir($0) }, isHidden: false, metaVar: nil, helpText: "Dump the input text, output text, and states for migration to <path>")
      parser.addOption(spelling: "-dump-parse", generator: Generator.flag { Option.dump_parse($0) }, isHidden: false, metaVar: nil, helpText: "Parse input file(s) and dump AST(s)")
      parser.addOption(spelling: "-dump-scope-maps", generator: Generator.separate { Option.dump_scope_maps($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s) and dump the scope map(s)")
      parser.addOption(spelling: "-dump-type-info", generator: Generator.flag { Option.dump_type_info($0) }, isHidden: false, metaVar: nil, helpText: "Output YAML dump of fixed-size types from all imported modules")
      parser.addOption(spelling: "-dump-type-refinement-contexts", generator: Generator.flag { Option.dump_type_refinement_contexts($0) }, isHidden: false, metaVar: nil, helpText: "Type-check input file(s) and dump type refinement contexts(s)")
      parser.addOption(spelling: "-dump-usr", generator: Generator.flag { Option.dump_usr($0) }, isHidden: false, metaVar: nil, helpText: "Dump USR for each declaration reference")
      parser.addOption(spelling: "-D", generator: Generator.joinedOrSeparate { Option.D($0) }, isHidden: false, metaVar: nil, helpText: "Marks a conditional compilation flag as true")
      parser.addOption(spelling: "-embed-bitcode-marker", generator: Generator.flag { Option.embed_bitcode_marker($0) }, isHidden: false, metaVar: nil, helpText: "Embed placeholder LLVM IR data as a marker")
      parser.addOption(spelling: "-embed-bitcode", generator: Generator.flag { Option.embed_bitcode($0) }, isHidden: false, metaVar: nil, helpText: "Embed LLVM IR bitcode as data")
      parser.addOption(spelling: "-emit-assembly", generator: Generator.flag { Option.emit_assembly($0) }, isHidden: false, metaVar: nil, helpText: "Emit assembly file(s) (-S)")
      parser.addOption(spelling: "-emit-bc", generator: Generator.flag { Option.emit_bc($0) }, isHidden: false, metaVar: nil, helpText: "Emit LLVM BC file(s)")
      parser.addOption(spelling: "-emit-dependencies-path", generator: Generator.separate { Option.emit_dependencies_path($0) }, isHidden: false, metaVar: nil, helpText: "Output basic Make-compatible dependencies file to <path>")
      parser.addOption(spelling: "-emit-dependencies", generator: Generator.flag { Option.emit_dependencies($0) }, isHidden: false, metaVar: nil, helpText: "Emit basic Make-compatible dependencies files")
      parser.addOption(spelling: "-emit-fixits-path", generator: Generator.separate { Option.emit_fixits_path($0) }, isHidden: false, metaVar: nil, helpText: "Output compiler fixits as source edits to <path>")
      parser.addOption(spelling: "-emit-imported-modules", generator: Generator.flag { Option.emit_imported_modules($0) }, isHidden: false, metaVar: nil, helpText: "Emit a list of the imported modules")
      parser.addOption(spelling: "-emit-ir", generator: Generator.flag { Option.emit_ir($0) }, isHidden: false, metaVar: nil, helpText: "Emit LLVM IR file(s)")
      parser.addAlias(spelling: "-emit-loaded-module-trace-path=", generator: Generator.joined { Option.emit_loaded_module_trace_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-emit-loaded-module-trace-path", generator: Generator.separate { Option.emit_loaded_module_trace_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit the loaded module trace JSON to <path>")
      parser.addOption(spelling: "-emit-loaded-module-trace", generator: Generator.flag { Option.emit_loaded_module_trace($0) }, isHidden: false, metaVar: nil, helpText: "Emit a JSON file containing information about what modules were loaded")
      parser.addOption(spelling: "-emit-migrated-file-path", generator: Generator.separate { Option.emit_migrated_file_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit the migrated source file to <path>")
      parser.addOption(spelling: "-emit-module-doc-path", generator: Generator.separate { Option.emit_module_doc_path($0) }, isHidden: false, metaVar: nil, helpText: "Output module documentation file <path>")
      parser.addOption(spelling: "-emit-module-doc", generator: Generator.flag { Option.emit_module_doc($0) }, isHidden: false, metaVar: nil, helpText: "Emit a module documentation file based on documentation comments")
      parser.addOption(spelling: "-emit-module-interface-path", generator: Generator.separate { Option.emit_module_interface_path($0) }, isHidden: false, metaVar: nil, helpText: "Output module interface file to <path>")
      parser.addAlias(spelling: "-emit-module-path=", generator: Generator.joined { Option.emit_module_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-emit-module-path", generator: Generator.separate { Option.emit_module_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit an importable module to <path>")
      parser.addOption(spelling: "-emit-module", generator: Generator.flag { Option.emit_module($0) }, isHidden: false, metaVar: nil, helpText: "Emit an importable module")
      parser.addOption(spelling: "-emit-objc-header-path", generator: Generator.separate { Option.emit_objc_header_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit an Objective-C header file to <path>")
      parser.addOption(spelling: "-emit-objc-header", generator: Generator.flag { Option.emit_objc_header($0) }, isHidden: false, metaVar: nil, helpText: "Emit an Objective-C header file")
      parser.addOption(spelling: "-emit-object", generator: Generator.flag { Option.emit_object($0) }, isHidden: false, metaVar: nil, helpText: "Emit object file(s) (-c)")
      parser.addAlias(spelling: "-emit-parseable-module-interface-path", generator: Generator.separate { Option.emit_parseable_module_interface_path($0) }, isHidden: true)
      parser.addOption(spelling: "-emit-pch", generator: Generator.flag { Option.emit_pch($0) }, isHidden: true, metaVar: nil, helpText: "Emit PCH for imported Objective-C header file")
      parser.addOption(spelling: "-emit-reference-dependencies-path", generator: Generator.separate { Option.emit_reference_dependencies_path($0) }, isHidden: false, metaVar: nil, helpText: "Output Swift-style dependencies file to <path>")
      parser.addOption(spelling: "-emit-reference-dependencies", generator: Generator.flag { Option.emit_reference_dependencies($0) }, isHidden: false, metaVar: nil, helpText: "Emit a Swift-style dependencies file")
      parser.addOption(spelling: "-emit-remap-file-path", generator: Generator.separate { Option.emit_remap_file_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit the replacement map describing Swift Migrator changes to <path>")
      parser.addOption(spelling: "-emit-sibgen", generator: Generator.flag { Option.emit_sibgen($0) }, isHidden: false, metaVar: nil, helpText: "Emit serialized AST + raw SIL file(s)")
      parser.addOption(spelling: "-emit-sib", generator: Generator.flag { Option.emit_sib($0) }, isHidden: false, metaVar: nil, helpText: "Emit serialized AST + canonical SIL file(s)")
      parser.addOption(spelling: "-emit-silgen", generator: Generator.flag { Option.emit_silgen($0) }, isHidden: false, metaVar: nil, helpText: "Emit raw SIL file(s)")
      parser.addOption(spelling: "-emit-sil", generator: Generator.flag { Option.emit_sil($0) }, isHidden: false, metaVar: nil, helpText: "Emit canonical SIL file(s)")
      parser.addOption(spelling: "-emit-sorted-sil", generator: Generator.flag { Option.emit_sorted_sil($0) }, isHidden: true, metaVar: nil, helpText: "When printing SIL, print out all sil entities sorted by name to ease diffing")
      parser.addOption(spelling: "-emit-stack-promotion-checks", generator: Generator.flag { Option.stack_promotion_checks($0) }, isHidden: true, metaVar: nil, helpText: "Emit runtime checks for correct stack promotion of objects.")
      parser.addOption(spelling: "-emit-syntax", generator: Generator.flag { Option.emit_syntax($0) }, isHidden: true, metaVar: nil, helpText: "Parse input file(s) and emit the Syntax tree(s) as JSON")
      parser.addAlias(spelling: "-emit-tbd-path=", generator: Generator.joined { Option.emit_tbd_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-emit-tbd-path", generator: Generator.separate { Option.emit_tbd_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit the TBD file to <path>")
      parser.addOption(spelling: "-emit-tbd", generator: Generator.flag { Option.emit_tbd($0) }, isHidden: false, metaVar: nil, helpText: "Emit a TBD file")
      parser.addOption(spelling: "-emit-verbose-sil", generator: Generator.flag { Option.emit_verbose_sil($0) }, isHidden: true, metaVar: nil, helpText: "Emit locations during SIL emission")
      parser.addOption(spelling: "-enable-access-control", generator: Generator.flag { Option.enable_access_control($0) }, isHidden: true, metaVar: nil, helpText: "Respect access control restrictions")
      parser.addOption(spelling: "-enable-anonymous-context-mangled-names", generator: Generator.flag { Option.enable_anonymous_context_mangled_names($0) }, isHidden: true, metaVar: nil, helpText: "Enable emission of mangled names in anonymous context descriptors")
      parser.addOption(spelling: "-enable-astscope-lookup", generator: Generator.flag { Option.enable_astscope_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Enable ASTScope-based unqualified name lookup")
      parser.addOption(spelling: "-enable-batch-mode", generator: Generator.flag { Option.enable_batch_mode($0) }, isHidden: true, metaVar: nil, helpText: "Enable combining frontend jobs into batches")
      parser.addOption(spelling: "-enable-cxx-interop", generator: Generator.flag { Option.enable_cxx_interop($0) }, isHidden: true, metaVar: nil, helpText: "Enable C++ interop code generation and config directives")
      parser.addOption(spelling: "-enable-deserialization-recovery", generator: Generator.flag { Option.enable_deserialization_recovery($0) }, isHidden: true, metaVar: nil, helpText: "Attempt to recover from missing xrefs (etc) in swiftmodules")
      parser.addOption(spelling: "-enable-dynamic-replacement-chaining", generator: Generator.flag { Option.enable_dynamic_replacement_chaining($0) }, isHidden: true, metaVar: nil, helpText: "Enable chaining of dynamic replacements")
      parser.addOption(spelling: "-enable-experimental-dependencies", generator: Generator.flag { Option.enable_experimental_dependencies($0) }, isHidden: true, metaVar: nil, helpText: "Experimental work-in-progress to be more selective about incremental recompilation")
      parser.addOption(spelling: "-enable-experimental-static-assert", generator: Generator.flag { Option.enable_experimental_static_assert($0) }, isHidden: true, metaVar: nil, helpText: "Enable experimental #assert")
      parser.addOption(spelling: "-enable-function-builder-one-way-constraints", generator: Generator.flag { Option.enable_function_builder_one_way_constraints($0) }, isHidden: true, metaVar: nil, helpText: "Enable one-way constraints in the function builder transformation")
      parser.addOption(spelling: "-enable-implicit-dynamic", generator: Generator.flag { Option.enable_implicit_dynamic($0) }, isHidden: true, metaVar: nil, helpText: "Add 'dynamic' to all declarations")
      parser.addOption(spelling: "-enable-infer-import-as-member", generator: Generator.flag { Option.enable_infer_import_as_member($0) }, isHidden: true, metaVar: nil, helpText: "Infer when a global could be imported as a member")
      parser.addOption(spelling: "-enable-large-loadable-types", generator: Generator.flag { Option.enable_large_loadable_types($0) }, isHidden: true, metaVar: nil, helpText: "Enable Large Loadable types IRGen pass")
      parser.addOption(spelling: "-enable-library-evolution", generator: Generator.flag { Option.enable_library_evolution($0) }, isHidden: false, metaVar: nil, helpText: "Build the module to allow binary-compatible library evolution")
      parser.addOption(spelling: "-enable-llvm-value-names", generator: Generator.flag { Option.enable_llvm_value_names($0) }, isHidden: true, metaVar: nil, helpText: "Add names to local values in LLVM IR")
      parser.addOption(spelling: "-enable-nonfrozen-enum-exhaustivity-diagnostics", generator: Generator.flag { Option.enable_nonfrozen_enum_exhaustivity_diagnostics($0) }, isHidden: true, metaVar: nil, helpText: "Diagnose switches over non-frozen enums without catch-all cases")
      parser.addOption(spelling: "-enable-nskeyedarchiver-diagnostics", generator: Generator.flag { Option.enable_nskeyedarchiver_diagnostics($0) }, isHidden: true, metaVar: nil, helpText: "Diagnose classes with unstable mangled names adopting NSCoding")
      parser.addOption(spelling: "-enable-objc-attr-requires-foundation-module", generator: Generator.flag { Option.enable_objc_attr_requires_foundation_module($0) }, isHidden: true, metaVar: nil, helpText: "Enable requiring uses of @objc to require importing the Foundation module")
      parser.addOption(spelling: "-enable-objc-interop", generator: Generator.flag { Option.enable_objc_interop($0) }, isHidden: true, metaVar: nil, helpText: "Enable Objective-C interop code generation and config directives")
      parser.addOption(spelling: "-enable-operator-designated-types", generator: Generator.flag { Option.enable_operator_designated_types($0) }, isHidden: true, metaVar: nil, helpText: "Enable operator designated types")
      parser.addOption(spelling: "-enable-ownership-stripping-after-serialization", generator: Generator.flag { Option.enable_ownership_stripping_after_serialization($0) }, isHidden: true, metaVar: nil, helpText: "Strip ownership after serialization")
      parser.addOption(spelling: "-enable-private-imports", generator: Generator.flag { Option.enable_private_imports($0) }, isHidden: true, metaVar: nil, helpText: "Allows this module's internal and private API to be accessed")
      parser.addOption(spelling: "-enable-resilience", generator: Generator.flag { Option.enable_resilience($0) }, isHidden: true, metaVar: nil, helpText: "Deprecated, use -enable-library-evolution instead")
      parser.addOption(spelling: "-enable-sil-opaque-values", generator: Generator.flag { Option.enable_sil_opaque_values($0) }, isHidden: true, metaVar: nil, helpText: "Enable SIL Opaque Values")
      parser.addOption(spelling: "-enable-source-import", generator: Generator.flag { Option.enable_source_import($0) }, isHidden: true, metaVar: nil, helpText: "Enable importing of Swift source files")
      parser.addOption(spelling: "-enable-swift3-objc-inference", generator: Generator.flag { Option.enable_swift3_objc_inference($0) }, isHidden: true, metaVar: nil, helpText: "Enable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 3 behavior)")
      parser.addOption(spelling: "-enable-swiftcall", generator: Generator.flag { Option.enable_swiftcall($0) }, isHidden: false, metaVar: nil, helpText: "Enable the use of LLVM swiftcall support")
      parser.addOption(spelling: "-enable-target-os-checking", generator: Generator.flag { Option.enable_target_os_checking($0) }, isHidden: false, metaVar: nil, helpText: "Enable checking the target OS of serialized modules")
      parser.addOption(spelling: "-enable-testable-attr-requires-testable-module", generator: Generator.flag { Option.enable_testable_attr_requires_testable_module($0) }, isHidden: false, metaVar: nil, helpText: "Enable checking of @testable")
      parser.addOption(spelling: "-enable-testing", generator: Generator.flag { Option.enable_testing($0) }, isHidden: true, metaVar: nil, helpText: "Allows this module's internal API to be accessed for testing")
      parser.addOption(spelling: "-enable-throw-without-try", generator: Generator.flag { Option.enable_throw_without_try($0) }, isHidden: true, metaVar: nil, helpText: "Allow throwing function calls without 'try'")
      parser.addOption(spelling: "-enable-verify-exclusivity", generator: Generator.flag { Option.enable_verify_exclusivity($0) }, isHidden: true, metaVar: nil, helpText: "Enable verification of access markers used to enforce exclusivity.")
      parser.addOption(spelling: "-enforce-exclusivity=", generator: Generator.joined { Option.enforce_exclusivity_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Enforce law of exclusivity")
      parser.addOption(spelling: "-external-pass-pipeline-filename", generator: Generator.separate { Option.external_pass_pipeline_filename($0) }, isHidden: true, metaVar: nil, helpText: "Use the pass pipeline defined by <pass_pipeline_file>")
      parser.addAlias(spelling: "-F=", generator: Generator.joined { Option.F_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-filelist", generator: Generator.separate { Option.filelist($0) }, isHidden: false, metaVar: nil, helpText: "Specify source inputs in a file rather than on the command line")
      parser.addOption(spelling: "-fixit-all", generator: Generator.flag { Option.fixit_all($0) }, isHidden: false, metaVar: nil, helpText: "Apply all fixits from diagnostics without any filtering")
      parser.addOption(spelling: "-force-public-linkage", generator: Generator.flag { Option.force_public_linkage($0) }, isHidden: true, metaVar: nil, helpText: "Force public linkage for private symbols. Used by LLDB.")
      parser.addAlias(spelling: "-force-single-frontend-invocation", generator: Generator.flag { Option.force_single_frontend_invocation($0) }, isHidden: true)
      parser.addOption(spelling: "-framework", generator: Generator.separate { Option.framework($0) }, isHidden: false, metaVar: nil, helpText: "Specifies a framework which should be linked against")
      parser.addOption(spelling: "-Fsystem", generator: Generator.separate { Option.Fsystem($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to system framework search path")
      parser.addOption(spelling: "-F", generator: Generator.joinedOrSeparate { Option.F($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to framework search path")
      parser.addOption(spelling: "-gdwarf-types", generator: Generator.flag { Option.gdwarf_types($0) }, isHidden: false, metaVar: nil, helpText: "Emit full DWARF type info.")
      parser.addOption(spelling: "-gline-tables-only", generator: Generator.flag { Option.gline_tables_only($0) }, isHidden: false, metaVar: nil, helpText: "Emit minimal debug info for backtraces only")
      parser.addOption(spelling: "-gnone", generator: Generator.flag { Option.gnone($0) }, isHidden: false, metaVar: nil, helpText: "Don't emit debug info")
      parser.addOption(spelling: "-group-info-path", generator: Generator.separate { Option.group_info_path($0) }, isHidden: true, metaVar: nil, helpText: "The path to collect the group information of the compiled module")
      parser.addOption(spelling: "-gsil", generator: Generator.flag { Option.debug_on_sil($0) }, isHidden: true, metaVar: nil, helpText: "Write the SIL into a file and generate debug-info to debug on SIL  level.")
      parser.addOption(spelling: "-g", generator: Generator.flag { Option.g($0) }, isHidden: false, metaVar: nil, helpText: "Emit debug info. This is the preferred setting for debugging with LLDB.")
      parser.addOption(spelling: "-help-hidden", generator: Generator.flag { Option.help_hidden($0) }, isHidden: true, metaVar: nil, helpText: "Display available options, including hidden options")
      parser.addAlias(spelling: "--help-hidden", generator: Generator.flag { Option.help_hidden($0) }, isHidden: true)
      parser.addOption(spelling: "-help", generator: Generator.flag { Option.help($0) }, isHidden: false, metaVar: nil, helpText: "Display available options")
      parser.addAlias(spelling: "--help", generator: Generator.flag { Option.help($0) }, isHidden: false)
      parser.addAlias(spelling: "-I=", generator: Generator.joined { Option.I_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-import-cf-types", generator: Generator.flag { Option.import_cf_types($0) }, isHidden: true, metaVar: nil, helpText: "Recognize and import CF types as class types")
      parser.addOption(spelling: "-import-module", generator: Generator.separate { Option.import_module($0) }, isHidden: true, metaVar: nil, helpText: "Implicitly import the specified module")
      parser.addOption(spelling: "-import-objc-header", generator: Generator.separate { Option.import_objc_header($0) }, isHidden: true, metaVar: nil, helpText: "Implicitly imports an Objective-C header file")
      parser.addOption(spelling: "-import-underlying-module", generator: Generator.flag { Option.import_underlying_module($0) }, isHidden: false, metaVar: nil, helpText: "Implicitly imports the Objective-C half of a module")
      parser.addOption(spelling: "-index-store-path", generator: Generator.separate { Option.index_store_path($0) }, isHidden: false, metaVar: nil, helpText: "Store indexing data to <path>")
      parser.addOption(spelling: "-index-system-modules", generator: Generator.flag { Option.index_system_modules($0) }, isHidden: true, metaVar: nil, helpText: "Emit index data for imported serialized swift system modules")
      parser.addOption(spelling: "-interpret", generator: Generator.flag { Option.interpret($0) }, isHidden: true, metaVar: nil, helpText: "Immediate mode")
      parser.addOption(spelling: "-I", generator: Generator.joinedOrSeparate { Option.I($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to the import search path")
      parser.addAlias(spelling: "-L=", generator: Generator.joined { Option.L_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-lazy-astscopes", generator: Generator.flag { Option.lazy_astscopes($0) }, isHidden: false, metaVar: nil, helpText: "Build ASTScopes lazily")
      parser.addOption(spelling: "-L", generator: Generator.joinedOrSeparate { Option.L($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to library link search path")
      parser.addOption(spelling: "-l", generator: Generator.joined { Option.l($0) }, isHidden: false, metaVar: nil, helpText: "Specifies a library which should be linked against")
      parser.addOption(spelling: "-merge-modules", generator: Generator.flag { Option.merge_modules($0) }, isHidden: false, metaVar: nil, helpText: "Merge the input modules without otherwise processing them")
      parser.addOption(spelling: "-migrate-keep-objc-visibility", generator: Generator.flag { Option.migrate_keep_objc_visibility($0) }, isHidden: false, metaVar: nil, helpText: "When migrating, add '@objc' to declarations that would've been implicitly visible in Swift 3")
      parser.addOption(spelling: "-migrator-update-sdk", generator: Generator.flag { Option.migrator_update_sdk($0) }, isHidden: false, metaVar: nil, helpText: "Does nothing. Temporary compatibility flag for Xcode.")
      parser.addOption(spelling: "-migrator-update-swift", generator: Generator.flag { Option.migrator_update_swift($0) }, isHidden: false, metaVar: nil, helpText: "Does nothing. Temporary compatibility flag for Xcode.")
      parser.addOption(spelling: "-module-cache-path", generator: Generator.separate { Option.module_cache_path($0) }, isHidden: false, metaVar: nil, helpText: "Specifies the Clang module cache path")
      parser.addOption(spelling: "-module-interface-preserve-types-as-written", generator: Generator.flag { Option.module_interface_preserve_types_as_written($0) }, isHidden: true, metaVar: nil, helpText: "When emitting a module interface, preserve types as they were written in the source")
      parser.addAlias(spelling: "-module-link-name=", generator: Generator.joined { Option.module_link_name_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-module-link-name", generator: Generator.separate { Option.module_link_name($0) }, isHidden: false, metaVar: nil, helpText: "Library to link against when using this module")
      parser.addAlias(spelling: "-module-name=", generator: Generator.joined { Option.module_name_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-module-name", generator: Generator.separate { Option.module_name($0) }, isHidden: false, metaVar: nil, helpText: "Name of the module to build")
      parser.addOption(spelling: "-no-clang-module-breadcrumbs", generator: Generator.flag { Option.no_clang_module_breadcrumbs($0) }, isHidden: true, metaVar: nil, helpText: "Don't emit DWARF skeleton CUs for imported Clang modules. Use this when building a redistributable static archive.")
      parser.addOption(spelling: "-no-color-diagnostics", generator: Generator.flag { Option.no_color_diagnostics($0) }, isHidden: false, metaVar: nil, helpText: "Do not print diagnostics in color")
      parser.addOption(spelling: "-no-serialize-debugging-options", generator: Generator.flag { Option.no_serialize_debugging_options($0) }, isHidden: false, metaVar: nil, helpText: "Never serialize options for debugging (default: only for apps)")
      parser.addOption(spelling: "-nostdimport", generator: Generator.flag { Option.nostdimport($0) }, isHidden: false, metaVar: nil, helpText: "Don't search the standard library import path for modules")
      parser.addOption(spelling: "-num-threads", generator: Generator.separate { Option.num_threads($0) }, isHidden: false, metaVar: nil, helpText: "Enable multi-threading and specify number of threads")
      parser.addOption(spelling: "-Onone", generator: Generator.flag { Option.Onone($0) }, isHidden: false, metaVar: nil, helpText: "Compile without any optimization")
      parser.addOption(spelling: "-Oplayground", generator: Generator.flag { Option.Oplayground($0) }, isHidden: true, metaVar: nil, helpText: "Compile with optimizations appropriate for a playground")
      parser.addOption(spelling: "-Osize", generator: Generator.flag { Option.Osize($0) }, isHidden: false, metaVar: nil, helpText: "Compile with optimizations and target small code size")
      parser.addOption(spelling: "-Ounchecked", generator: Generator.flag { Option.Ounchecked($0) }, isHidden: false, metaVar: nil, helpText: "Compile with optimizations and remove runtime safety checks")
      parser.addOption(spelling: "-output-filelist", generator: Generator.separate { Option.output_filelist($0) }, isHidden: false, metaVar: nil, helpText: "Specify outputs in a file rather than on the command line")
      parser.addOption(spelling: "-output-request-graphviz", generator: Generator.separate { Option.output_request_graphviz($0) }, isHidden: true, metaVar: nil, helpText: "Emit GraphViz output visualizing the request graph")
      parser.addOption(spelling: "-O", generator: Generator.flag { Option.O($0) }, isHidden: false, metaVar: nil, helpText: "Compile with optimizations")
      parser.addOption(spelling: "-o", generator: Generator.joinedOrSeparate { Option.o($0) }, isHidden: false, metaVar: nil, helpText: "Write output to <file>")
      parser.addOption(spelling: "-package-description-version", generator: Generator.separate { Option.package_description_version($0) }, isHidden: true, metaVar: nil, helpText: "The version number to be applied on the input for the PackageDescription availability kind")
      parser.addOption(spelling: "-parse-as-library", generator: Generator.flag { Option.parse_as_library($0) }, isHidden: false, metaVar: nil, helpText: "Parse the input file(s) as libraries, not scripts")
      parser.addOption(spelling: "-parse-sil", generator: Generator.flag { Option.parse_sil($0) }, isHidden: false, metaVar: nil, helpText: "Parse the input file as SIL code, not Swift source")
      parser.addOption(spelling: "-parse-stdlib", generator: Generator.flag { Option.parse_stdlib($0) }, isHidden: true, metaVar: nil, helpText: "Parse the input file(s) as the Swift standard library")
      parser.addOption(spelling: "-parse", generator: Generator.flag { Option.parse($0) }, isHidden: false, metaVar: nil, helpText: "Parse input file(s)")
      parser.addOption(spelling: "-pc-macro", generator: Generator.flag { Option.pc_macro($0) }, isHidden: true, metaVar: nil, helpText: "Apply the 'program counter simulation' macro")
      parser.addOption(spelling: "-pch-disable-validation", generator: Generator.flag { Option.pch_disable_validation($0) }, isHidden: true, metaVar: nil, helpText: "Disable validating the persistent PCH")
      parser.addOption(spelling: "-pch-output-dir", generator: Generator.separate { Option.pch_output_dir($0) }, isHidden: true, metaVar: nil, helpText: "Directory to persist automatically created precompiled bridging headers")
      parser.addOption(spelling: "-playground-high-performance", generator: Generator.flag { Option.playground_high_performance($0) }, isHidden: true, metaVar: nil, helpText: "Omit instrumentation that has a high runtime performance impact")
      parser.addOption(spelling: "-playground", generator: Generator.flag { Option.playground($0) }, isHidden: true, metaVar: nil, helpText: "Apply the playground semantics and transformation")
      parser.addAlias(spelling: "-prebuilt-module-cache-path=", generator: Generator.joined { Option.prebuilt_module_cache_path_EQ($0) }, isHidden: true)
      parser.addOption(spelling: "-prebuilt-module-cache-path", generator: Generator.separate { Option.prebuilt_module_cache_path($0) }, isHidden: true, metaVar: nil, helpText: "Directory of prebuilt modules for loading module interfaces")
      parser.addOption(spelling: "-primary-filelist", generator: Generator.separate { Option.primary_filelist($0) }, isHidden: false, metaVar: nil, helpText: "Specify primary inputs in a file rather than on the command line")
      parser.addOption(spelling: "-primary-file", generator: Generator.separate { Option.primary_file($0) }, isHidden: false, metaVar: nil, helpText: "Produce output for this file, not the whole module")
      parser.addOption(spelling: "-print-ast", generator: Generator.flag { Option.print_ast($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s) and pretty print AST(s)")
      parser.addOption(spelling: "-print-clang-stats", generator: Generator.flag { Option.print_clang_stats($0) }, isHidden: false, metaVar: nil, helpText: "Print Clang importer statistics")
      parser.addOption(spelling: "-print-inst-counts", generator: Generator.flag { Option.print_inst_counts($0) }, isHidden: true, metaVar: nil, helpText: "Before IRGen, count all the various SIL instructions. Must be used in conjunction with -print-stats.")
      parser.addOption(spelling: "-print-llvm-inline-tree", generator: Generator.flag { Option.print_llvm_inline_tree($0) }, isHidden: true, metaVar: nil, helpText: "Print the LLVM inline tree.")
      parser.addOption(spelling: "-print-stats", generator: Generator.flag { Option.print_stats($0) }, isHidden: true, metaVar: nil, helpText: "Print various statistics")
      parser.addOption(spelling: "-profile-coverage-mapping", generator: Generator.flag { Option.profile_coverage_mapping($0) }, isHidden: false, metaVar: nil, helpText: "Generate coverage data for use with profiled execution counts")
      parser.addOption(spelling: "-profile-generate", generator: Generator.flag { Option.profile_generate($0) }, isHidden: false, metaVar: nil, helpText: "Generate instrumented code to collect execution counts")
      parser.addOption(spelling: "-profile-stats-entities", generator: Generator.flag { Option.profile_stats_entities($0) }, isHidden: true, metaVar: nil, helpText: "Profile changes to stats in -stats-output-dir, subdivided by source entity")
      parser.addOption(spelling: "-profile-stats-events", generator: Generator.flag { Option.profile_stats_events($0) }, isHidden: true, metaVar: nil, helpText: "Profile changes to stats in -stats-output-dir")
      parser.addOption(spelling: "-profile-use=", generator: Generator.commaJoined { Option.profile_use($0) }, isHidden: false, metaVar: nil, helpText: "Supply a profdata file to enable profile-guided optimization")
      parser.addOption(spelling: "-read-legacy-type-info-path=", generator: Generator.joined { Option.read_legacy_type_info_path_EQ($0) }, isHidden: true, metaVar: nil, helpText: "Read legacy type layout from the given path instead of default path")
      parser.addOption(spelling: "-remove-runtime-asserts", generator: Generator.flag { Option.RemoveRuntimeAsserts($0) }, isHidden: false, metaVar: nil, helpText: "Remove runtime safety checks.")
      parser.addOption(spelling: "-repl", generator: Generator.flag { Option.repl($0) }, isHidden: true, metaVar: nil, helpText: "REPL mode (the default if there is no input file)")
      parser.addOption(spelling: "-report-errors-to-debugger", generator: Generator.flag { Option.report_errors_to_debugger($0) }, isHidden: true, metaVar: nil, helpText: "Deprecated, will be removed in future versions.")
      parser.addOption(spelling: "-require-explicit-availability-target", generator: Generator.separate { Option.require_explicit_availability_target($0) }, isHidden: false, metaVar: nil, helpText: "Suggest fix-its adding @available(<target>, *) to public declarations without availability")
      parser.addOption(spelling: "-require-explicit-availability", generator: Generator.flag { Option.require_explicit_availability($0) }, isHidden: false, metaVar: nil, helpText: "Require explicit availability on public declarations")
      parser.addOption(spelling: "-resolve-imports", generator: Generator.flag { Option.resolve_imports($0) }, isHidden: false, metaVar: nil, helpText: "Parse and resolve imports in input file(s)")
      parser.addOption(spelling: "-resource-dir", generator: Generator.separate { Option.resource_dir($0) }, isHidden: true, metaVar: nil, helpText: "The directory that holds the compiler resource files")
      parser.addOption(spelling: "-Rmodule-interface-rebuild", generator: Generator.flag { Option.Rmodule_interface_rebuild($0) }, isHidden: true, metaVar: nil, helpText: "Emits a remark if an imported module needs to be re-compiled from its module interface")
      parser.addOption(spelling: "-Rpass-missed=", generator: Generator.joined { Option.Rpass_missed_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Report missed transformations by optimization passes whose name matches the given POSIX regular expression")
      parser.addOption(spelling: "-Rpass=", generator: Generator.joined { Option.Rpass_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Report performed transformations by optimization passes whose name matches the given POSIX regular expression")
      parser.addOption(spelling: "-runtime-compatibility-version", generator: Generator.separate { Option.runtime_compatibility_version($0) }, isHidden: false, metaVar: nil, helpText: "Link compatibility library for Swift runtime version, or 'none'")
      parser.addOption(spelling: "-sanitize-coverage=", generator: Generator.commaJoined { Option.sanitize_coverage_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Specify the type of coverage instrumentation for Sanitizers and additional options separated by commas")
      parser.addOption(spelling: "-sanitize=", generator: Generator.commaJoined { Option.sanitize_EQ($0) }, isHidden: false, metaVar: nil, helpText: "Turn on runtime checks for erroneous behavior.")
      parser.addOption(spelling: "-save-optimization-record-path", generator: Generator.separate { Option.save_optimization_record_path($0) }, isHidden: false, metaVar: nil, helpText: "Specify the file name of any generated YAML optimization record")
      parser.addOption(spelling: "-save-optimization-record", generator: Generator.flag { Option.save_optimization_record($0) }, isHidden: false, metaVar: nil, helpText: "Generate a YAML optimization record file")
      parser.addOption(spelling: "-sdk", generator: Generator.separate { Option.sdk($0) }, isHidden: false, metaVar: nil, helpText: "Compile against <sdk>")
      parser.addOption(spelling: "-serialize-debugging-options", generator: Generator.flag { Option.serialize_debugging_options($0) }, isHidden: false, metaVar: nil, helpText: "Always serialize options for debugging (default: only for apps)")
      parser.addAlias(spelling: "-serialize-diagnostics-path=", generator: Generator.joined { Option.serialize_diagnostics_path_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-serialize-diagnostics-path", generator: Generator.separate { Option.serialize_diagnostics_path($0) }, isHidden: false, metaVar: nil, helpText: "Emit a serialized diagnostics file to <path>")
      parser.addOption(spelling: "-serialize-diagnostics", generator: Generator.flag { Option.serialize_diagnostics($0) }, isHidden: false, metaVar: nil, helpText: "Serialize diagnostics in a binary format")
      parser.addOption(spelling: "-serialize-module-interface-dependency-hashes", generator: Generator.flag { Option.serialize_module_interface_dependency_hashes($0) }, isHidden: false, metaVar: nil, helpText: nil)
      parser.addAlias(spelling: "-serialize-parseable-module-interface-dependency-hashes", generator: Generator.flag { Option.serialize_parseable_module_interface_dependency_hashes($0) }, isHidden: false)
      parser.addOption(spelling: "-show-diagnostics-after-fatal", generator: Generator.flag { Option.show_diagnostics_after_fatal($0) }, isHidden: false, metaVar: nil, helpText: "Keep emitting subsequent diagnostics after a fatal error")
      parser.addOption(spelling: "-sil-debug-serialization", generator: Generator.flag { Option.sil_debug_serialization($0) }, isHidden: true, metaVar: nil, helpText: "Do not eliminate functions in Mandatory Inlining/SILCombine dead functions. (for debugging only)")
      parser.addOption(spelling: "-sil-inline-caller-benefit-reduction-factor", generator: Generator.separate { Option.sil_inline_caller_benefit_reduction_factor($0) }, isHidden: true, metaVar: nil, helpText: "Controls the aggressiveness of performance inlining in -Osize mode by reducing the base benefits of a caller (lower value permits more inlining!)")
      parser.addOption(spelling: "-sil-inline-threshold", generator: Generator.separate { Option.sil_inline_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Controls the aggressiveness of performance inlining")
      parser.addOption(spelling: "-sil-merge-partial-modules", generator: Generator.flag { Option.sil_merge_partial_modules($0) }, isHidden: true, metaVar: nil, helpText: "Merge SIL from all partial swiftmodules into the final module")
      parser.addOption(spelling: "-sil-unroll-threshold", generator: Generator.separate { Option.sil_unroll_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Controls the aggressiveness of loop unrolling")
      parser.addOption(spelling: "-sil-verify-all", generator: Generator.flag { Option.sil_verify_all($0) }, isHidden: true, metaVar: nil, helpText: "Verify SIL after each transform")
      parser.addOption(spelling: "-solver-disable-shrink", generator: Generator.flag { Option.solver_disable_shrink($0) }, isHidden: true, metaVar: nil, helpText: "Disable the shrink phase of expression type checking")
      parser.addOption(spelling: "-solver-enable-operator-designated-types", generator: Generator.flag { Option.solver_enable_operator_designated_types($0) }, isHidden: true, metaVar: nil, helpText: "Enable operator designated types in constraint solver")
      parser.addOption(spelling: "-solver-expression-time-threshold=", generator: Generator.joined { Option.solver_expression_time_threshold_EQ($0) }, isHidden: true, metaVar: nil, helpText: nil)
      parser.addOption(spelling: "-solver-memory-threshold", generator: Generator.separate { Option.solver_memory_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Set the upper bound for memory consumption, in bytes, by the constraint solver")
      parser.addOption(spelling: "-solver-shrink-unsolved-threshold", generator: Generator.separate { Option.solver_shrink_unsolved_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Set The upper bound to number of sub-expressions unsolved before termination of the shrink phrase")
      parser.addOption(spelling: "-stack-promotion-limit", generator: Generator.separate { Option.stack_promotion_limit($0) }, isHidden: true, metaVar: nil, helpText: "Limit the size of stack promoted objects to the provided number of bytes.")
      parser.addOption(spelling: "-static", generator: Generator.flag { Option.static($0) }, isHidden: false, metaVar: nil, helpText: "Make this module statically linkable and make the output of -emit-library a static library.")
      parser.addOption(spelling: "-stats-output-dir", generator: Generator.separate { Option.stats_output_dir($0) }, isHidden: true, metaVar: nil, helpText: "Directory to write unified compilation-statistics files to")
      parser.addOption(spelling: "-stress-astscope-lookup", generator: Generator.flag { Option.stress_astscope_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Stress ASTScope-based unqualified name lookup (for testing)")
      parser.addOption(spelling: "-supplementary-output-file-map", generator: Generator.separate { Option.supplementary_output_file_map($0) }, isHidden: false, metaVar: nil, helpText: "Specify supplementary outputs in a file rather than on the command line")
      parser.addOption(spelling: "-suppress-static-exclusivity-swap", generator: Generator.flag { Option.suppress_static_exclusivity_swap($0) }, isHidden: true, metaVar: nil, helpText: "Suppress static violations of exclusive access with swap()")
      parser.addOption(spelling: "-suppress-warnings", generator: Generator.flag { Option.suppress_warnings($0) }, isHidden: false, metaVar: nil, helpText: "Suppress all warnings")
      parser.addOption(spelling: "-swift-version", generator: Generator.separate { Option.swift_version($0) }, isHidden: false, metaVar: nil, helpText: "Interpret input according to a specific Swift language version number")
      parser.addOption(spelling: "-switch-checking-invocation-threshold=", generator: Generator.joined { Option.switch_checking_invocation_threshold_EQ($0) }, isHidden: true, metaVar: nil, helpText: nil)
      parser.addAlias(spelling: "-S", generator: Generator.flag { Option.S($0) }, isHidden: false)
      parser.addOption(spelling: "-target-cpu", generator: Generator.separate { Option.target_cpu($0) }, isHidden: false, metaVar: nil, helpText: "Generate code for a particular CPU variant")
      parser.addAlias(spelling: "--target=", generator: Generator.joined { Option.target_legacy_spelling($0) }, isHidden: false)
      parser.addOption(spelling: "-target", generator: Generator.separate { Option.target($0) }, isHidden: false, metaVar: nil, helpText: "Generate code for the given target <triple>, such as x86_64-apple-macos10.9")
      parser.addAlias(spelling: "-tbd-compatibility-version=", generator: Generator.joined { Option.tbd_compatibility_version_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-tbd-compatibility-version", generator: Generator.separate { Option.tbd_compatibility_version($0) }, isHidden: false, metaVar: nil, helpText: "The compatibility_version to use in an emitted TBD file")
      parser.addAlias(spelling: "-tbd-current-version=", generator: Generator.joined { Option.tbd_current_version_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-tbd-current-version", generator: Generator.separate { Option.tbd_current_version($0) }, isHidden: false, metaVar: nil, helpText: "The current_version to use in an emitted TBD file")
      parser.addAlias(spelling: "-tbd-install_name=", generator: Generator.joined { Option.tbd_install_name_EQ($0) }, isHidden: false)
      parser.addOption(spelling: "-tbd-install_name", generator: Generator.separate { Option.tbd_install_name($0) }, isHidden: false, metaVar: nil, helpText: "The install_name to use in an emitted TBD file")
      parser.addOption(spelling: "-tools-directory", generator: Generator.separate { Option.tools_directory($0) }, isHidden: false, metaVar: nil, helpText: "Look for external executables (ld, clang, binutils) in <directory>")
      parser.addOption(spelling: "-trace-stats-events", generator: Generator.flag { Option.trace_stats_events($0) }, isHidden: true, metaVar: nil, helpText: "Trace changes to stats in -stats-output-dir")
      parser.addOption(spelling: "-track-system-dependencies", generator: Generator.flag { Option.track_system_dependencies($0) }, isHidden: false, metaVar: nil, helpText: "Track system dependencies while emitting Make-style dependencies")
      parser.addAlias(spelling: "-triple", generator: Generator.separate { Option.triple($0) }, isHidden: false)
      parser.addOption(spelling: "-type-info-dump-filter=", generator: Generator.joined { Option.type_info_dump_filter_EQ($0) }, isHidden: true, metaVar: nil, helpText: "One of 'all', 'resilient' or 'fragile'")
      parser.addOption(spelling: "-typecheck", generator: Generator.flag { Option.typecheck($0) }, isHidden: false, metaVar: nil, helpText: "Parse and type-check input file(s)")
      parser.addOption(spelling: "-typo-correction-limit", generator: Generator.separate { Option.typo_correction_limit($0) }, isHidden: true, metaVar: nil, helpText: "Limit the number of times the compiler will attempt typo correction to <n>")
      parser.addOption(spelling: "-update-code", generator: Generator.flag { Option.update_code($0) }, isHidden: true, metaVar: nil, helpText: "Update Swift code")
      parser.addOption(spelling: "-use-jit", generator: Generator.flag { Option.use_jit($0) }, isHidden: true, metaVar: nil, helpText: "Register Objective-C classes as if the JIT were in use")
      parser.addOption(spelling: "-use-malloc", generator: Generator.flag { Option.use_malloc($0) }, isHidden: true, metaVar: nil, helpText: "Allocate internal data structures using malloc (for memory debugging)")
      parser.addOption(spelling: "-validate-tbd-against-ir=", generator: Generator.joined { Option.validate_tbd_against_ir_EQ($0) }, isHidden: true, metaVar: nil, helpText: "Compare the symbols in the IR against the TBD file that would be generated.")
      parser.addOption(spelling: "-value-recursion-threshold", generator: Generator.separate { Option.value_recursion_threshold($0) }, isHidden: true, metaVar: nil, helpText: "Set the maximum depth for direct recursion in value types")
      parser.addOption(spelling: "-verify-apply-fixes", generator: Generator.flag { Option.verify_apply_fixes($0) }, isHidden: false, metaVar: nil, helpText: "Like -verify, but updates the original source file")
      parser.addOption(spelling: "-verify-generic-signatures", generator: Generator.separate { Option.verify_generic_signatures($0) }, isHidden: false, metaVar: nil, helpText: "Verify the generic signatures in the given module")
      parser.addOption(spelling: "-verify-ignore-unknown", generator: Generator.flag { Option.verify_ignore_unknown($0) }, isHidden: false, metaVar: nil, helpText: "Allow diagnostics for '<unknown>' location in verify mode")
      parser.addOption(spelling: "-verify-syntax-tree", generator: Generator.flag { Option.verify_syntax_tree($0) }, isHidden: false, metaVar: nil, helpText: "Verify that no unknown nodes exist in the libSyntax tree")
      parser.addOption(spelling: "-verify-type-layout", generator: Generator.joinedOrSeparate { Option.verify_type_layout($0) }, isHidden: true, metaVar: nil, helpText: "Verify compile-time and runtime type layout information for type")
      parser.addOption(spelling: "-verify", generator: Generator.flag { Option.verify($0) }, isHidden: false, metaVar: nil, helpText: "Verify diagnostics against expected-{error|warning|note} annotations")
      parser.addOption(spelling: "-vfsoverlay", generator: Generator.joinedOrSeparate { Option.vfsoverlay($0) }, isHidden: false, metaVar: nil, helpText: "Add directory to VFS overlay file")
      parser.addOption(spelling: "-warn-if-astscope-lookup", generator: Generator.flag { Option.warn_if_astscope_lookup($0) }, isHidden: false, metaVar: nil, helpText: "Print a warning if ASTScope lookup is used")
      parser.addOption(spelling: "-warn-implicit-overrides", generator: Generator.flag { Option.warn_implicit_overrides($0) }, isHidden: false, metaVar: nil, helpText: "Warn about implicit overrides of protocol members")
      parser.addAlias(spelling: "-warn-long-expression-type-checking=", generator: Generator.joined { Option.warn_long_expression_type_checking_EQ($0) }, isHidden: true)
      parser.addOption(spelling: "-warn-long-expression-type-checking", generator: Generator.separate { Option.warn_long_expression_type_checking($0) }, isHidden: true, metaVar: nil, helpText: "Warns when type-checking a function takes longer than <n> ms")
      parser.addAlias(spelling: "-warn-long-function-bodies=", generator: Generator.joined { Option.warn_long_function_bodies_EQ($0) }, isHidden: true)
      parser.addOption(spelling: "-warn-long-function-bodies", generator: Generator.separate { Option.warn_long_function_bodies($0) }, isHidden: true, metaVar: nil, helpText: "Warns when type-checking a function takes longer than <n> ms")
      parser.addOption(spelling: "-warn-swift3-objc-inference-complete", generator: Generator.flag { Option.warn_swift3_objc_inference_complete($0) }, isHidden: false, metaVar: nil, helpText: "Warn about deprecated @objc inference in Swift 3 for every declaration that will no longer be inferred as @objc in Swift 4")
      parser.addOption(spelling: "-warn-swift3-objc-inference-minimal", generator: Generator.flag { Option.warn_swift3_objc_inference_minimal($0) }, isHidden: false, metaVar: nil, helpText: "Warn about deprecated @objc inference in Swift 3 based on direct uses of the Objective-C entrypoint")
      parser.addAlias(spelling: "-warn-swift3-objc-inference", generator: Generator.flag { Option.warn_swift3_objc_inference($0) }, isHidden: true)
      parser.addOption(spelling: "-warnings-as-errors", generator: Generator.flag { Option.warnings_as_errors($0) }, isHidden: false, metaVar: nil, helpText: "Treat warnings as errors")
      parser.addOption(spelling: "-whole-module-optimization", generator: Generator.flag { Option.whole_module_optimization($0) }, isHidden: false, metaVar: nil, helpText: "Optimize input files together instead of individually")
      parser.addAlias(spelling: "-wmo", generator: Generator.flag { Option.wmo($0) }, isHidden: true)
      parser.addOption(spelling: "-Xcc", generator: Generator.separate { Option.Xcc($0) }, isHidden: false, metaVar: nil, helpText: "Pass <arg> to the C/C++/Objective-C compiler")
      parser.addOption(spelling: "-Xllvm", generator: Generator.separate { Option.Xllvm($0) }, isHidden: true, metaVar: nil, helpText: "Pass <arg> to LLVM.")
      parser.addOption(spelling: "--", generator: Generator.remaining { Option._DASH_DASH($0) }, isHidden: false, metaVar: nil, helpText: nil)
    return parser
  }
}

extension OptionParser {
  public static var moduleWrapOptions: OptionParser {
    var parser = OptionParser()
      parser.addOption(spelling: "-help", generator: Generator.flag { Option.help($0) }, isHidden: false, metaVar: nil, helpText: "Display available options")
      parser.addAlias(spelling: "--help", generator: Generator.flag { Option.help($0) }, isHidden: false)
      parser.addOption(spelling: "-o", generator: Generator.joinedOrSeparate { Option.o($0) }, isHidden: false, metaVar: nil, helpText: "Write output to <file>")
      parser.addOption(spelling: "-target", generator: Generator.separate { Option.target($0) }, isHidden: false, metaVar: nil, helpText: "Generate code for the given target <triple>, such as x86_64-apple-macos10.9")
    return parser
  }
}

extension OptionParser {
  public static var autolinkExtractOptions: OptionParser {
    var parser = OptionParser()
      parser.addOption(spelling: "-help", generator: Generator.flag { Option.help($0) }, isHidden: false, metaVar: nil, helpText: "Display available options")
      parser.addAlias(spelling: "--help", generator: Generator.flag { Option.help($0) }, isHidden: false)
      parser.addOption(spelling: "-o", generator: Generator.joinedOrSeparate { Option.o($0) }, isHidden: false, metaVar: nil, helpText: "Write output to <file>")
    return parser
  }
}

extension OptionParser {
  public static var indentOptions: OptionParser {
    var parser = OptionParser()
      parser.addOption(spelling: "-help", generator: Generator.flag { Option.help($0) }, isHidden: false, metaVar: nil, helpText: "Display available options")
      parser.addAlias(spelling: "--help", generator: Generator.flag { Option.help($0) }, isHidden: false)
      parser.addOption(spelling: "-in-place", generator: Generator.flag { Option.in_place($0) }, isHidden: false, metaVar: nil, helpText: "Overwrite input file with formatted file.")
      parser.addOption(spelling: "-indent-switch-case", generator: Generator.flag { Option.indent_switch_case($0) }, isHidden: false, metaVar: nil, helpText: "Indent cases in switch statements.")
      parser.addOption(spelling: "-indent-width", generator: Generator.separate { Option.indent_width($0) }, isHidden: false, metaVar: nil, helpText: "Number of characters to indent.")
      parser.addOption(spelling: "-line-range", generator: Generator.separate { Option.line_range($0) }, isHidden: false, metaVar: nil, helpText: "<start line>:<end line>. Formats a range of lines (1-based). Can only be used with one input file.")
      parser.addOption(spelling: "-o", generator: Generator.joinedOrSeparate { Option.o($0) }, isHidden: false, metaVar: nil, helpText: "Write output to <file>")
      parser.addOption(spelling: "-tab-width", generator: Generator.separate { Option.tab_width($0) }, isHidden: false, metaVar: nil, helpText: "Width of tab character.")
      parser.addOption(spelling: "-use-tabs", generator: Generator.flag { Option.use_tabs($0) }, isHidden: false, metaVar: nil, helpText: "Use tabs for indentation.")
    return parser
  }
}
