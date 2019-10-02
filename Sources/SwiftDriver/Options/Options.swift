
extension Option {
  public static let INPUT: Option = Option("<input>", .input, attributes: [.argumentIsPath])
  public static let _HASH_HASH_HASH: Option = Option("-###", .flag, alias: Option.driver_print_jobs)
  public static let api_diff_data_dir: Option = Option("-api-diff-data-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Load platform and version specific API migration data files from <path>. Ignored if -api-diff-data-file is specified.")
  public static let api_diff_data_file: Option = Option("-api-diff-data-file", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "API migration data is from <path>")
  public static let enable_app_extension: Option = Option("-application-extension", .flag, attributes: [.frontend, .noInteractive], helpText: "Restrict code to those available for App Extensions")
  public static let AssertConfig: Option = Option("-assert-config", .separate, attributes: [.frontend], helpText: "Specify the assert_configuration replacement. Possible values are Debug, Release, Unchecked, DisableReplacement.")
  public static let AssumeSingleThreaded: Option = Option("-assume-single-threaded", .flag, attributes: [.helpHidden, .frontend], helpText: "Assume that code will be executed in a single-threaded environment")
  public static let autolink_force_load: Option = Option("-autolink-force-load", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Force ld to link against this module even if no symbols are used")
  public static let autolink_library: Option = Option("-autolink-library", .separate, attributes: [.frontend, .noDriver], helpText: "Add dependent library")
  public static let build_module_from_parseable_interface: Option = Option("-build-module-from-parseable-interface", .flag, alias: Option.compile_module_from_interface, attributes: [.helpHidden, .frontend, .noDriver], group: .modes)
  public static let bypass_batch_mode_checks: Option = Option("-bypass-batch-mode-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Bypass checks for batch-mode errors.")
  public static let check_onone_completeness: Option = Option("-check-onone-completeness", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print errors if the compile OnoneSupport module is missing symbols")
  public static let code_complete_call_pattern_heuristics: Option = Option("-code-complete-call-pattern-heuristics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use heuristics to guess whether we want call pattern completions")
  public static let code_complete_inits_in_postfix_expr: Option = Option("-code-complete-inits-in-postfix-expr", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Include initializers when completing a postfix expression")
  public static let color_diagnostics: Option = Option("-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Print diagnostics in color")
  public static let compile_module_from_interface: Option = Option("-compile-module-from-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Treat the (single) input as a swiftinterface and produce a module", group: .modes)
  public static let continue_building_after_errors: Option = Option("-continue-building-after-errors", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Continue building, even after errors are encountered")
  public static let crosscheck_unqualified_lookup: Option = Option("-crosscheck-unqualified-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Compare legacy DeclContext- to ASTScope-based unqualified name lookup (for debugging)")
  public static let c: Option = Option("-c", .flag, alias: Option.emit_object, attributes: [.frontend, .noInteractive], group: .modes)
  public static let debug_assert_after_parse: Option = Option("-debug-assert-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure after parsing", group: .debug_crash)
  public static let debug_assert_immediately: Option = Option("-debug-assert-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure immediately", group: .debug_crash)
  public static let debug_constraints_attempt: Option = Option("-debug-constraints-attempt", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint solver at a given attempt")
  public static let debug_constraints_on_line_EQ: Option = Option("-debug-constraints-on-line=", .joined, alias: Option.debug_constraints_on_line, attributes: [.helpHidden, .frontend, .noDriver])
  public static let debug_constraints_on_line: Option = Option("-debug-constraints-on-line", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<line>", helpText: "Debug the constraint solver for expressions on <line>")
  public static let debug_constraints: Option = Option("-debug-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint-based type checker")
  public static let debug_crash_after_parse: Option = Option("-debug-crash-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash after parsing", group: .debug_crash)
  public static let debug_crash_immediately: Option = Option("-debug-crash-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash immediately", group: .debug_crash)
  public static let debug_cycles: Option = Option("-debug-cycles", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print out debug dumps when cycles are detected in evaluation")
  public static let debug_diagnostic_names: Option = Option("-debug-diagnostic-names", .flag, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Include diagnostic names when printing")
  public static let debug_forbid_typecheck_prefix: Option = Option("-debug-forbid-typecheck-prefix", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Triggers llvm fatal_error if typechecker tries to typecheck a decl with the provided prefix name")
  public static let debug_generic_signatures: Option = Option("-debug-generic-signatures", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug generic signatures")
  public static let debug_info_format: Option = Option("-debug-info-format=", .joined, attributes: [.frontend], helpText: "Specify the debug info format type to either 'dwarf' or 'codeview'")
  public static let debug_info_store_invocation: Option = Option("-debug-info-store-invocation", .flag, attributes: [.frontend], helpText: "Emit the compiler invocation in the debug info.")
  public static let debug_prefix_map: Option = Option("-debug-prefix-map", .separate, attributes: [.frontend], helpText: "Remap source paths in debug info")
  public static let debug_time_compilation: Option = Option("-debug-time-compilation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Prints the time taken by each compilation phase")
  public static let debug_time_expression_type_checking: Option = Option("-debug-time-expression-type-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each expression")
  public static let debug_time_function_bodies: Option = Option("-debug-time-function-bodies", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each function body")
  public static let debugger_support: Option = Option("-debugger-support", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Process swift code as if running in the debugger")
  public static let debugger_testing_transform: Option = Option("-debugger-testing-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Instrument the code with calls to an intrinsic that record the expected values of local variables so they can be compared against the results from the debugger.")
  public static let deprecated_integrated_repl: Option = Option("-deprecated-integrated-repl", .flag, attributes: [.frontend, .noBatch], group: .modes)
  public static let diagnostics_editor_mode: Option = Option("-diagnostics-editor-mode", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnostics will be used in editor")
  public static let disable_access_control: Option = Option("-disable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't respect access control restrictions")
  public static let disable_arc_opts: Option = Option("-disable-arc-opts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL ARC optimization passes.")
  public static let disable_astscope_lookup: Option = Option("-disable-astscope-lookup", .flag, attributes: [.frontend], helpText: "Disable ASTScope-based unqualified name lookup")
  public static let disable_autolink_framework: Option = Option("-disable-autolink-framework", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable autolinking against the provided framework")
  public static let disable_autolinking_runtime_compatibility_dynamic_replacements: Option = Option("-disable-autolinking-runtime-compatibility-dynamic-replacements", .flag, attributes: [.frontend], helpText: "Do not use autolinking for the dynamic replacement runtime compatibility library")
  public static let disable_autolinking_runtime_compatibility: Option = Option("-disable-autolinking-runtime-compatibility", .flag, attributes: [.frontend], helpText: "Do not use autolinking for runtime compatibility libraries")
  public static let disable_availability_checking: Option = Option("-disable-availability-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable checking for potentially unavailable APIs")
  public static let disable_batch_mode: Option = Option("-disable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Disable combining frontend jobs into batches")
  public static let disable_bridging_pch: Option = Option("-disable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Disable automatic generation of bridging PCH files")
  public static let disable_constraint_solver_performance_hacks: Option = Option("-disable-constraint-solver-performance-hacks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable all the hacks in the constraint solver")
  public static let disable_deserialization_recovery: Option = Option("-disable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't attempt to recover from missing xrefs (etc) in swiftmodules")
  public static let disable_diagnostic_passes: Option = Option("-disable-diagnostic-passes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run diagnostic passes")
  public static let disable_function_builder_one_way_constraints: Option = Option("-disable-function-builder-one-way-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable one-way constraints in the function builder transformation")
  public static let disable_incremental_llvm_codegeneration: Option = Option("-disable-incremental-llvm-codegen", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable incremental llvm code generation.")
  public static let disable_legacy_type_info: Option = Option("-disable-legacy-type-info", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Completely disable legacy type layout")
  public static let disable_llvm_optzns: Option = Option("-disable-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run LLVM optimization passes")
  public static let disable_llvm_slp_vectorizer: Option = Option("-disable-llvm-slp-vectorizer", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run LLVM SLP vectorizer")
  public static let disable_llvm_value_names: Option = Option("-disable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't add names to local values in LLVM IR")
  public static let disable_llvm_verify: Option = Option("-disable-llvm-verify", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run the LLVM IR verifier.")
  public static let disable_migrator_fixits: Option = Option("-disable-migrator-fixits", .flag, attributes: [.frontend, .noInteractive], helpText: "Disable the Migrator phase which automatically applies fix-its")
  public static let disable_modules_validate_system_headers: Option = Option("-disable-modules-validate-system-headers", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating system headers in the Clang importer")
  public static let disable_named_lazy_member_loading: Option = Option("-disable-named-lazy-member-loading", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable per-name lazy member loading")
  public static let disable_nonfrozen_enum_exhaustivity_diagnostics: Option = Option("-disable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow switches over non-frozen enums without catch-all cases")
  public static let disable_nskeyedarchiver_diagnostics: Option = Option("-disable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow classes with unstable mangled names to adopt NSCoding")
  public static let disable_objc_attr_requires_foundation_module: Option = Option("-disable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable requiring uses of @objc to require importing the Foundation module")
  public static let disable_objc_interop: Option = Option("-disable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable Objective-C interop code generation and config directives")
  public static let disable_parser_lookup: Option = Option("-disable-parser-lookup", .flag, attributes: [.frontend], helpText: "Disable parser lookup & use ast scope lookup only (experimental)")
  public static let disable_playground_transform: Option = Option("-disable-playground-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable playground transformation")
  public static let disable_previous_implementation_calls_in_dynamic_replacements: Option = Option("-disable-previous-implementation-calls-in-dynamic-replacements", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable calling the previous implementation in dynamic replacements")
  public static let disable_reflection_metadata: Option = Option("-disable-reflection-metadata", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of reflection metadata for nominal types")
  public static let disable_reflection_names: Option = Option("-disable-reflection-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of names of stored properties and enum cases inreflection metadata")
  public static let disable_serialization_nested_type_lookup_table: Option = Option("-disable-serialization-nested-type-lookup-table", .flag, attributes: [.frontend, .noDriver], helpText: "Force module merging to use regular lookups to find nested types")
  public static let disable_sil_ownership_verifier: Option = Option("-disable-sil-ownership-verifier", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not verify ownership invariants during SIL Verification ")
  public static let disable_sil_partial_apply: Option = Option("-disable-sil-partial-apply", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable use of partial_apply in SIL generation")
  public static let disable_sil_perf_optzns: Option = Option("-disable-sil-perf-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL performance optimization passes")
  public static let disable_swift_bridge_attr: Option = Option("-disable-swift-bridge-attr", .flag, attributes: [.helpHidden, .frontend], helpText: "Disable using the swift bridge attribute")
  public static let disable_swift_specific_llvm_optzns: Option = Option("-disable-swift-specific-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run Swift specific LLVM optimization passes.")
  public static let disable_swift3_objc_inference: Option = Option("-disable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 4 behavior)")
  public static let disable_target_os_checking: Option = Option("-disable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking the target OS of serialized modules")
  public static let disable_testable_attr_requires_testable_module: Option = Option("-disable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking of @testable")
  public static let disable_tsan_inout_instrumentation: Option = Option("-disable-tsan-inout-instrumentation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable treatment of inout parameters as Thread Sanitizer accesses")
  public static let disable_typo_correction: Option = Option("-disable-typo-correction", .flag, attributes: [.frontend, .noDriver], helpText: "Disable typo correction")
  public static let disable_verify_exclusivity: Option = Option("-disable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diable verification of access markers used to enforce exclusivity.")
  public static let driver_always_rebuild_dependents: Option = Option("-driver-always-rebuild-dependents", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Always rebuild dependents of files that have been modified", group: .internal_debug)
  public static let driver_batch_count: Option = Option("-driver-batch-count", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number of batch-mode partitions, rather than partitioning dynamically", group: .internal_debug)
  public static let driver_batch_seed: Option = Option("-driver-batch-seed", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given seed value to randomize batch-mode partitions", group: .internal_debug)
  public static let driver_batch_size_limit: Option = Option("-driver-batch-size-limit", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number as the upper limit on dynamic batch-mode partition size", group: .internal_debug)
  public static let driver_emit_experimental_dependency_dot_file_after_every_import: Option = Option("-driver-emit-experimental-dependency-dot-file-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Emit dot files every time driver imports an experimental swiftdeps file.", group: .internal_debug)
  public static let driver_filelist_threshold_EQ: Option = Option("-driver-filelist-threshold=", .joined, alias: Option.driver_filelist_threshold)
  public static let driver_filelist_threshold: Option = Option("-driver-filelist-threshold", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Pass input or output file names as filelists if there are more than <n>", group: .internal_debug)
  public static let driver_force_response_files: Option = Option("-driver-force-response-files", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Force the use of response files for testing", group: .internal_debug)
  public static let driver_mode: Option = Option("--driver-mode=", .joined, attributes: [.helpHidden], helpText: "Set the driver mode to either 'swift' or 'swiftc'")
  public static let driver_print_actions: Option = Option("-driver-print-actions", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of actions to perform", group: .internal_debug)
  public static let driver_print_bindings: Option = Option("-driver-print-bindings", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of job inputs and outputs", group: .internal_debug)
  public static let driver_print_derived_output_file_map: Option = Option("-driver-print-derived-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the derived output file map", group: .internal_debug)
  public static let driver_print_jobs: Option = Option("-driver-print-jobs", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of jobs to execute", group: .internal_debug)
  public static let driver_print_output_file_map: Option = Option("-driver-print-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the output file map", group: .internal_debug)
  public static let driver_show_incremental: Option = Option("-driver-show-incremental", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "With -v, dump information about why files are being rebuilt", group: .internal_debug)
  public static let driver_show_job_lifecycle: Option = Option("-driver-show-job-lifecycle", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Show every step in the lifecycle of driver jobs", group: .internal_debug)
  public static let driver_skip_execution: Option = Option("-driver-skip-execution", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Skip execution of subtasks when performing compilation", group: .internal_debug)
  public static let driver_time_compilation: Option = Option("-driver-time-compilation", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Prints the total time it took to execute all compilation tasks")
  public static let driver_use_filelists: Option = Option("-driver-use-filelists", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Pass input files as filelists whenever possible", group: .internal_debug)
  public static let driver_use_frontend_path: Option = Option("-driver-use-frontend-path", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given executable to perform compilations. Arguments can be passed as a ';' separated list", group: .internal_debug)
  public static let driver_verify_experimental_dependency_graph_after_every_import: Option = Option("-driver-verify-experimental-dependency-graph-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Debug DriverGraph by verifying it after every import", group: .internal_debug)
  public static let dump_api_path: Option = Option("-dump-api-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The path to output swift interface files for the compiled source files")
  public static let dump_ast: Option = Option("-dump-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and dump AST(s)", group: .modes)
  public static let dump_clang_diagnostics: Option = Option("-dump-clang-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dump Clang diagnostics to stderr")
  public static let dump_interface_hash: Option = Option("-dump-interface-hash", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Parse input file(s) and dump interface token hash(es)", group: .modes)
  public static let dump_migration_states_dir: Option = Option("-dump-migration-states-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Dump the input text, output text, and states for migration to <path>")
  public static let dump_parse: Option = Option("-dump-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s) and dump AST(s)", group: .modes)
  public static let dump_scope_maps: Option = Option("-dump-scope-maps", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<expanded-or-list-of-line:column>", helpText: "Parse and type-check input file(s) and dump the scope map(s)", group: .modes)
  public static let dump_type_info: Option = Option("-dump-type-info", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Output YAML dump of fixed-size types from all imported modules", group: .modes)
  public static let dump_type_refinement_contexts: Option = Option("-dump-type-refinement-contexts", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Type-check input file(s) and dump type refinement contexts(s)", group: .modes)
  public static let dump_usr: Option = Option("-dump-usr", .flag, attributes: [.frontend, .noInteractive], helpText: "Dump USR for each declaration reference")
  public static let D: Option = Option("-D", .joinedOrSeparate, attributes: [.frontend], helpText: "Marks a conditional compilation flag as true")
  public static let embed_bitcode_marker: Option = Option("-embed-bitcode-marker", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed placeholder LLVM IR data as a marker")
  public static let embed_bitcode: Option = Option("-embed-bitcode", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed LLVM IR bitcode as data")
  public static let emit_assembly: Option = Option("-emit-assembly", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit assembly file(s) (-S)", group: .modes)
  public static let emit_bc: Option = Option("-emit-bc", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM BC file(s)", group: .modes)
  public static let emit_dependencies_path: Option = Option("-emit-dependencies-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output basic Make-compatible dependencies file to <path>")
  public static let emit_dependencies: Option = Option("-emit-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit basic Make-compatible dependencies files")
  public static let emit_executable: Option = Option("-emit-executable", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a linked executable", group: .modes)
  public static let emit_fixits_path: Option = Option("-emit-fixits-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output compiler fixits as source edits to <path>")
  public static let emit_imported_modules: Option = Option("-emit-imported-modules", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a list of the imported modules", group: .modes)
  public static let emit_ir: Option = Option("-emit-ir", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM IR file(s)", group: .modes)
  public static let emit_library: Option = Option("-emit-library", .flag, attributes: [.noInteractive], helpText: "Emit a linked library", group: .modes)
  public static let emit_loaded_module_trace_path_EQ: Option = Option("-emit-loaded-module-trace-path=", .joined, alias: Option.emit_loaded_module_trace_path, attributes: [.frontend, .noInteractive, .argumentIsPath])
  public static let emit_loaded_module_trace_path: Option = Option("-emit-loaded-module-trace-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Emit the loaded module trace JSON to <path>")
  public static let emit_loaded_module_trace: Option = Option("-emit-loaded-module-trace", .flag, attributes: [.frontend, .noInteractive], helpText: "Emit a JSON file containing information about what modules were loaded")
  public static let emit_migrated_file_path: Option = Option("-emit-migrated-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the migrated source file to <path>")
  public static let emit_module_doc_path: Option = Option("-emit-module-doc-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output module documentation file <path>")
  public static let emit_module_doc: Option = Option("-emit-module-doc", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a module documentation file based on documentation comments")
  public static let emit_module_interface_path: Option = Option("-emit-module-interface-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Output module interface file to <path>")
  public static let emit_module_interface: Option = Option("-emit-module-interface", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Output module interface file")
  public static let emit_module_path_EQ: Option = Option("-emit-module-path=", .joined, alias: Option.emit_module_path, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let emit_module_path: Option = Option("-emit-module-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit an importable module to <path>")
  public static let emit_module: Option = Option("-emit-module", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit an importable module")
  public static let emit_objc_header_path: Option = Option("-emit-objc-header-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit an Objective-C header file to <path>")
  public static let emit_objc_header: Option = Option("-emit-objc-header", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit an Objective-C header file")
  public static let emit_object: Option = Option("-emit-object", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit object file(s) (-c)", group: .modes)
  public static let emit_parseable_module_interface_path: Option = Option("-emit-parseable-module-interface-path", .separate, alias: Option.emit_module_interface_path, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let emit_parseable_module_interface: Option = Option("-emit-parseable-module-interface", .flag, alias: Option.emit_module_interface, attributes: [.helpHidden, .noInteractive, .doesNotAffectIncrementalBuild])
  public static let emit_pch: Option = Option("-emit-pch", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit PCH for imported Objective-C header file", group: .modes)
  public static let emit_reference_dependencies_path: Option = Option("-emit-reference-dependencies-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output Swift-style dependencies file to <path>")
  public static let emit_reference_dependencies: Option = Option("-emit-reference-dependencies", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a Swift-style dependencies file")
  public static let emit_remap_file_path: Option = Option("-emit-remap-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the replacement map describing Swift Migrator changes to <path>")
  public static let emit_sibgen: Option = Option("-emit-sibgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + raw SIL file(s)", group: .modes)
  public static let emit_sib: Option = Option("-emit-sib", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + canonical SIL file(s)", group: .modes)
  public static let emit_silgen: Option = Option("-emit-silgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit raw SIL file(s)", group: .modes)
  public static let emit_sil: Option = Option("-emit-sil", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit canonical SIL file(s)", group: .modes)
  public static let emit_sorted_sil: Option = Option("-emit-sorted-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When printing SIL, print out all sil entities sorted by name to ease diffing")
  public static let stack_promotion_checks: Option = Option("-emit-stack-promotion-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit runtime checks for correct stack promotion of objects.")
  public static let emit_syntax: Option = Option("-emit-syntax", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Parse input file(s) and emit the Syntax tree(s) as JSON", group: .modes)
  public static let emit_tbd_path_EQ: Option = Option("-emit-tbd-path=", .joined, alias: Option.emit_tbd_path, attributes: [.frontend, .noInteractive, .argumentIsPath])
  public static let emit_tbd_path: Option = Option("-emit-tbd-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Emit the TBD file to <path>")
  public static let emit_tbd: Option = Option("-emit-tbd", .flag, attributes: [.frontend, .noInteractive], helpText: "Emit a TBD file")
  public static let emit_verbose_sil: Option = Option("-emit-verbose-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit locations during SIL emission")
  public static let enable_access_control: Option = Option("-enable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Respect access control restrictions")
  public static let enable_anonymous_context_mangled_names: Option = Option("-enable-anonymous-context-mangled-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable emission of mangled names in anonymous context descriptors")
  public static let enable_astscope_lookup: Option = Option("-enable-astscope-lookup", .flag, attributes: [.frontend], helpText: "Enable ASTScope-based unqualified name lookup")
  public static let enable_batch_mode: Option = Option("-enable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Enable combining frontend jobs into batches")
  public static let enable_bridging_pch: Option = Option("-enable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Enable automatic generation of bridging PCH files")
  public static let enable_cxx_interop: Option = Option("-enable-cxx-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable C++ interop code generation and config directives")
  public static let enable_deserialization_recovery: Option = Option("-enable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Attempt to recover from missing xrefs (etc) in swiftmodules")
  public static let enable_dynamic_replacement_chaining: Option = Option("-enable-dynamic-replacement-chaining", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable chaining of dynamic replacements")
  public static let enable_experimental_dependencies: Option = Option("-enable-experimental-dependencies", .flag, attributes: [.helpHidden, .frontend], helpText: "Experimental work-in-progress to be more selective about incremental recompilation")
  public static let enable_experimental_static_assert: Option = Option("-enable-experimental-static-assert", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental #assert")
  public static let enable_function_builder_one_way_constraints: Option = Option("-enable-function-builder-one-way-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable one-way constraints in the function builder transformation")
  public static let enable_implicit_dynamic: Option = Option("-enable-implicit-dynamic", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add 'dynamic' to all declarations")
  public static let enable_infer_import_as_member: Option = Option("-enable-infer-import-as-member", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Infer when a global could be imported as a member")
  public static let enable_large_loadable_types: Option = Option("-enable-large-loadable-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable Large Loadable types IRGen pass")
  public static let enable_library_evolution: Option = Option("-enable-library-evolution", .flag, attributes: [.frontend, .moduleInterface], helpText: "Build the module to allow binary-compatible library evolution")
  public static let enable_llvm_value_names: Option = Option("-enable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add names to local values in LLVM IR")
  public static let enable_nonfrozen_enum_exhaustivity_diagnostics: Option = Option("-enable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose switches over non-frozen enums without catch-all cases")
  public static let enable_nskeyedarchiver_diagnostics: Option = Option("-enable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose classes with unstable mangled names adopting NSCoding")
  public static let enable_objc_attr_requires_foundation_module: Option = Option("-enable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable requiring uses of @objc to require importing the Foundation module")
  public static let enable_objc_interop: Option = Option("-enable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable Objective-C interop code generation and config directives")
  public static let enable_operator_designated_types: Option = Option("-enable-operator-designated-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable operator designated types")
  public static let enable_ownership_stripping_after_serialization: Option = Option("-enable-ownership-stripping-after-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Strip ownership after serialization")
  public static let enable_private_imports: Option = Option("-enable-private-imports", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal and private API to be accessed")
  public static let enable_resilience: Option = Option("-enable-resilience", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Deprecated, use -enable-library-evolution instead")
  public static let enable_sil_opaque_values: Option = Option("-enable-sil-opaque-values", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable SIL Opaque Values")
  public static let enable_source_import: Option = Option("-enable-source-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable importing of Swift source files")
  public static let enable_swift3_objc_inference: Option = Option("-enable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 3 behavior)")
  public static let enable_swiftcall: Option = Option("-enable-swiftcall", .flag, attributes: [.frontend, .noDriver], helpText: "Enable the use of LLVM swiftcall support")
  public static let enable_target_os_checking: Option = Option("-enable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking the target OS of serialized modules")
  public static let enable_testable_attr_requires_testable_module: Option = Option("-enable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking of @testable")
  public static let enable_testing: Option = Option("-enable-testing", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal API to be accessed for testing")
  public static let enable_throw_without_try: Option = Option("-enable-throw-without-try", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow throwing function calls without 'try'")
  public static let enable_verify_exclusivity: Option = Option("-enable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable verification of access markers used to enforce exclusivity.")
  public static let enforce_exclusivity_EQ: Option = Option("-enforce-exclusivity=", .joined, attributes: [.frontend, .moduleInterface], metaVar: "<enforcement>", helpText: "Enforce law of exclusivity")
  public static let experimental_dependency_include_intrafile: Option = Option("-experimental-dependency-include-intrafile", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Include within-file dependencies.", group: .internal_debug)
  public static let external_pass_pipeline_filename: Option = Option("-external-pass-pipeline-filename", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<pass_pipeline_file>", helpText: "Use the pass pipeline defined by <pass_pipeline_file>")
  public static let F_EQ: Option = Option("-F=", .joined, alias: Option.F, attributes: [.frontend, .argumentIsPath])
  public static let filelist: Option = Option("-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify source inputs in a file rather than on the command line")
  public static let fixit_all: Option = Option("-fixit-all", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Apply all fixits from diagnostics without any filtering")
  public static let force_public_linkage: Option = Option("-force-public-linkage", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force public linkage for private symbols. Used by LLDB.")
  public static let force_single_frontend_invocation: Option = Option("-force-single-frontend-invocation", .flag, alias: Option.whole_module_optimization, attributes: [.helpHidden, .frontend, .noInteractive])
  public static let framework: Option = Option("-framework", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a framework which should be linked against", group: .linker_option)
  public static let Fsystem: Option = Option("-Fsystem", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to system framework search path")
  public static let F: Option = Option("-F", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to framework search path")
  public static let gdwarf_types: Option = Option("-gdwarf-types", .flag, attributes: [.frontend], helpText: "Emit full DWARF type info.", group: .g)
  public static let gline_tables_only: Option = Option("-gline-tables-only", .flag, attributes: [.frontend], helpText: "Emit minimal debug info for backtraces only", group: .g)
  public static let gnone: Option = Option("-gnone", .flag, attributes: [.frontend], helpText: "Don't emit debug info", group: .g)
  public static let group_info_path: Option = Option("-group-info-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The path to collect the group information of the compiled module")
  public static let debug_on_sil: Option = Option("-gsil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Write the SIL into a file and generate debug-info to debug on SIL  level.")
  public static let g: Option = Option("-g", .flag, attributes: [.frontend], helpText: "Emit debug info. This is the preferred setting for debugging with LLDB.", group: .g)
  public static let help_hidden: Option = Option("-help-hidden", .flag, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options")
  public static let help_hidden_: Option = Option("--help-hidden", .flag, alias: Option.help_hidden, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options")
  public static let help: Option = Option("-help", .flag, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options")
  public static let help_: Option = Option("--help", .flag, alias: Option.help, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options")
  public static let h: Option = Option("-h", .flag, alias: Option.help)
  public static let I_EQ: Option = Option("-I=", .joined, alias: Option.I, attributes: [.frontend, .argumentIsPath])
  public static let import_cf_types: Option = Option("-import-cf-types", .flag, attributes: [.helpHidden, .frontend], helpText: "Recognize and import CF types as class types")
  public static let import_module: Option = Option("-import-module", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Implicitly import the specified module")
  public static let import_objc_header: Option = Option("-import-objc-header", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Implicitly imports an Objective-C header file")
  public static let import_underlying_module: Option = Option("-import-underlying-module", .flag, attributes: [.frontend, .noInteractive], helpText: "Implicitly imports the Objective-C half of a module")
  public static let in_place: Option = Option("-in-place", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Overwrite input file with formatted file.", group: .code_formatting)
  public static let incremental: Option = Option("-incremental", .flag, attributes: [.helpHidden, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Perform an incremental build if possible")
  public static let indent_switch_case: Option = Option("-indent-switch-case", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Indent cases in switch statements.", group: .code_formatting)
  public static let indent_width: Option = Option("-indent-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Number of characters to indent.", group: .code_formatting)
  public static let index_file_path: Option = Option("-index-file-path", .separate, attributes: [.noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Produce index data for file <path>")
  public static let index_file: Option = Option("-index-file", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Produce index data for a source file", group: .modes)
  public static let index_ignore_system_modules: Option = Option("-index-ignore-system-modules", .flag, attributes: [.noInteractive], helpText: "Avoid indexing system modules")
  public static let index_store_path: Option = Option("-index-store-path", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<path>", helpText: "Store indexing data to <path>")
  public static let index_system_modules: Option = Option("-index-system-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit index data for imported serialized swift system modules")
  public static let interpret: Option = Option("-interpret", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Immediate mode", group: .modes)
  public static let I: Option = Option("-I", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to the import search path")
  public static let i: Option = Option("-i", .flag, group: .modes)
  public static let j: Option = Option("-j", .joinedOrSeparate, attributes: [.doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Number of commands to execute in parallel")
  public static let L_EQ: Option = Option("-L=", .joined, alias: Option.L, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let lazy_astscopes: Option = Option("-lazy-astscopes", .flag, attributes: [.frontend, .noDriver], helpText: "Build ASTScopes lazily")
  public static let libc: Option = Option("-libc", .separate, helpText: "libc runtime library to use")
  public static let line_range: Option = Option("-line-range", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n:n>", helpText: "<start line>:<end line>. Formats a range of lines (1-based). Can only be used with one input file.", group: .code_formatting)
  public static let link_objc_runtime: Option = Option("-link-objc-runtime", .flag, attributes: [.doesNotAffectIncrementalBuild])
  public static let lldb_repl: Option = Option("-lldb-repl", .flag, attributes: [.helpHidden, .noBatch], helpText: "LLDB-enhanced REPL mode", group: .modes)
  public static let L: Option = Option("-L", .joinedOrSeparate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Add directory to library link search path", group: .linker_option)
  public static let l: Option = Option("-l", .joined, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a library which should be linked against", group: .linker_option)
  public static let merge_modules: Option = Option("-merge-modules", .flag, attributes: [.frontend, .noDriver], helpText: "Merge the input modules without otherwise processing them", group: .modes)
  public static let migrate_keep_objc_visibility: Option = Option("-migrate-keep-objc-visibility", .flag, attributes: [.frontend, .noInteractive], helpText: "When migrating, add '@objc' to declarations that would've been implicitly visible in Swift 3")
  public static let migrator_update_sdk: Option = Option("-migrator-update-sdk", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.")
  public static let migrator_update_swift: Option = Option("-migrator-update-swift", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.")
  public static let module_cache_path: Option = Option("-module-cache-path", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Specifies the Clang module cache path")
  public static let module_interface_preserve_types_as_written: Option = Option("-module-interface-preserve-types-as-written", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface, preserve types as they were written in the source")
  public static let module_link_name_EQ: Option = Option("-module-link-name=", .joined, alias: Option.module_link_name, attributes: [.frontend])
  public static let module_link_name: Option = Option("-module-link-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Library to link against when using this module")
  public static let module_name_EQ: Option = Option("-module-name=", .joined, alias: Option.module_name, attributes: [.frontend])
  public static let module_name: Option = Option("-module-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Name of the module to build")
  public static let no_clang_module_breadcrumbs: Option = Option("-no-clang-module-breadcrumbs", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't emit DWARF skeleton CUs for imported Clang modules. Use this when building a redistributable static archive.")
  public static let no_color_diagnostics: Option = Option("-no-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Do not print diagnostics in color")
  public static let no_link_objc_runtime: Option = Option("-no-link-objc-runtime", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't link in additions to the Objective-C runtime")
  public static let no_serialize_debugging_options: Option = Option("-no-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Never serialize options for debugging (default: only for apps)")
  public static let no_static_executable: Option = Option("-no-static-executable", .flag, attributes: [.helpHidden], helpText: "Don't statically link the executable")
  public static let no_static_stdlib: Option = Option("-no-static-stdlib", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't statically link the Swift standard library")
  public static let no_stdlib_rpath: Option = Option("-no-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't add any rpath entries.")
  public static let no_toolchain_stdlib_rpath: Option = Option("-no-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Do not add an rpath entry for the toolchain's standard library (default)")
  public static let nostdimport: Option = Option("-nostdimport", .flag, attributes: [.frontend], helpText: "Don't search the standard library import path for modules")
  public static let num_threads: Option = Option("-num-threads", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Enable multi-threading and specify number of threads")
  public static let Onone: Option = Option("-Onone", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile without any optimization", group: .O)
  public static let Oplayground: Option = Option("-Oplayground", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Compile with optimizations appropriate for a playground", group: .O)
  public static let Osize: Option = Option("-Osize", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and target small code size", group: .O)
  public static let Ounchecked: Option = Option("-Ounchecked", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and remove runtime safety checks", group: .O)
  public static let output_file_map_EQ: Option = Option("-output-file-map=", .joined, alias: Option.output_file_map, attributes: [.noInteractive, .argumentIsPath])
  public static let output_file_map: Option = Option("-output-file-map", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "A file which specifies the location of outputs")
  public static let output_filelist: Option = Option("-output-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify outputs in a file rather than on the command line")
  public static let output_request_graphviz: Option = Option("-output-request-graphviz", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit GraphViz output visualizing the request graph")
  public static let O: Option = Option("-O", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations", group: .O)
  public static let o: Option = Option("-o", .joinedOrSeparate, attributes: [.frontend, .noInteractive, .autolinkExtract, .moduleWrap, .indent, .argumentIsPath], metaVar: "<file>", helpText: "Write output to <file>")
  public static let package_description_version: Option = Option("-package-description-version", .separate, attributes: [.helpHidden, .frontend, .moduleInterface], metaVar: "<vers>", helpText: "The version number to be applied on the input for the PackageDescription availability kind")
  public static let parse_as_library: Option = Option("-parse-as-library", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file(s) as libraries, not scripts")
  public static let parse_sil: Option = Option("-parse-sil", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file as SIL code, not Swift source")
  public static let parse_stdlib: Option = Option("-parse-stdlib", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Parse the input file(s) as the Swift standard library")
  public static let parseable_output: Option = Option("-parseable-output", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit textual output in a parseable format")
  public static let parse: Option = Option("-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s)", group: .modes)
  public static let pc_macro: Option = Option("-pc-macro", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the 'program counter simulation' macro")
  public static let pch_disable_validation: Option = Option("-pch-disable-validation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating the persistent PCH")
  public static let pch_output_dir: Option = Option("-pch-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to persist automatically created precompiled bridging headers")
  public static let playground_high_performance: Option = Option("-playground-high-performance", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Omit instrumentation that has a high runtime performance impact")
  public static let playground: Option = Option("-playground", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the playground semantics and transformation")
  public static let prebuilt_module_cache_path_EQ: Option = Option("-prebuilt-module-cache-path=", .joined, alias: Option.prebuilt_module_cache_path, attributes: [.helpHidden, .frontend, .noDriver])
  public static let prebuilt_module_cache_path: Option = Option("-prebuilt-module-cache-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Directory of prebuilt modules for loading module interfaces")
  public static let primary_filelist: Option = Option("-primary-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify primary inputs in a file rather than on the command line")
  public static let primary_file: Option = Option("-primary-file", .separate, attributes: [.frontend, .noDriver], helpText: "Produce output for this file, not the whole module")
  public static let print_ast: Option = Option("-print-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and pretty print AST(s)", group: .modes)
  public static let print_clang_stats: Option = Option("-print-clang-stats", .flag, attributes: [.frontend, .noDriver], helpText: "Print Clang importer statistics")
  public static let print_inst_counts: Option = Option("-print-inst-counts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Before IRGen, count all the various SIL instructions. Must be used in conjunction with -print-stats.")
  public static let print_llvm_inline_tree: Option = Option("-print-llvm-inline-tree", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print the LLVM inline tree.")
  public static let print_stats: Option = Option("-print-stats", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print various statistics")
  public static let profile_coverage_mapping: Option = Option("-profile-coverage-mapping", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate coverage data for use with profiled execution counts")
  public static let profile_generate: Option = Option("-profile-generate", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate instrumented code to collect execution counts")
  public static let profile_stats_entities: Option = Option("-profile-stats-entities", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir, subdivided by source entity")
  public static let profile_stats_events: Option = Option("-profile-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir")
  public static let profile_use: Option = Option("-profile-use=", .commaJoined, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<profdata>", helpText: "Supply a profdata file to enable profile-guided optimization")
  public static let read_legacy_type_info_path_EQ: Option = Option("-read-legacy-type-info-path=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Read legacy type layout from the given path instead of default path")
  public static let RemoveRuntimeAsserts: Option = Option("-remove-runtime-asserts", .flag, attributes: [.frontend], helpText: "Remove runtime safety checks.")
  public static let repl: Option = Option("-repl", .flag, attributes: [.helpHidden, .frontend, .noBatch], helpText: "REPL mode (the default if there is no input file)", group: .modes)
  public static let report_errors_to_debugger: Option = Option("-report-errors-to-debugger", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, will be removed in future versions.")
  public static let require_explicit_availability_target: Option = Option("-require-explicit-availability-target", .separate, attributes: [.frontend, .noInteractive], metaVar: "<target>", helpText: "Suggest fix-its adding @available(<target>, *) to public declarations without availability")
  public static let require_explicit_availability: Option = Option("-require-explicit-availability", .flag, attributes: [.frontend, .noInteractive], helpText: "Require explicit availability on public declarations")
  public static let resolve_imports: Option = Option("-resolve-imports", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and resolve imports in input file(s)", group: .modes)
  public static let resource_dir: Option = Option("-resource-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], metaVar: "</usr/lib/swift>", helpText: "The directory that holds the compiler resource files")
  public static let Rmodule_interface_rebuild: Option = Option("-Rmodule-interface-rebuild", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emits a remark if an imported module needs to be re-compiled from its module interface")
  public static let Rpass_missed_EQ: Option = Option("-Rpass-missed=", .joined, attributes: [.frontend], helpText: "Report missed transformations by optimization passes whose name matches the given POSIX regular expression")
  public static let Rpass_EQ: Option = Option("-Rpass=", .joined, attributes: [.frontend], helpText: "Report performed transformations by optimization passes whose name matches the given POSIX regular expression")
  public static let runtime_compatibility_version: Option = Option("-runtime-compatibility-version", .separate, attributes: [.frontend], helpText: "Link compatibility library for Swift runtime version, or 'none'")
  public static let sanitize_coverage_EQ: Option = Option("-sanitize-coverage=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<type>", helpText: "Specify the type of coverage instrumentation for Sanitizers and additional options separated by commas")
  public static let sanitize_EQ: Option = Option("-sanitize=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<check>", helpText: "Turn on runtime checks for erroneous behavior.")
  public static let save_optimization_record_path: Option = Option("-save-optimization-record-path", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Specify the file name of any generated YAML optimization record")
  public static let save_optimization_record: Option = Option("-save-optimization-record", .flag, attributes: [.frontend], helpText: "Generate a YAML optimization record file")
  public static let save_temps: Option = Option("-save-temps", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Save intermediate compilation results")
  public static let sdk: Option = Option("-sdk", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<sdk>", helpText: "Compile against <sdk>")
  public static let serialize_debugging_options: Option = Option("-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Always serialize options for debugging (default: only for apps)")
  public static let serialize_diagnostics_path_EQ: Option = Option("-serialize-diagnostics-path=", .joined, alias: Option.serialize_diagnostics_path, attributes: [.frontend, .noBatch, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let serialize_diagnostics_path: Option = Option("-serialize-diagnostics-path", .separate, attributes: [.frontend, .noBatch, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit a serialized diagnostics file to <path>")
  public static let serialize_diagnostics: Option = Option("-serialize-diagnostics", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Serialize diagnostics in a binary format")
  public static let serialize_module_interface_dependency_hashes: Option = Option("-serialize-module-interface-dependency-hashes", .flag, attributes: [.frontend, .noDriver])
  public static let serialize_parseable_module_interface_dependency_hashes: Option = Option("-serialize-parseable-module-interface-dependency-hashes", .flag, alias: Option.serialize_module_interface_dependency_hashes, attributes: [.frontend, .noDriver])
  public static let show_diagnostics_after_fatal: Option = Option("-show-diagnostics-after-fatal", .flag, attributes: [.frontend, .noDriver], helpText: "Keep emitting subsequent diagnostics after a fatal error")
  public static let sil_debug_serialization: Option = Option("-sil-debug-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not eliminate functions in Mandatory Inlining/SILCombine dead functions. (for debugging only)")
  public static let sil_inline_caller_benefit_reduction_factor: Option = Option("-sil-inline-caller-benefit-reduction-factor", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<2>", helpText: "Controls the aggressiveness of performance inlining in -Osize mode by reducing the base benefits of a caller (lower value permits more inlining!)")
  public static let sil_inline_threshold: Option = Option("-sil-inline-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<50>", helpText: "Controls the aggressiveness of performance inlining")
  public static let sil_merge_partial_modules: Option = Option("-sil-merge-partial-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Merge SIL from all partial swiftmodules into the final module")
  public static let sil_unroll_threshold: Option = Option("-sil-unroll-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<250>", helpText: "Controls the aggressiveness of loop unrolling")
  public static let sil_verify_all: Option = Option("-sil-verify-all", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Verify SIL after each transform")
  public static let solver_disable_shrink: Option = Option("-solver-disable-shrink", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the shrink phase of expression type checking")
  public static let solver_enable_operator_designated_types: Option = Option("-solver-enable-operator-designated-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable operator designated types in constraint solver")
  public static let solver_expression_time_threshold_EQ: Option = Option("-solver-expression-time-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver])
  public static let solver_memory_threshold: Option = Option("-solver-memory-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the upper bound for memory consumption, in bytes, by the constraint solver")
  public static let solver_shrink_unsolved_threshold: Option = Option("-solver-shrink-unsolved-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set The upper bound to number of sub-expressions unsolved before termination of the shrink phrase")
  public static let stack_promotion_limit: Option = Option("-stack-promotion-limit", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Limit the size of stack promoted objects to the provided number of bytes.")
  public static let static_executable: Option = Option("-static-executable", .flag, helpText: "Statically link the executable")
  public static let static_stdlib: Option = Option("-static-stdlib", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Statically link the Swift standard library")
  public static let `static`: Option = Option("-static", .flag, attributes: [.frontend, .noInteractive, .moduleInterface], helpText: "Make this module statically linkable and make the output of -emit-library a static library.")
  public static let stats_output_dir: Option = Option("-stats-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to write unified compilation-statistics files to")
  public static let stress_astscope_lookup: Option = Option("-stress-astscope-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Stress ASTScope-based unqualified name lookup (for testing)")
  public static let supplementary_output_file_map: Option = Option("-supplementary-output-file-map", .separate, attributes: [.frontend, .noDriver], helpText: "Specify supplementary outputs in a file rather than on the command line")
  public static let suppress_static_exclusivity_swap: Option = Option("-suppress-static-exclusivity-swap", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Suppress static violations of exclusive access with swap()")
  public static let suppress_warnings: Option = Option("-suppress-warnings", .flag, attributes: [.frontend], helpText: "Suppress all warnings")
  public static let swift_version: Option = Option("-swift-version", .separate, attributes: [.frontend, .moduleInterface], metaVar: "<vers>", helpText: "Interpret input according to a specific Swift language version number")
  public static let switch_checking_invocation_threshold_EQ: Option = Option("-switch-checking-invocation-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver])
  public static let S: Option = Option("-S", .flag, alias: Option.emit_assembly, attributes: [.frontend, .noInteractive], group: .modes)
  public static let tab_width: Option = Option("-tab-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Width of tab character.", group: .code_formatting)
  public static let target_cpu: Option = Option("-target-cpu", .separate, attributes: [.frontend, .moduleInterface], helpText: "Generate code for a particular CPU variant")
  public static let target_legacy_spelling: Option = Option("--target=", .joined, alias: Option.target, attributes: [.frontend])
  public static let target: Option = Option("-target", .separate, attributes: [.frontend, .moduleWrap, .moduleInterface], metaVar: "<triple>", helpText: "Generate code for the given target <triple>, such as x86_64-apple-macos10.9")
  public static let tbd_compatibility_version_EQ: Option = Option("-tbd-compatibility-version=", .joined, alias: Option.tbd_compatibility_version, attributes: [.frontend, .noDriver])
  public static let tbd_compatibility_version: Option = Option("-tbd-compatibility-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The compatibility_version to use in an emitted TBD file")
  public static let tbd_current_version_EQ: Option = Option("-tbd-current-version=", .joined, alias: Option.tbd_current_version, attributes: [.frontend, .noDriver])
  public static let tbd_current_version: Option = Option("-tbd-current-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The current_version to use in an emitted TBD file")
  public static let tbd_install_name_EQ: Option = Option("-tbd-install_name=", .joined, alias: Option.tbd_install_name, attributes: [.frontend, .noDriver])
  public static let tbd_install_name: Option = Option("-tbd-install_name", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "The install_name to use in an emitted TBD file")
  public static let toolchain_stdlib_rpath: Option = Option("-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Add an rpath entry for the toolchain's standard library, rather than the OS's")
  public static let tools_directory: Option = Option("-tools-directory", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<directory>", helpText: "Look for external executables (ld, clang, binutils) in <directory>")
  public static let trace_stats_events: Option = Option("-trace-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Trace changes to stats in -stats-output-dir")
  public static let track_system_dependencies: Option = Option("-track-system-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Track system dependencies while emitting Make-style dependencies")
  public static let triple: Option = Option("-triple", .separate, alias: Option.target, attributes: [.frontend, .noDriver])
  public static let type_info_dump_filter_EQ: Option = Option("-type-info-dump-filter=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "One of 'all', 'resilient' or 'fragile'")
  public static let typecheck: Option = Option("-typecheck", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s)", group: .modes)
  public static let typo_correction_limit: Option = Option("-typo-correction-limit", .separate, attributes: [.helpHidden, .frontend], metaVar: "<n>", helpText: "Limit the number of times the compiler will attempt typo correction to <n>")
  public static let update_code: Option = Option("-update-code", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Update Swift code")
  public static let use_jit: Option = Option("-use-jit", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Register Objective-C classes as if the JIT were in use")
  public static let use_ld: Option = Option("-use-ld=", .joined, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies the linker to be used")
  public static let use_malloc: Option = Option("-use-malloc", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allocate internal data structures using malloc (for memory debugging)")
  public static let use_tabs: Option = Option("-use-tabs", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Use tabs for indentation.", group: .code_formatting)
  public static let validate_tbd_against_ir_EQ: Option = Option("-validate-tbd-against-ir=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<level>", helpText: "Compare the symbols in the IR against the TBD file that would be generated.")
  public static let value_recursion_threshold: Option = Option("-value-recursion-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the maximum depth for direct recursion in value types")
  public static let verify_apply_fixes: Option = Option("-verify-apply-fixes", .flag, attributes: [.frontend, .noDriver], helpText: "Like -verify, but updates the original source file")
  public static let verify_debug_info: Option = Option("-verify-debug-info", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Verify the binary representation of debug output.")
  public static let verify_generic_signatures: Option = Option("-verify-generic-signatures", .separate, attributes: [.frontend, .noDriver], metaVar: "<module-name>", helpText: "Verify the generic signatures in the given module")
  public static let verify_ignore_unknown: Option = Option("-verify-ignore-unknown", .flag, attributes: [.frontend, .noDriver], helpText: "Allow diagnostics for '<unknown>' location in verify mode")
  public static let verify_syntax_tree: Option = Option("-verify-syntax-tree", .flag, attributes: [.frontend, .noDriver], helpText: "Verify that no unknown nodes exist in the libSyntax tree")
  public static let verify_type_layout: Option = Option("-verify-type-layout", .joinedOrSeparate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<type>", helpText: "Verify compile-time and runtime type layout information for type")
  public static let verify: Option = Option("-verify", .flag, attributes: [.frontend, .noDriver], helpText: "Verify diagnostics against expected-{error|warning|note} annotations")
  public static let version: Option = Option("-version", .flag, helpText: "Print version information and exit")
  public static let version_: Option = Option("--version", .flag, alias: Option.version, helpText: "Print version information and exit")
  public static let vfsoverlay_EQ: Option = Option("-vfsoverlay=", .joined, alias: Option.vfsoverlay)
  public static let vfsoverlay: Option = Option("-vfsoverlay", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to VFS overlay file")
  public static let v: Option = Option("-v", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Show commands to run and use verbose output")
  public static let warn_if_astscope_lookup: Option = Option("-warn-if-astscope-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Print a warning if ASTScope lookup is used")
  public static let warn_implicit_overrides: Option = Option("-warn-implicit-overrides", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about implicit overrides of protocol members")
  public static let warn_long_expression_type_checking_EQ: Option = Option("-warn-long-expression-type-checking=", .joined, alias: Option.warn_long_expression_type_checking, attributes: [.helpHidden, .frontend, .noDriver])
  public static let warn_long_expression_type_checking: Option = Option("-warn-long-expression-type-checking", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms")
  public static let warn_long_function_bodies_EQ: Option = Option("-warn-long-function-bodies=", .joined, alias: Option.warn_long_function_bodies, attributes: [.helpHidden, .frontend, .noDriver])
  public static let warn_long_function_bodies: Option = Option("-warn-long-function-bodies", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms")
  public static let warn_swift3_objc_inference_complete: Option = Option("-warn-swift3-objc-inference-complete", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about deprecated @objc inference in Swift 3 for every declaration that will no longer be inferred as @objc in Swift 4")
  public static let warn_swift3_objc_inference_minimal: Option = Option("-warn-swift3-objc-inference-minimal", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about deprecated @objc inference in Swift 3 based on direct uses of the Objective-C entrypoint")
  public static let warn_swift3_objc_inference: Option = Option("-warn-swift3-objc-inference", .flag, alias: Option.warn_swift3_objc_inference_complete, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild])
  public static let warnings_as_errors: Option = Option("-warnings-as-errors", .flag, attributes: [.frontend], helpText: "Treat warnings as errors")
  public static let whole_module_optimization: Option = Option("-whole-module-optimization", .flag, attributes: [.frontend, .noInteractive], helpText: "Optimize input files together instead of individually")
  public static let wmo: Option = Option("-wmo", .flag, alias: Option.whole_module_optimization, attributes: [.helpHidden, .frontend, .noInteractive])
  public static let working_directory_EQ: Option = Option("-working-directory=", .joined, alias: Option.working_directory)
  public static let working_directory: Option = Option("-working-directory", .separate, metaVar: "<path>", helpText: "Resolve file paths relative to the specified directory")
  public static let Xcc: Option = Option("-Xcc", .separate, attributes: [.frontend], metaVar: "<arg>", helpText: "Pass <arg> to the C/C++/Objective-C compiler")
  public static let Xclang_linker: Option = Option("-Xclang-linker", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to Clang when it is use for linking.")
  public static let Xfrontend: Option = Option("-Xfrontend", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to the Swift frontend")
  public static let Xlinker: Option = Option("-Xlinker", .separate, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies an option which should be passed to the linker")
  public static let Xllvm: Option = Option("-Xllvm", .separate, attributes: [.helpHidden, .frontend], metaVar: "<arg>", helpText: "Pass <arg> to LLVM.")
  public static let _DASH_DASH: Option = Option("--", .remaining, attributes: [.frontend, .doesNotAffectIncrementalBuild])
}

extension Option {
  public static var allOptions: [Option] {
    return [
      Option.INPUT,
      Option._HASH_HASH_HASH,
      Option.api_diff_data_dir,
      Option.api_diff_data_file,
      Option.enable_app_extension,
      Option.AssertConfig,
      Option.AssumeSingleThreaded,
      Option.autolink_force_load,
      Option.autolink_library,
      Option.build_module_from_parseable_interface,
      Option.bypass_batch_mode_checks,
      Option.check_onone_completeness,
      Option.code_complete_call_pattern_heuristics,
      Option.code_complete_inits_in_postfix_expr,
      Option.color_diagnostics,
      Option.compile_module_from_interface,
      Option.continue_building_after_errors,
      Option.crosscheck_unqualified_lookup,
      Option.c,
      Option.debug_assert_after_parse,
      Option.debug_assert_immediately,
      Option.debug_constraints_attempt,
      Option.debug_constraints_on_line_EQ,
      Option.debug_constraints_on_line,
      Option.debug_constraints,
      Option.debug_crash_after_parse,
      Option.debug_crash_immediately,
      Option.debug_cycles,
      Option.debug_diagnostic_names,
      Option.debug_forbid_typecheck_prefix,
      Option.debug_generic_signatures,
      Option.debug_info_format,
      Option.debug_info_store_invocation,
      Option.debug_prefix_map,
      Option.debug_time_compilation,
      Option.debug_time_expression_type_checking,
      Option.debug_time_function_bodies,
      Option.debugger_support,
      Option.debugger_testing_transform,
      Option.deprecated_integrated_repl,
      Option.diagnostics_editor_mode,
      Option.disable_access_control,
      Option.disable_arc_opts,
      Option.disable_astscope_lookup,
      Option.disable_autolink_framework,
      Option.disable_autolinking_runtime_compatibility_dynamic_replacements,
      Option.disable_autolinking_runtime_compatibility,
      Option.disable_availability_checking,
      Option.disable_batch_mode,
      Option.disable_bridging_pch,
      Option.disable_constraint_solver_performance_hacks,
      Option.disable_deserialization_recovery,
      Option.disable_diagnostic_passes,
      Option.disable_function_builder_one_way_constraints,
      Option.disable_incremental_llvm_codegeneration,
      Option.disable_legacy_type_info,
      Option.disable_llvm_optzns,
      Option.disable_llvm_slp_vectorizer,
      Option.disable_llvm_value_names,
      Option.disable_llvm_verify,
      Option.disable_migrator_fixits,
      Option.disable_modules_validate_system_headers,
      Option.disable_named_lazy_member_loading,
      Option.disable_nonfrozen_enum_exhaustivity_diagnostics,
      Option.disable_nskeyedarchiver_diagnostics,
      Option.disable_objc_attr_requires_foundation_module,
      Option.disable_objc_interop,
      Option.disable_parser_lookup,
      Option.disable_playground_transform,
      Option.disable_previous_implementation_calls_in_dynamic_replacements,
      Option.disable_reflection_metadata,
      Option.disable_reflection_names,
      Option.disable_serialization_nested_type_lookup_table,
      Option.disable_sil_ownership_verifier,
      Option.disable_sil_partial_apply,
      Option.disable_sil_perf_optzns,
      Option.disable_swift_bridge_attr,
      Option.disable_swift_specific_llvm_optzns,
      Option.disable_swift3_objc_inference,
      Option.disable_target_os_checking,
      Option.disable_testable_attr_requires_testable_module,
      Option.disable_tsan_inout_instrumentation,
      Option.disable_typo_correction,
      Option.disable_verify_exclusivity,
      Option.driver_always_rebuild_dependents,
      Option.driver_batch_count,
      Option.driver_batch_seed,
      Option.driver_batch_size_limit,
      Option.driver_emit_experimental_dependency_dot_file_after_every_import,
      Option.driver_filelist_threshold_EQ,
      Option.driver_filelist_threshold,
      Option.driver_force_response_files,
      Option.driver_mode,
      Option.driver_print_actions,
      Option.driver_print_bindings,
      Option.driver_print_derived_output_file_map,
      Option.driver_print_jobs,
      Option.driver_print_output_file_map,
      Option.driver_show_incremental,
      Option.driver_show_job_lifecycle,
      Option.driver_skip_execution,
      Option.driver_time_compilation,
      Option.driver_use_filelists,
      Option.driver_use_frontend_path,
      Option.driver_verify_experimental_dependency_graph_after_every_import,
      Option.dump_api_path,
      Option.dump_ast,
      Option.dump_clang_diagnostics,
      Option.dump_interface_hash,
      Option.dump_migration_states_dir,
      Option.dump_parse,
      Option.dump_scope_maps,
      Option.dump_type_info,
      Option.dump_type_refinement_contexts,
      Option.dump_usr,
      Option.D,
      Option.embed_bitcode_marker,
      Option.embed_bitcode,
      Option.emit_assembly,
      Option.emit_bc,
      Option.emit_dependencies_path,
      Option.emit_dependencies,
      Option.emit_executable,
      Option.emit_fixits_path,
      Option.emit_imported_modules,
      Option.emit_ir,
      Option.emit_library,
      Option.emit_loaded_module_trace_path_EQ,
      Option.emit_loaded_module_trace_path,
      Option.emit_loaded_module_trace,
      Option.emit_migrated_file_path,
      Option.emit_module_doc_path,
      Option.emit_module_doc,
      Option.emit_module_interface_path,
      Option.emit_module_interface,
      Option.emit_module_path_EQ,
      Option.emit_module_path,
      Option.emit_module,
      Option.emit_objc_header_path,
      Option.emit_objc_header,
      Option.emit_object,
      Option.emit_parseable_module_interface_path,
      Option.emit_parseable_module_interface,
      Option.emit_pch,
      Option.emit_reference_dependencies_path,
      Option.emit_reference_dependencies,
      Option.emit_remap_file_path,
      Option.emit_sibgen,
      Option.emit_sib,
      Option.emit_silgen,
      Option.emit_sil,
      Option.emit_sorted_sil,
      Option.stack_promotion_checks,
      Option.emit_syntax,
      Option.emit_tbd_path_EQ,
      Option.emit_tbd_path,
      Option.emit_tbd,
      Option.emit_verbose_sil,
      Option.enable_access_control,
      Option.enable_anonymous_context_mangled_names,
      Option.enable_astscope_lookup,
      Option.enable_batch_mode,
      Option.enable_bridging_pch,
      Option.enable_cxx_interop,
      Option.enable_deserialization_recovery,
      Option.enable_dynamic_replacement_chaining,
      Option.enable_experimental_dependencies,
      Option.enable_experimental_static_assert,
      Option.enable_function_builder_one_way_constraints,
      Option.enable_implicit_dynamic,
      Option.enable_infer_import_as_member,
      Option.enable_large_loadable_types,
      Option.enable_library_evolution,
      Option.enable_llvm_value_names,
      Option.enable_nonfrozen_enum_exhaustivity_diagnostics,
      Option.enable_nskeyedarchiver_diagnostics,
      Option.enable_objc_attr_requires_foundation_module,
      Option.enable_objc_interop,
      Option.enable_operator_designated_types,
      Option.enable_ownership_stripping_after_serialization,
      Option.enable_private_imports,
      Option.enable_resilience,
      Option.enable_sil_opaque_values,
      Option.enable_source_import,
      Option.enable_swift3_objc_inference,
      Option.enable_swiftcall,
      Option.enable_target_os_checking,
      Option.enable_testable_attr_requires_testable_module,
      Option.enable_testing,
      Option.enable_throw_without_try,
      Option.enable_verify_exclusivity,
      Option.enforce_exclusivity_EQ,
      Option.experimental_dependency_include_intrafile,
      Option.external_pass_pipeline_filename,
      Option.F_EQ,
      Option.filelist,
      Option.fixit_all,
      Option.force_public_linkage,
      Option.force_single_frontend_invocation,
      Option.framework,
      Option.Fsystem,
      Option.F,
      Option.gdwarf_types,
      Option.gline_tables_only,
      Option.gnone,
      Option.group_info_path,
      Option.debug_on_sil,
      Option.g,
      Option.help_hidden,
      Option.help_hidden_,
      Option.help,
      Option.help_,
      Option.h,
      Option.I_EQ,
      Option.import_cf_types,
      Option.import_module,
      Option.import_objc_header,
      Option.import_underlying_module,
      Option.in_place,
      Option.incremental,
      Option.indent_switch_case,
      Option.indent_width,
      Option.index_file_path,
      Option.index_file,
      Option.index_ignore_system_modules,
      Option.index_store_path,
      Option.index_system_modules,
      Option.interpret,
      Option.I,
      Option.i,
      Option.j,
      Option.L_EQ,
      Option.lazy_astscopes,
      Option.libc,
      Option.line_range,
      Option.link_objc_runtime,
      Option.lldb_repl,
      Option.L,
      Option.l,
      Option.merge_modules,
      Option.migrate_keep_objc_visibility,
      Option.migrator_update_sdk,
      Option.migrator_update_swift,
      Option.module_cache_path,
      Option.module_interface_preserve_types_as_written,
      Option.module_link_name_EQ,
      Option.module_link_name,
      Option.module_name_EQ,
      Option.module_name,
      Option.no_clang_module_breadcrumbs,
      Option.no_color_diagnostics,
      Option.no_link_objc_runtime,
      Option.no_serialize_debugging_options,
      Option.no_static_executable,
      Option.no_static_stdlib,
      Option.no_stdlib_rpath,
      Option.no_toolchain_stdlib_rpath,
      Option.nostdimport,
      Option.num_threads,
      Option.Onone,
      Option.Oplayground,
      Option.Osize,
      Option.Ounchecked,
      Option.output_file_map_EQ,
      Option.output_file_map,
      Option.output_filelist,
      Option.output_request_graphviz,
      Option.O,
      Option.o,
      Option.package_description_version,
      Option.parse_as_library,
      Option.parse_sil,
      Option.parse_stdlib,
      Option.parseable_output,
      Option.parse,
      Option.pc_macro,
      Option.pch_disable_validation,
      Option.pch_output_dir,
      Option.playground_high_performance,
      Option.playground,
      Option.prebuilt_module_cache_path_EQ,
      Option.prebuilt_module_cache_path,
      Option.primary_filelist,
      Option.primary_file,
      Option.print_ast,
      Option.print_clang_stats,
      Option.print_inst_counts,
      Option.print_llvm_inline_tree,
      Option.print_stats,
      Option.profile_coverage_mapping,
      Option.profile_generate,
      Option.profile_stats_entities,
      Option.profile_stats_events,
      Option.profile_use,
      Option.read_legacy_type_info_path_EQ,
      Option.RemoveRuntimeAsserts,
      Option.repl,
      Option.report_errors_to_debugger,
      Option.require_explicit_availability_target,
      Option.require_explicit_availability,
      Option.resolve_imports,
      Option.resource_dir,
      Option.Rmodule_interface_rebuild,
      Option.Rpass_missed_EQ,
      Option.Rpass_EQ,
      Option.runtime_compatibility_version,
      Option.sanitize_coverage_EQ,
      Option.sanitize_EQ,
      Option.save_optimization_record_path,
      Option.save_optimization_record,
      Option.save_temps,
      Option.sdk,
      Option.serialize_debugging_options,
      Option.serialize_diagnostics_path_EQ,
      Option.serialize_diagnostics_path,
      Option.serialize_diagnostics,
      Option.serialize_module_interface_dependency_hashes,
      Option.serialize_parseable_module_interface_dependency_hashes,
      Option.show_diagnostics_after_fatal,
      Option.sil_debug_serialization,
      Option.sil_inline_caller_benefit_reduction_factor,
      Option.sil_inline_threshold,
      Option.sil_merge_partial_modules,
      Option.sil_unroll_threshold,
      Option.sil_verify_all,
      Option.solver_disable_shrink,
      Option.solver_enable_operator_designated_types,
      Option.solver_expression_time_threshold_EQ,
      Option.solver_memory_threshold,
      Option.solver_shrink_unsolved_threshold,
      Option.stack_promotion_limit,
      Option.static_executable,
      Option.static_stdlib,
      Option.static,
      Option.stats_output_dir,
      Option.stress_astscope_lookup,
      Option.supplementary_output_file_map,
      Option.suppress_static_exclusivity_swap,
      Option.suppress_warnings,
      Option.swift_version,
      Option.switch_checking_invocation_threshold_EQ,
      Option.S,
      Option.tab_width,
      Option.target_cpu,
      Option.target_legacy_spelling,
      Option.target,
      Option.tbd_compatibility_version_EQ,
      Option.tbd_compatibility_version,
      Option.tbd_current_version_EQ,
      Option.tbd_current_version,
      Option.tbd_install_name_EQ,
      Option.tbd_install_name,
      Option.toolchain_stdlib_rpath,
      Option.tools_directory,
      Option.trace_stats_events,
      Option.track_system_dependencies,
      Option.triple,
      Option.type_info_dump_filter_EQ,
      Option.typecheck,
      Option.typo_correction_limit,
      Option.update_code,
      Option.use_jit,
      Option.use_ld,
      Option.use_malloc,
      Option.use_tabs,
      Option.validate_tbd_against_ir_EQ,
      Option.value_recursion_threshold,
      Option.verify_apply_fixes,
      Option.verify_debug_info,
      Option.verify_generic_signatures,
      Option.verify_ignore_unknown,
      Option.verify_syntax_tree,
      Option.verify_type_layout,
      Option.verify,
      Option.version,
      Option.version_,
      Option.vfsoverlay_EQ,
      Option.vfsoverlay,
      Option.v,
      Option.warn_if_astscope_lookup,
      Option.warn_implicit_overrides,
      Option.warn_long_expression_type_checking_EQ,
      Option.warn_long_expression_type_checking,
      Option.warn_long_function_bodies_EQ,
      Option.warn_long_function_bodies,
      Option.warn_swift3_objc_inference_complete,
      Option.warn_swift3_objc_inference_minimal,
      Option.warn_swift3_objc_inference,
      Option.warnings_as_errors,
      Option.whole_module_optimization,
      Option.wmo,
      Option.working_directory_EQ,
      Option.working_directory,
      Option.Xcc,
      Option.Xclang_linker,
      Option.Xfrontend,
      Option.Xlinker,
      Option.Xllvm,
      Option._DASH_DASH,
    ]
  }
}

extension Option {
  public enum Group {
    case O
    case code_formatting
    case debug_crash
    case g
    case `internal`
    case internal_debug
    case linker_option
    case modes
  }
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
