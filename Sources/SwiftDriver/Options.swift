
extension Option {
  @Option("-###", .flag, alias: Option.driver_print_jobs) static var _HASH_HASH_HASH: Option
  @Option("-api-diff-data-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Load platform and version specific API migration data files from <path>. Ignored if -api-diff-data-file is specified.") static var api_diff_data_dir: Option
  @Option("-api-diff-data-file", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "API migration data is from <path>") static var api_diff_data_file: Option
  @Option("-application-extension", .flag, attributes: [.frontend, .noInteractive], helpText: "Restrict code to those available for App Extensions") static var enable_app_extension: Option
  @Option("-assert-config", .separate, attributes: [.frontend], helpText: "Specify the assert_configuration replacement. Possible values are Debug, Release, Unchecked, DisableReplacement.") static var AssertConfig: Option
  @Option("-assume-single-threaded", .flag, attributes: [.helpHidden, .frontend], helpText: "Assume that code will be executed in a single-threaded environment") static var AssumeSingleThreaded: Option
  @Option("-autolink-force-load", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Force ld to link against this module even if no symbols are used") static var autolink_force_load: Option
  @Option("-autolink-library", .separate, attributes: [.frontend, .noDriver], helpText: "Add dependent library") static var autolink_library: Option
  @Option("-build-module-from-parseable-interface", .flag, alias: Option.compile_module_from_interface, attributes: [.helpHidden, .frontend, .noDriver]) static var build_module_from_parseable_interface: Option
  @Option("-bypass-batch-mode-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Bypass checks for batch-mode errors.") static var bypass_batch_mode_checks: Option
  @Option("-check-onone-completeness", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print errors if the compile OnoneSupport module is missing symbols") static var check_onone_completeness: Option
  @Option("-code-complete-call-pattern-heuristics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use heuristics to guess whether we want call pattern completions") static var code_complete_call_pattern_heuristics: Option
  @Option("-code-complete-inits-in-postfix-expr", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Include initializers when completing a postfix expression") static var code_complete_inits_in_postfix_expr: Option
  @Option("-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Print diagnostics in color") static var color_diagnostics: Option
  @Option("-compile-module-from-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Treat the (single) input as a swiftinterface and produce a module") static var compile_module_from_interface: Option
  @Option("-continue-building-after-errors", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Continue building, even after errors are encountered") static var continue_building_after_errors: Option
  @Option("-crosscheck-unqualified-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Compare legacy DeclContext- to ASTScope-based unqualified name lookup (for debugging)") static var crosscheck_unqualified_lookup: Option
  @Option("-c", .flag, alias: Option.emit_object, attributes: [.frontend, .noInteractive]) static var c: Option
  @Option("-debug-assert-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure after parsing") static var debug_assert_after_parse: Option
  @Option("-debug-assert-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure immediately") static var debug_assert_immediately: Option
  @Option("-debug-constraints-attempt", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint solver at a given attempt") static var debug_constraints_attempt: Option
  @Option("-debug-constraints-on-line=", .joined, alias: Option.debug_constraints_on_line, attributes: [.helpHidden, .frontend, .noDriver]) static var debug_constraints_on_line_EQ: Option
  @Option("-debug-constraints-on-line", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<line>", helpText: "Debug the constraint solver for expressions on <line>") static var debug_constraints_on_line: Option
  @Option("-debug-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint-based type checker") static var debug_constraints: Option
  @Option("-debug-crash-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash after parsing") static var debug_crash_after_parse: Option
  @Option("-debug-crash-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash immediately") static var debug_crash_immediately: Option
  @Option("-debug-cycles", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print out debug dumps when cycles are detected in evaluation") static var debug_cycles: Option
  @Option("-debug-diagnostic-names", .flag, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Include diagnostic names when printing") static var debug_diagnostic_names: Option
  @Option("-debug-forbid-typecheck-prefix", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Triggers llvm fatal_error if typechecker tries to typecheck a decl with the provided prefix name") static var debug_forbid_typecheck_prefix: Option
  @Option("-debug-generic-signatures", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug generic signatures") static var debug_generic_signatures: Option
  @Option("-debug-info-format=", .joined, attributes: [.frontend], helpText: "Specify the debug info format type to either 'dwarf' or 'codeview'") static var debug_info_format: Option
  @Option("-debug-info-store-invocation", .flag, attributes: [.frontend], helpText: "Emit the compiler invocation in the debug info.") static var debug_info_store_invocation: Option
  @Option("-debug-prefix-map", .separate, attributes: [.frontend], helpText: "Remap source paths in debug info") static var debug_prefix_map: Option
  @Option("-debug-time-compilation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Prints the time taken by each compilation phase") static var debug_time_compilation: Option
  @Option("-debug-time-expression-type-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each expression") static var debug_time_expression_type_checking: Option
  @Option("-debug-time-function-bodies", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each function body") static var debug_time_function_bodies: Option
  @Option("-debugger-support", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Process swift code as if running in the debugger") static var debugger_support: Option
  @Option("-debugger-testing-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Instrument the code with calls to an intrinsic that record the expected values of local variables so they can be compared against the results from the debugger.") static var debugger_testing_transform: Option
  @Option("-deprecated-integrated-repl", .flag, attributes: [.frontend, .noBatch]) static var deprecated_integrated_repl: Option
  @Option("-diagnostics-editor-mode", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnostics will be used in editor") static var diagnostics_editor_mode: Option
  @Option("-disable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't respect access control restrictions") static var disable_access_control: Option
  @Option("-disable-arc-opts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL ARC optimization passes.") static var disable_arc_opts: Option
  @Option("-disable-astscope-lookup", .flag, attributes: [.frontend], helpText: "Disable ASTScope-based unqualified name lookup") static var disable_astscope_lookup: Option
  @Option("-disable-autolink-framework", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable autolinking against the provided framework") static var disable_autolink_framework: Option
  @Option("-disable-autolinking-runtime-compatibility-dynamic-replacements", .flag, attributes: [.frontend], helpText: "Do not use autolinking for the dynamic replacement runtime compatibility library") static var disable_autolinking_runtime_compatibility_dynamic_replacements: Option
  @Option("-disable-autolinking-runtime-compatibility", .flag, attributes: [.frontend], helpText: "Do not use autolinking for runtime compatibility libraries") static var disable_autolinking_runtime_compatibility: Option
  @Option("-disable-availability-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable checking for potentially unavailable APIs") static var disable_availability_checking: Option
  @Option("-disable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Disable combining frontend jobs into batches") static var disable_batch_mode: Option
  @Option("-disable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Disable automatic generation of bridging PCH files") static var disable_bridging_pch: Option
  @Option("-disable-constraint-solver-performance-hacks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable all the hacks in the constraint solver") static var disable_constraint_solver_performance_hacks: Option
  @Option("-disable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't attempt to recover from missing xrefs (etc) in swiftmodules") static var disable_deserialization_recovery: Option
  @Option("-disable-diagnostic-passes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run diagnostic passes") static var disable_diagnostic_passes: Option
  @Option("-disable-function-builder-one-way-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable one-way constraints in the function builder transformation") static var disable_function_builder_one_way_constraints: Option
  @Option("-disable-incremental-llvm-codegen", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable incremental llvm code generation.") static var disable_incremental_llvm_codegeneration: Option
  @Option("-disable-legacy-type-info", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Completely disable legacy type layout") static var disable_legacy_type_info: Option
  @Option("-disable-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run LLVM optimization passes") static var disable_llvm_optzns: Option
  @Option("-disable-llvm-slp-vectorizer", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run LLVM SLP vectorizer") static var disable_llvm_slp_vectorizer: Option
  @Option("-disable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't add names to local values in LLVM IR") static var disable_llvm_value_names: Option
  @Option("-disable-llvm-verify", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run the LLVM IR verifier.") static var disable_llvm_verify: Option
  @Option("-disable-migrator-fixits", .flag, attributes: [.frontend, .noInteractive], helpText: "Disable the Migrator phase which automatically applies fix-its") static var disable_migrator_fixits: Option
  @Option("-disable-modules-validate-system-headers", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating system headers in the Clang importer") static var disable_modules_validate_system_headers: Option
  @Option("-disable-named-lazy-member-loading", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable per-name lazy member loading") static var disable_named_lazy_member_loading: Option
  @Option("-disable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow switches over non-frozen enums without catch-all cases") static var disable_nonfrozen_enum_exhaustivity_diagnostics: Option
  @Option("-disable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow classes with unstable mangled names to adopt NSCoding") static var disable_nskeyedarchiver_diagnostics: Option
  @Option("-disable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable requiring uses of @objc to require importing the Foundation module") static var disable_objc_attr_requires_foundation_module: Option
  @Option("-disable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable Objective-C interop code generation and config directives") static var disable_objc_interop: Option
  @Option("-disable-parser-lookup", .flag, attributes: [.frontend], helpText: "Disable parser lookup & use ast scope lookup only (experimental)") static var disable_parser_lookup: Option
  @Option("-disable-playground-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable playground transformation") static var disable_playground_transform: Option
  @Option("-disable-previous-implementation-calls-in-dynamic-replacements", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable calling the previous implementation in dynamic replacements") static var disable_previous_implementation_calls_in_dynamic_replacements: Option
  @Option("-disable-reflection-metadata", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of reflection metadata for nominal types") static var disable_reflection_metadata: Option
  @Option("-disable-reflection-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of names of stored properties and enum cases inreflection metadata") static var disable_reflection_names: Option
  @Option("-disable-serialization-nested-type-lookup-table", .flag, attributes: [.frontend, .noDriver], helpText: "Force module merging to use regular lookups to find nested types") static var disable_serialization_nested_type_lookup_table: Option
  @Option("-disable-sil-ownership-verifier", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not verify ownership invariants during SIL Verification ") static var disable_sil_ownership_verifier: Option
  @Option("-disable-sil-partial-apply", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable use of partial_apply in SIL generation") static var disable_sil_partial_apply: Option
  @Option("-disable-sil-perf-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL performance optimization passes") static var disable_sil_perf_optzns: Option
  @Option("-disable-swift-bridge-attr", .flag, attributes: [.helpHidden, .frontend], helpText: "Disable using the swift bridge attribute") static var disable_swift_bridge_attr: Option
  @Option("-disable-swift-specific-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run Swift specific LLVM optimization passes.") static var disable_swift_specific_llvm_optzns: Option
  @Option("-disable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 4 behavior)") static var disable_swift3_objc_inference: Option
  @Option("-disable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking the target OS of serialized modules") static var disable_target_os_checking: Option
  @Option("-disable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking of @testable") static var disable_testable_attr_requires_testable_module: Option
  @Option("-disable-tsan-inout-instrumentation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable treatment of inout parameters as Thread Sanitizer accesses") static var disable_tsan_inout_instrumentation: Option
  @Option("-disable-typo-correction", .flag, attributes: [.frontend, .noDriver], helpText: "Disable typo correction") static var disable_typo_correction: Option
  @Option("-disable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diable verification of access markers used to enforce exclusivity.") static var disable_verify_exclusivity: Option
  @Option("-driver-always-rebuild-dependents", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Always rebuild dependents of files that have been modified") static var driver_always_rebuild_dependents: Option
  @Option("-driver-batch-count", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number of batch-mode partitions, rather than partitioning dynamically") static var driver_batch_count: Option
  @Option("-driver-batch-seed", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given seed value to randomize batch-mode partitions") static var driver_batch_seed: Option
  @Option("-driver-batch-size-limit", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number as the upper limit on dynamic batch-mode partition size") static var driver_batch_size_limit: Option
  @Option("-driver-emit-experimental-dependency-dot-file-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Emit dot files every time driver imports an experimental swiftdeps file.") static var driver_emit_experimental_dependency_dot_file_after_every_import: Option
  @Option("-driver-filelist-threshold=", .joined, alias: Option.driver_filelist_threshold) static var driver_filelist_threshold_EQ: Option
  @Option("-driver-filelist-threshold", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Pass input or output file names as filelists if there are more than <n>") static var driver_filelist_threshold: Option
  @Option("-driver-force-response-files", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Force the use of response files for testing") static var driver_force_response_files: Option
  @Option("--driver-mode=", .joined, attributes: [.helpHidden], helpText: "Set the driver mode to either 'swift' or 'swiftc'") static var driver_mode: Option
  @Option("-driver-print-actions", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of actions to perform") static var driver_print_actions: Option
  @Option("-driver-print-bindings", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of job inputs and outputs") static var driver_print_bindings: Option
  @Option("-driver-print-derived-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the derived output file map") static var driver_print_derived_output_file_map: Option
  @Option("-driver-print-jobs", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of jobs to execute") static var driver_print_jobs: Option
  @Option("-driver-print-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the output file map") static var driver_print_output_file_map: Option
  @Option("-driver-show-incremental", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "With -v, dump information about why files are being rebuilt") static var driver_show_incremental: Option
  @Option("-driver-show-job-lifecycle", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Show every step in the lifecycle of driver jobs") static var driver_show_job_lifecycle: Option
  @Option("-driver-skip-execution", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Skip execution of subtasks when performing compilation") static var driver_skip_execution: Option
  @Option("-driver-time-compilation", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Prints the total time it took to execute all compilation tasks") static var driver_time_compilation: Option
  @Option("-driver-use-filelists", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Pass input files as filelists whenever possible") static var driver_use_filelists: Option
  @Option("-driver-use-frontend-path", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given executable to perform compilations. Arguments can be passed as a ';' separated list") static var driver_use_frontend_path: Option
  @Option("-driver-verify-experimental-dependency-graph-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Debug DriverGraph by verifying it after every import") static var driver_verify_experimental_dependency_graph_after_every_import: Option
  @Option("-dump-api-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The path to output swift interface files for the compiled source files") static var dump_api_path: Option
  @Option("-dump-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and dump AST(s)") static var dump_ast: Option
  @Option("-dump-clang-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dump Clang diagnostics to stderr") static var dump_clang_diagnostics: Option
  @Option("-dump-interface-hash", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Parse input file(s) and dump interface token hash(es)") static var dump_interface_hash: Option
  @Option("-dump-migration-states-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Dump the input text, output text, and states for migration to <path>") static var dump_migration_states_dir: Option
  @Option("-dump-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s) and dump AST(s)") static var dump_parse: Option
  @Option("-dump-scope-maps", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<expanded-or-list-of-line:column>", helpText: "Parse and type-check input file(s) and dump the scope map(s)") static var dump_scope_maps: Option
  @Option("-dump-type-info", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Output YAML dump of fixed-size types from all imported modules") static var dump_type_info: Option
  @Option("-dump-type-refinement-contexts", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Type-check input file(s) and dump type refinement contexts(s)") static var dump_type_refinement_contexts: Option
  @Option("-dump-usr", .flag, attributes: [.frontend, .noInteractive], helpText: "Dump USR for each declaration reference") static var dump_usr: Option
  @Option("-D", .joinedOrSeparate, attributes: [.frontend], helpText: "Marks a conditional compilation flag as true") static var D: Option
  @Option("-embed-bitcode-marker", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed placeholder LLVM IR data as a marker") static var embed_bitcode_marker: Option
  @Option("-embed-bitcode", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed LLVM IR bitcode as data") static var embed_bitcode: Option
  @Option("-emit-assembly", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit assembly file(s) (-S)") static var emit_assembly: Option
  @Option("-emit-bc", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM BC file(s)") static var emit_bc: Option
  @Option("-emit-dependencies-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output basic Make-compatible dependencies file to <path>") static var emit_dependencies_path: Option
  @Option("-emit-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit basic Make-compatible dependencies files") static var emit_dependencies: Option
  @Option("-emit-executable", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a linked executable") static var emit_executable: Option
  @Option("-emit-fixits-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output compiler fixits as source edits to <path>") static var emit_fixits_path: Option
  @Option("-emit-imported-modules", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a list of the imported modules") static var emit_imported_modules: Option
  @Option("-emit-ir", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM IR file(s)") static var emit_ir: Option
  @Option("-emit-library", .flag, attributes: [.noInteractive], helpText: "Emit a linked library") static var emit_library: Option
  @Option("-emit-loaded-module-trace-path=", .joined, alias: Option.emit_loaded_module_trace_path, attributes: [.frontend, .noInteractive, .argumentIsPath]) static var emit_loaded_module_trace_path_EQ: Option
  @Option("-emit-loaded-module-trace-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Emit the loaded module trace JSON to <path>") static var emit_loaded_module_trace_path: Option
  @Option("-emit-loaded-module-trace", .flag, attributes: [.frontend, .noInteractive], helpText: "Emit a JSON file containing information about what modules were loaded") static var emit_loaded_module_trace: Option
  @Option("-emit-migrated-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the migrated source file to <path>") static var emit_migrated_file_path: Option
  @Option("-emit-module-doc-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output module documentation file <path>") static var emit_module_doc_path: Option
  @Option("-emit-module-doc", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a module documentation file based on documentation comments") static var emit_module_doc: Option
  @Option("-emit-module-interface-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Output module interface file to <path>") static var emit_module_interface_path: Option
  @Option("-emit-module-interface", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Output module interface file") static var emit_module_interface: Option
  @Option("-emit-module-path=", .joined, alias: Option.emit_module_path, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath]) static var emit_module_path_EQ: Option
  @Option("-emit-module-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit an importable module to <path>") static var emit_module_path: Option
  @Option("-emit-module", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit an importable module") static var emit_module: Option
  @Option("-emit-objc-header-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit an Objective-C header file to <path>") static var emit_objc_header_path: Option
  @Option("-emit-objc-header", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit an Objective-C header file") static var emit_objc_header: Option
  @Option("-emit-object", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit object file(s) (-c)") static var emit_object: Option
  @Option("-emit-parseable-module-interface-path", .separate, alias: Option.emit_module_interface_path, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath]) static var emit_parseable_module_interface_path: Option
  @Option("-emit-parseable-module-interface", .flag, alias: Option.emit_module_interface, attributes: [.helpHidden, .noInteractive, .doesNotAffectIncrementalBuild]) static var emit_parseable_module_interface: Option
  @Option("-emit-pch", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit PCH for imported Objective-C header file") static var emit_pch: Option
  @Option("-emit-reference-dependencies-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output Swift-style dependencies file to <path>") static var emit_reference_dependencies_path: Option
  @Option("-emit-reference-dependencies", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a Swift-style dependencies file") static var emit_reference_dependencies: Option
  @Option("-emit-remap-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the replacement map describing Swift Migrator changes to <path>") static var emit_remap_file_path: Option
  @Option("-emit-sibgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + raw SIL file(s)") static var emit_sibgen: Option
  @Option("-emit-sib", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + canonical SIL file(s)") static var emit_sib: Option
  @Option("-emit-silgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit raw SIL file(s)") static var emit_silgen: Option
  @Option("-emit-sil", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit canonical SIL file(s)") static var emit_sil: Option
  @Option("-emit-sorted-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When printing SIL, print out all sil entities sorted by name to ease diffing") static var emit_sorted_sil: Option
  @Option("-emit-stack-promotion-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit runtime checks for correct stack promotion of objects.") static var stack_promotion_checks: Option
  @Option("-emit-syntax", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Parse input file(s) and emit the Syntax tree(s) as JSON") static var emit_syntax: Option
  @Option("-emit-tbd-path=", .joined, alias: Option.emit_tbd_path, attributes: [.frontend, .noInteractive, .argumentIsPath]) static var emit_tbd_path_EQ: Option
  @Option("-emit-tbd-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Emit the TBD file to <path>") static var emit_tbd_path: Option
  @Option("-emit-tbd", .flag, attributes: [.frontend, .noInteractive], helpText: "Emit a TBD file") static var emit_tbd: Option
  @Option("-emit-verbose-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit locations during SIL emission") static var emit_verbose_sil: Option
  @Option("-enable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Respect access control restrictions") static var enable_access_control: Option
  @Option("-enable-anonymous-context-mangled-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable emission of mangled names in anonymous context descriptors") static var enable_anonymous_context_mangled_names: Option
  @Option("-enable-astscope-lookup", .flag, attributes: [.frontend], helpText: "Enable ASTScope-based unqualified name lookup") static var enable_astscope_lookup: Option
  @Option("-enable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Enable combining frontend jobs into batches") static var enable_batch_mode: Option
  @Option("-enable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Enable automatic generation of bridging PCH files") static var enable_bridging_pch: Option
  @Option("-enable-cxx-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable C++ interop code generation and config directives") static var enable_cxx_interop: Option
  @Option("-enable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Attempt to recover from missing xrefs (etc) in swiftmodules") static var enable_deserialization_recovery: Option
  @Option("-enable-dynamic-replacement-chaining", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable chaining of dynamic replacements") static var enable_dynamic_replacement_chaining: Option
  @Option("-enable-experimental-dependencies", .flag, attributes: [.helpHidden, .frontend], helpText: "Experimental work-in-progress to be more selective about incremental recompilation") static var enable_experimental_dependencies: Option
  @Option("-enable-experimental-static-assert", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental #assert") static var enable_experimental_static_assert: Option
  @Option("-enable-function-builder-one-way-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable one-way constraints in the function builder transformation") static var enable_function_builder_one_way_constraints: Option
  @Option("-enable-implicit-dynamic", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add 'dynamic' to all declarations") static var enable_implicit_dynamic: Option
  @Option("-enable-infer-import-as-member", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Infer when a global could be imported as a member") static var enable_infer_import_as_member: Option
  @Option("-enable-large-loadable-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable Large Loadable types IRGen pass") static var enable_large_loadable_types: Option
  @Option("-enable-library-evolution", .flag, attributes: [.frontend, .moduleInterface], helpText: "Build the module to allow binary-compatible library evolution") static var enable_library_evolution: Option
  @Option("-enable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add names to local values in LLVM IR") static var enable_llvm_value_names: Option
  @Option("-enable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose switches over non-frozen enums without catch-all cases") static var enable_nonfrozen_enum_exhaustivity_diagnostics: Option
  @Option("-enable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose classes with unstable mangled names adopting NSCoding") static var enable_nskeyedarchiver_diagnostics: Option
  @Option("-enable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable requiring uses of @objc to require importing the Foundation module") static var enable_objc_attr_requires_foundation_module: Option
  @Option("-enable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable Objective-C interop code generation and config directives") static var enable_objc_interop: Option
  @Option("-enable-operator-designated-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable operator designated types") static var enable_operator_designated_types: Option
  @Option("-enable-ownership-stripping-after-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Strip ownership after serialization") static var enable_ownership_stripping_after_serialization: Option
  @Option("-enable-private-imports", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal and private API to be accessed") static var enable_private_imports: Option
  @Option("-enable-resilience", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Deprecated, use -enable-library-evolution instead") static var enable_resilience: Option
  @Option("-enable-sil-opaque-values", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable SIL Opaque Values") static var enable_sil_opaque_values: Option
  @Option("-enable-source-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable importing of Swift source files") static var enable_source_import: Option
  @Option("-enable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 3 behavior)") static var enable_swift3_objc_inference: Option
  @Option("-enable-swiftcall", .flag, attributes: [.frontend, .noDriver], helpText: "Enable the use of LLVM swiftcall support") static var enable_swiftcall: Option
  @Option("-enable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking the target OS of serialized modules") static var enable_target_os_checking: Option
  @Option("-enable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking of @testable") static var enable_testable_attr_requires_testable_module: Option
  @Option("-enable-testing", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal API to be accessed for testing") static var enable_testing: Option
  @Option("-enable-throw-without-try", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow throwing function calls without 'try'") static var enable_throw_without_try: Option
  @Option("-enable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable verification of access markers used to enforce exclusivity.") static var enable_verify_exclusivity: Option
  @Option("-enforce-exclusivity=", .joined, attributes: [.frontend, .moduleInterface], metaVar: "<enforcement>", helpText: "Enforce law of exclusivity") static var enforce_exclusivity_EQ: Option
  @Option("-experimental-dependency-include-intrafile", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Include within-file dependencies.") static var experimental_dependency_include_intrafile: Option
  @Option("-external-pass-pipeline-filename", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<pass_pipeline_file>", helpText: "Use the pass pipeline defined by <pass_pipeline_file>") static var external_pass_pipeline_filename: Option
  @Option("-F=", .joined, alias: Option.F, attributes: [.frontend, .argumentIsPath]) static var F_EQ: Option
  @Option("-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify source inputs in a file rather than on the command line") static var filelist: Option
  @Option("-fixit-all", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Apply all fixits from diagnostics without any filtering") static var fixit_all: Option
  @Option("-force-public-linkage", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force public linkage for private symbols. Used by LLDB.") static var force_public_linkage: Option
  @Option("-force-single-frontend-invocation", .flag, alias: Option.whole_module_optimization, attributes: [.helpHidden, .frontend, .noInteractive]) static var force_single_frontend_invocation: Option
  @Option("-framework", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a framework which should be linked against") static var framework: Option
  @Option("-Fsystem", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to system framework search path") static var Fsystem: Option
  @Option("-F", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to framework search path") static var F: Option
  @Option("-gdwarf-types", .flag, attributes: [.frontend], helpText: "Emit full DWARF type info.") static var gdwarf_types: Option
  @Option("-gline-tables-only", .flag, attributes: [.frontend], helpText: "Emit minimal debug info for backtraces only") static var gline_tables_only: Option
  @Option("-gnone", .flag, attributes: [.frontend], helpText: "Don't emit debug info") static var gnone: Option
  @Option("-group-info-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The path to collect the group information of the compiled module") static var group_info_path: Option
  @Option("-gsil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Write the SIL into a file and generate debug-info to debug on SIL  level.") static var debug_on_sil: Option
  @Option("-g", .flag, attributes: [.frontend], helpText: "Emit debug info. This is the preferred setting for debugging with LLDB.") static var g: Option
  @Option("-help-hidden", .flag, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options") static var help_hidden: Option
  @Option("--help-hidden", .flag, alias: Option.help_hidden, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options") static var help_hidden_: Option
  @Option("-help", .flag, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options") static var help: Option
  @Option("--help", .flag, alias: Option.help, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options") static var help_: Option
  @Option("-h", .flag, alias: Option.help) static var h: Option
  @Option("-I=", .joined, alias: Option.I, attributes: [.frontend, .argumentIsPath]) static var I_EQ: Option
  @Option("-import-cf-types", .flag, attributes: [.helpHidden, .frontend], helpText: "Recognize and import CF types as class types") static var import_cf_types: Option
  @Option("-import-module", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Implicitly import the specified module") static var import_module: Option
  @Option("-import-objc-header", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Implicitly imports an Objective-C header file") static var import_objc_header: Option
  @Option("-import-underlying-module", .flag, attributes: [.frontend, .noInteractive], helpText: "Implicitly imports the Objective-C half of a module") static var import_underlying_module: Option
  @Option("-in-place", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Overwrite input file with formatted file.") static var in_place: Option
  @Option("-incremental", .flag, attributes: [.helpHidden, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Perform an incremental build if possible") static var incremental: Option
  @Option("-indent-switch-case", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Indent cases in switch statements.") static var indent_switch_case: Option
  @Option("-indent-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Number of characters to indent.") static var indent_width: Option
  @Option("-index-file-path", .separate, attributes: [.noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Produce index data for file <path>") static var index_file_path: Option
  @Option("-index-file", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Produce index data for a source file") static var index_file: Option
  @Option("-index-ignore-system-modules", .flag, attributes: [.noInteractive], helpText: "Avoid indexing system modules") static var index_ignore_system_modules: Option
  @Option("-index-store-path", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<path>", helpText: "Store indexing data to <path>") static var index_store_path: Option
  @Option("-index-system-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit index data for imported serialized swift system modules") static var index_system_modules: Option
  @Option("-interpret", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Immediate mode") static var interpret: Option
  @Option("-I", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to the import search path") static var I: Option
  @Option("-i", .flag) static var i: Option
  @Option("-j", .joinedOrSeparate, attributes: [.doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Number of commands to execute in parallel") static var j: Option
  @Option("-L=", .joined, alias: Option.L, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath]) static var L_EQ: Option
  @Option("-lazy-astscopes", .flag, attributes: [.frontend, .noDriver], helpText: "Build ASTScopes lazily") static var lazy_astscopes: Option
  @Option("-libc", .separate, helpText: "libc runtime library to use") static var libc: Option
  @Option("-line-range", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n:n>", helpText: "<start line>:<end line>. Formats a range of lines (1-based). Can only be used with one input file.") static var line_range: Option
  @Option("-link-objc-runtime", .flag, attributes: [.doesNotAffectIncrementalBuild]) static var link_objc_runtime: Option
  @Option("-lldb-repl", .flag, attributes: [.helpHidden, .noBatch], helpText: "LLDB-enhanced REPL mode") static var lldb_repl: Option
  @Option("-L", .joinedOrSeparate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Add directory to library link search path") static var L: Option
  @Option("-l", .joined, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a library which should be linked against") static var l: Option
  @Option("-merge-modules", .flag, attributes: [.frontend, .noDriver], helpText: "Merge the input modules without otherwise processing them") static var merge_modules: Option
  @Option("-migrate-keep-objc-visibility", .flag, attributes: [.frontend, .noInteractive], helpText: "When migrating, add '@objc' to declarations that would've been implicitly visible in Swift 3") static var migrate_keep_objc_visibility: Option
  @Option("-migrator-update-sdk", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.") static var migrator_update_sdk: Option
  @Option("-migrator-update-swift", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.") static var migrator_update_swift: Option
  @Option("-module-cache-path", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Specifies the Clang module cache path") static var module_cache_path: Option
  @Option("-module-interface-preserve-types-as-written", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface, preserve types as they were written in the source") static var module_interface_preserve_types_as_written: Option
  @Option("-module-link-name=", .joined, alias: Option.module_link_name, attributes: [.frontend]) static var module_link_name_EQ: Option
  @Option("-module-link-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Library to link against when using this module") static var module_link_name: Option
  @Option("-module-name=", .joined, alias: Option.module_name, attributes: [.frontend]) static var module_name_EQ: Option
  @Option("-module-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Name of the module to build") static var module_name: Option
  @Option("-no-clang-module-breadcrumbs", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't emit DWARF skeleton CUs for imported Clang modules. Use this when building a redistributable static archive.") static var no_clang_module_breadcrumbs: Option
  @Option("-no-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Do not print diagnostics in color") static var no_color_diagnostics: Option
  @Option("-no-link-objc-runtime", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't link in additions to the Objective-C runtime") static var no_link_objc_runtime: Option
  @Option("-no-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Never serialize options for debugging (default: only for apps)") static var no_serialize_debugging_options: Option
  @Option("-no-static-executable", .flag, attributes: [.helpHidden], helpText: "Don't statically link the executable") static var no_static_executable: Option
  @Option("-no-static-stdlib", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't statically link the Swift standard library") static var no_static_stdlib: Option
  @Option("-no-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't add any rpath entries.") static var no_stdlib_rpath: Option
  @Option("-no-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Do not add an rpath entry for the toolchain's standard library (default)") static var no_toolchain_stdlib_rpath: Option
  @Option("-nostdimport", .flag, attributes: [.frontend], helpText: "Don't search the standard library import path for modules") static var nostdimport: Option
  @Option("-num-threads", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Enable multi-threading and specify number of threads") static var num_threads: Option
  @Option("-Onone", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile without any optimization") static var Onone: Option
  @Option("-Oplayground", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Compile with optimizations appropriate for a playground") static var Oplayground: Option
  @Option("-Osize", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and target small code size") static var Osize: Option
  @Option("-Ounchecked", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and remove runtime safety checks") static var Ounchecked: Option
  @Option("-output-file-map=", .joined, alias: Option.output_file_map, attributes: [.noInteractive, .argumentIsPath]) static var output_file_map_EQ: Option
  @Option("-output-file-map", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "A file which specifies the location of outputs") static var output_file_map: Option
  @Option("-output-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify outputs in a file rather than on the command line") static var output_filelist: Option
  @Option("-output-request-graphviz", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit GraphViz output visualizing the request graph") static var output_request_graphviz: Option
  @Option("-O", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations") static var O: Option
  @Option("-o", .joinedOrSeparate, attributes: [.frontend, .noInteractive, .autolinkExtract, .moduleWrap, .indent, .argumentIsPath], metaVar: "<file>", helpText: "Write output to <file>") static var o: Option
  @Option("-package-description-version", .separate, attributes: [.helpHidden, .frontend, .moduleInterface], metaVar: "<vers>", helpText: "The version number to be applied on the input for the PackageDescription availability kind") static var package_description_version: Option
  @Option("-parse-as-library", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file(s) as libraries, not scripts") static var parse_as_library: Option
  @Option("-parse-sil", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file as SIL code, not Swift source") static var parse_sil: Option
  @Option("-parse-stdlib", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Parse the input file(s) as the Swift standard library") static var parse_stdlib: Option
  @Option("-parseable-output", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit textual output in a parseable format") static var parseable_output: Option
  @Option("-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s)") static var parse: Option
  @Option("-pc-macro", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the 'program counter simulation' macro") static var pc_macro: Option
  @Option("-pch-disable-validation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating the persistent PCH") static var pch_disable_validation: Option
  @Option("-pch-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to persist automatically created precompiled bridging headers") static var pch_output_dir: Option
  @Option("-playground-high-performance", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Omit instrumentation that has a high runtime performance impact") static var playground_high_performance: Option
  @Option("-playground", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the playground semantics and transformation") static var playground: Option
  @Option("-prebuilt-module-cache-path=", .joined, alias: Option.prebuilt_module_cache_path, attributes: [.helpHidden, .frontend, .noDriver]) static var prebuilt_module_cache_path_EQ: Option
  @Option("-prebuilt-module-cache-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Directory of prebuilt modules for loading module interfaces") static var prebuilt_module_cache_path: Option
  @Option("-primary-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify primary inputs in a file rather than on the command line") static var primary_filelist: Option
  @Option("-primary-file", .separate, attributes: [.frontend, .noDriver], helpText: "Produce output for this file, not the whole module") static var primary_file: Option
  @Option("-print-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and pretty print AST(s)") static var print_ast: Option
  @Option("-print-clang-stats", .flag, attributes: [.frontend, .noDriver], helpText: "Print Clang importer statistics") static var print_clang_stats: Option
  @Option("-print-inst-counts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Before IRGen, count all the various SIL instructions. Must be used in conjunction with -print-stats.") static var print_inst_counts: Option
  @Option("-print-llvm-inline-tree", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print the LLVM inline tree.") static var print_llvm_inline_tree: Option
  @Option("-print-stats", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print various statistics") static var print_stats: Option
  @Option("-profile-coverage-mapping", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate coverage data for use with profiled execution counts") static var profile_coverage_mapping: Option
  @Option("-profile-generate", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate instrumented code to collect execution counts") static var profile_generate: Option
  @Option("-profile-stats-entities", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir, subdivided by source entity") static var profile_stats_entities: Option
  @Option("-profile-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir") static var profile_stats_events: Option
  @Option("-profile-use=", .commaJoined, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<profdata>", helpText: "Supply a profdata file to enable profile-guided optimization") static var profile_use: Option
  @Option("-read-legacy-type-info-path=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Read legacy type layout from the given path instead of default path") static var read_legacy_type_info_path_EQ: Option
  @Option("-remove-runtime-asserts", .flag, attributes: [.frontend], helpText: "Remove runtime safety checks.") static var RemoveRuntimeAsserts: Option
  @Option("-repl", .flag, attributes: [.helpHidden, .frontend, .noBatch], helpText: "REPL mode (the default if there is no input file)") static var repl: Option
  @Option("-report-errors-to-debugger", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, will be removed in future versions.") static var report_errors_to_debugger: Option
  @Option("-require-explicit-availability-target", .separate, attributes: [.frontend, .noInteractive], metaVar: "<target>", helpText: "Suggest fix-its adding @available(<target>, *) to public declarations without availability") static var require_explicit_availability_target: Option
  @Option("-require-explicit-availability", .flag, attributes: [.frontend, .noInteractive], helpText: "Require explicit availability on public declarations") static var require_explicit_availability: Option
  @Option("-resolve-imports", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and resolve imports in input file(s)") static var resolve_imports: Option
  @Option("-resource-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], metaVar: "</usr/lib/swift>", helpText: "The directory that holds the compiler resource files") static var resource_dir: Option
  @Option("-Rmodule-interface-rebuild", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emits a remark if an imported module needs to be re-compiled from its module interface") static var Rmodule_interface_rebuild: Option
  @Option("-Rpass-missed=", .joined, attributes: [.frontend], helpText: "Report missed transformations by optimization passes whose name matches the given POSIX regular expression") static var Rpass_missed_EQ: Option
  @Option("-Rpass=", .joined, attributes: [.frontend], helpText: "Report performed transformations by optimization passes whose name matches the given POSIX regular expression") static var Rpass_EQ: Option
  @Option("-runtime-compatibility-version", .separate, attributes: [.frontend], helpText: "Link compatibility library for Swift runtime version, or 'none'") static var runtime_compatibility_version: Option
  @Option("-sanitize-coverage=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<type>", helpText: "Specify the type of coverage instrumentation for Sanitizers and additional options separated by commas") static var sanitize_coverage_EQ: Option
  @Option("-sanitize=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<check>", helpText: "Turn on runtime checks for erroneous behavior.") static var sanitize_EQ: Option
  @Option("-save-optimization-record-path", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Specify the file name of any generated YAML optimization record") static var save_optimization_record_path: Option
  @Option("-save-optimization-record", .flag, attributes: [.frontend], helpText: "Generate a YAML optimization record file") static var save_optimization_record: Option
  @Option("-save-temps", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Save intermediate compilation results") static var save_temps: Option
  @Option("-sdk", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<sdk>", helpText: "Compile against <sdk>") static var sdk: Option
  @Option("-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Always serialize options for debugging (default: only for apps)") static var serialize_debugging_options: Option
  @Option("-serialize-diagnostics-path=", .joined, alias: Option.serialize_diagnostics_path, attributes: [.frontend, .noBatch, .doesNotAffectIncrementalBuild, .argumentIsPath]) static var serialize_diagnostics_path_EQ: Option
  @Option("-serialize-diagnostics-path", .separate, attributes: [.frontend, .noBatch, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit a serialized diagnostics file to <path>") static var serialize_diagnostics_path: Option
  @Option("-serialize-diagnostics", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Serialize diagnostics in a binary format") static var serialize_diagnostics: Option
  @Option("-serialize-module-interface-dependency-hashes", .flag, attributes: [.frontend, .noDriver]) static var serialize_module_interface_dependency_hashes: Option
  @Option("-serialize-parseable-module-interface-dependency-hashes", .flag, alias: Option.serialize_module_interface_dependency_hashes, attributes: [.frontend, .noDriver]) static var serialize_parseable_module_interface_dependency_hashes: Option
  @Option("-show-diagnostics-after-fatal", .flag, attributes: [.frontend, .noDriver], helpText: "Keep emitting subsequent diagnostics after a fatal error") static var show_diagnostics_after_fatal: Option
  @Option("-sil-debug-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not eliminate functions in Mandatory Inlining/SILCombine dead functions. (for debugging only)") static var sil_debug_serialization: Option
  @Option("-sil-inline-caller-benefit-reduction-factor", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<2>", helpText: "Controls the aggressiveness of performance inlining in -Osize mode by reducing the base benefits of a caller (lower value permits more inlining!)") static var sil_inline_caller_benefit_reduction_factor: Option
  @Option("-sil-inline-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<50>", helpText: "Controls the aggressiveness of performance inlining") static var sil_inline_threshold: Option
  @Option("-sil-merge-partial-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Merge SIL from all partial swiftmodules into the final module") static var sil_merge_partial_modules: Option
  @Option("-sil-unroll-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<250>", helpText: "Controls the aggressiveness of loop unrolling") static var sil_unroll_threshold: Option
  @Option("-sil-verify-all", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Verify SIL after each transform") static var sil_verify_all: Option
  @Option("-solver-disable-shrink", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the shrink phase of expression type checking") static var solver_disable_shrink: Option
  @Option("-solver-enable-operator-designated-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable operator designated types in constraint solver") static var solver_enable_operator_designated_types: Option
  @Option("-solver-expression-time-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver]) static var solver_expression_time_threshold_EQ: Option
  @Option("-solver-memory-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the upper bound for memory consumption, in bytes, by the constraint solver") static var solver_memory_threshold: Option
  @Option("-solver-shrink-unsolved-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set The upper bound to number of sub-expressions unsolved before termination of the shrink phrase") static var solver_shrink_unsolved_threshold: Option
  @Option("-stack-promotion-limit", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Limit the size of stack promoted objects to the provided number of bytes.") static var stack_promotion_limit: Option
  @Option("-static-executable", .flag, helpText: "Statically link the executable") static var static_executable: Option
  @Option("-static-stdlib", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Statically link the Swift standard library") static var static_stdlib: Option
  @Option("-static", .flag, attributes: [.frontend, .noInteractive, .moduleInterface], helpText: "Make this module statically linkable and make the output of -emit-library a static library.") static var `static`: Option
  @Option("-stats-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to write unified compilation-statistics files to") static var stats_output_dir: Option
  @Option("-stress-astscope-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Stress ASTScope-based unqualified name lookup (for testing)") static var stress_astscope_lookup: Option
  @Option("-supplementary-output-file-map", .separate, attributes: [.frontend, .noDriver], helpText: "Specify supplementary outputs in a file rather than on the command line") static var supplementary_output_file_map: Option
  @Option("-suppress-static-exclusivity-swap", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Suppress static violations of exclusive access with swap()") static var suppress_static_exclusivity_swap: Option
  @Option("-suppress-warnings", .flag, attributes: [.frontend], helpText: "Suppress all warnings") static var suppress_warnings: Option
  @Option("-swift-version", .separate, attributes: [.frontend, .moduleInterface], metaVar: "<vers>", helpText: "Interpret input according to a specific Swift language version number") static var swift_version: Option
  @Option("-switch-checking-invocation-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver]) static var switch_checking_invocation_threshold_EQ: Option
  @Option("-S", .flag, alias: Option.emit_assembly, attributes: [.frontend, .noInteractive]) static var S: Option
  @Option("-tab-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Width of tab character.") static var tab_width: Option
  @Option("-target-cpu", .separate, attributes: [.frontend, .moduleInterface], helpText: "Generate code for a particular CPU variant") static var target_cpu: Option
  @Option("--target=", .joined, alias: Option.target, attributes: [.frontend]) static var target_legacy_spelling: Option
  @Option("-target", .separate, attributes: [.frontend, .moduleWrap, .moduleInterface], metaVar: "<triple>", helpText: "Generate code for the given target <triple>, such as x86_64-apple-macos10.9") static var target: Option
  @Option("-tbd-compatibility-version=", .joined, alias: Option.tbd_compatibility_version, attributes: [.frontend, .noDriver]) static var tbd_compatibility_version_EQ: Option
  @Option("-tbd-compatibility-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The compatibility_version to use in an emitted TBD file") static var tbd_compatibility_version: Option
  @Option("-tbd-current-version=", .joined, alias: Option.tbd_current_version, attributes: [.frontend, .noDriver]) static var tbd_current_version_EQ: Option
  @Option("-tbd-current-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The current_version to use in an emitted TBD file") static var tbd_current_version: Option
  @Option("-tbd-install_name=", .joined, alias: Option.tbd_install_name, attributes: [.frontend, .noDriver]) static var tbd_install_name_EQ: Option
  @Option("-tbd-install_name", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "The install_name to use in an emitted TBD file") static var tbd_install_name: Option
  @Option("-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Add an rpath entry for the toolchain's standard library, rather than the OS's") static var toolchain_stdlib_rpath: Option
  @Option("-tools-directory", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<directory>", helpText: "Look for external executables (ld, clang, binutils) in <directory>") static var tools_directory: Option
  @Option("-trace-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Trace changes to stats in -stats-output-dir") static var trace_stats_events: Option
  @Option("-track-system-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Track system dependencies while emitting Make-style dependencies") static var track_system_dependencies: Option
  @Option("-triple", .separate, alias: Option.target, attributes: [.frontend, .noDriver]) static var triple: Option
  @Option("-type-info-dump-filter=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "One of 'all', 'resilient' or 'fragile'") static var type_info_dump_filter_EQ: Option
  @Option("-typecheck", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s)") static var typecheck: Option
  @Option("-typo-correction-limit", .separate, attributes: [.helpHidden, .frontend], metaVar: "<n>", helpText: "Limit the number of times the compiler will attempt typo correction to <n>") static var typo_correction_limit: Option
  @Option("-update-code", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Update Swift code") static var update_code: Option
  @Option("-use-jit", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Register Objective-C classes as if the JIT were in use") static var use_jit: Option
  @Option("-use-ld=", .joined, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies the linker to be used") static var use_ld: Option
  @Option("-use-malloc", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allocate internal data structures using malloc (for memory debugging)") static var use_malloc: Option
  @Option("-use-tabs", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Use tabs for indentation.") static var use_tabs: Option
  @Option("-validate-tbd-against-ir=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<level>", helpText: "Compare the symbols in the IR against the TBD file that would be generated.") static var validate_tbd_against_ir_EQ: Option
  @Option("-value-recursion-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the maximum depth for direct recursion in value types") static var value_recursion_threshold: Option
  @Option("-verify-apply-fixes", .flag, attributes: [.frontend, .noDriver], helpText: "Like -verify, but updates the original source file") static var verify_apply_fixes: Option
  @Option("-verify-debug-info", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Verify the binary representation of debug output.") static var verify_debug_info: Option
  @Option("-verify-generic-signatures", .separate, attributes: [.frontend, .noDriver], metaVar: "<module-name>", helpText: "Verify the generic signatures in the given module") static var verify_generic_signatures: Option
  @Option("-verify-ignore-unknown", .flag, attributes: [.frontend, .noDriver], helpText: "Allow diagnostics for '<unknown>' location in verify mode") static var verify_ignore_unknown: Option
  @Option("-verify-syntax-tree", .flag, attributes: [.frontend, .noDriver], helpText: "Verify that no unknown nodes exist in the libSyntax tree") static var verify_syntax_tree: Option
  @Option("-verify-type-layout", .joinedOrSeparate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<type>", helpText: "Verify compile-time and runtime type layout information for type") static var verify_type_layout: Option
  @Option("-verify", .flag, attributes: [.frontend, .noDriver], helpText: "Verify diagnostics against expected-{error|warning|note} annotations") static var verify: Option
  @Option("-version", .flag, helpText: "Print version information and exit") static var version: Option
  @Option("--version", .flag, alias: Option.version, helpText: "Print version information and exit") static var version_: Option
  @Option("-vfsoverlay=", .joined, alias: Option.vfsoverlay) static var vfsoverlay_EQ: Option
  @Option("-vfsoverlay", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to VFS overlay file") static var vfsoverlay: Option
  @Option("-v", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Show commands to run and use verbose output") static var v: Option
  @Option("-warn-if-astscope-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Print a warning if ASTScope lookup is used") static var warn_if_astscope_lookup: Option
  @Option("-warn-implicit-overrides", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about implicit overrides of protocol members") static var warn_implicit_overrides: Option
  @Option("-warn-long-expression-type-checking=", .joined, alias: Option.warn_long_expression_type_checking, attributes: [.helpHidden, .frontend, .noDriver]) static var warn_long_expression_type_checking_EQ: Option
  @Option("-warn-long-expression-type-checking", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms") static var warn_long_expression_type_checking: Option
  @Option("-warn-long-function-bodies=", .joined, alias: Option.warn_long_function_bodies, attributes: [.helpHidden, .frontend, .noDriver]) static var warn_long_function_bodies_EQ: Option
  @Option("-warn-long-function-bodies", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms") static var warn_long_function_bodies: Option
  @Option("-warn-swift3-objc-inference-complete", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about deprecated @objc inference in Swift 3 for every declaration that will no longer be inferred as @objc in Swift 4") static var warn_swift3_objc_inference_complete: Option
  @Option("-warn-swift3-objc-inference-minimal", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about deprecated @objc inference in Swift 3 based on direct uses of the Objective-C entrypoint") static var warn_swift3_objc_inference_minimal: Option
  @Option("-warn-swift3-objc-inference", .flag, alias: Option.warn_swift3_objc_inference_complete, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild]) static var warn_swift3_objc_inference: Option
  @Option("-warnings-as-errors", .flag, attributes: [.frontend], helpText: "Treat warnings as errors") static var warnings_as_errors: Option
  @Option("-whole-module-optimization", .flag, attributes: [.frontend, .noInteractive], helpText: "Optimize input files together instead of individually") static var whole_module_optimization: Option
  @Option("-wmo", .flag, alias: Option.whole_module_optimization, attributes: [.helpHidden, .frontend, .noInteractive]) static var wmo: Option
  @Option("-working-directory=", .joined, alias: Option.working_directory) static var working_directory_EQ: Option
  @Option("-working-directory", .separate, metaVar: "<path>", helpText: "Resolve file paths relative to the specified directory") static var working_directory: Option
  @Option("-Xcc", .separate, attributes: [.frontend], metaVar: "<arg>", helpText: "Pass <arg> to the C/C++/Objective-C compiler") static var Xcc: Option
  @Option("-Xclang-linker", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to Clang when it is use for linking.") static var Xclang_linker: Option
  @Option("-Xfrontend", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to the Swift frontend") static var Xfrontend: Option
  @Option("-Xlinker", .separate, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies an option which should be passed to the linker") static var Xlinker: Option
  @Option("-Xllvm", .separate, attributes: [.helpHidden, .frontend], metaVar: "<arg>", helpText: "Pass <arg> to LLVM.") static var Xllvm: Option
  @Option("--", .remaining, attributes: [.frontend, .doesNotAffectIncrementalBuild]) static var _DASH_DASH: Option
}

extension Option {
  public static var allOptions: [Option] {
    return [
      Option.__HASH_HASH_HASH,
      Option._api_diff_data_dir,
      Option._api_diff_data_file,
      Option._enable_app_extension,
      Option._AssertConfig,
      Option._AssumeSingleThreaded,
      Option._autolink_force_load,
      Option._autolink_library,
      Option._build_module_from_parseable_interface,
      Option._bypass_batch_mode_checks,
      Option._check_onone_completeness,
      Option._code_complete_call_pattern_heuristics,
      Option._code_complete_inits_in_postfix_expr,
      Option._color_diagnostics,
      Option._compile_module_from_interface,
      Option._continue_building_after_errors,
      Option._crosscheck_unqualified_lookup,
      Option._c,
      Option._debug_assert_after_parse,
      Option._debug_assert_immediately,
      Option._debug_constraints_attempt,
      Option._debug_constraints_on_line_EQ,
      Option._debug_constraints_on_line,
      Option._debug_constraints,
      Option._debug_crash_after_parse,
      Option._debug_crash_immediately,
      Option._debug_cycles,
      Option._debug_diagnostic_names,
      Option._debug_forbid_typecheck_prefix,
      Option._debug_generic_signatures,
      Option._debug_info_format,
      Option._debug_info_store_invocation,
      Option._debug_prefix_map,
      Option._debug_time_compilation,
      Option._debug_time_expression_type_checking,
      Option._debug_time_function_bodies,
      Option._debugger_support,
      Option._debugger_testing_transform,
      Option._deprecated_integrated_repl,
      Option._diagnostics_editor_mode,
      Option._disable_access_control,
      Option._disable_arc_opts,
      Option._disable_astscope_lookup,
      Option._disable_autolink_framework,
      Option._disable_autolinking_runtime_compatibility_dynamic_replacements,
      Option._disable_autolinking_runtime_compatibility,
      Option._disable_availability_checking,
      Option._disable_batch_mode,
      Option._disable_bridging_pch,
      Option._disable_constraint_solver_performance_hacks,
      Option._disable_deserialization_recovery,
      Option._disable_diagnostic_passes,
      Option._disable_function_builder_one_way_constraints,
      Option._disable_incremental_llvm_codegeneration,
      Option._disable_legacy_type_info,
      Option._disable_llvm_optzns,
      Option._disable_llvm_slp_vectorizer,
      Option._disable_llvm_value_names,
      Option._disable_llvm_verify,
      Option._disable_migrator_fixits,
      Option._disable_modules_validate_system_headers,
      Option._disable_named_lazy_member_loading,
      Option._disable_nonfrozen_enum_exhaustivity_diagnostics,
      Option._disable_nskeyedarchiver_diagnostics,
      Option._disable_objc_attr_requires_foundation_module,
      Option._disable_objc_interop,
      Option._disable_parser_lookup,
      Option._disable_playground_transform,
      Option._disable_previous_implementation_calls_in_dynamic_replacements,
      Option._disable_reflection_metadata,
      Option._disable_reflection_names,
      Option._disable_serialization_nested_type_lookup_table,
      Option._disable_sil_ownership_verifier,
      Option._disable_sil_partial_apply,
      Option._disable_sil_perf_optzns,
      Option._disable_swift_bridge_attr,
      Option._disable_swift_specific_llvm_optzns,
      Option._disable_swift3_objc_inference,
      Option._disable_target_os_checking,
      Option._disable_testable_attr_requires_testable_module,
      Option._disable_tsan_inout_instrumentation,
      Option._disable_typo_correction,
      Option._disable_verify_exclusivity,
      Option._driver_always_rebuild_dependents,
      Option._driver_batch_count,
      Option._driver_batch_seed,
      Option._driver_batch_size_limit,
      Option._driver_emit_experimental_dependency_dot_file_after_every_import,
      Option._driver_filelist_threshold_EQ,
      Option._driver_filelist_threshold,
      Option._driver_force_response_files,
      Option._driver_mode,
      Option._driver_print_actions,
      Option._driver_print_bindings,
      Option._driver_print_derived_output_file_map,
      Option._driver_print_jobs,
      Option._driver_print_output_file_map,
      Option._driver_show_incremental,
      Option._driver_show_job_lifecycle,
      Option._driver_skip_execution,
      Option._driver_time_compilation,
      Option._driver_use_filelists,
      Option._driver_use_frontend_path,
      Option._driver_verify_experimental_dependency_graph_after_every_import,
      Option._dump_api_path,
      Option._dump_ast,
      Option._dump_clang_diagnostics,
      Option._dump_interface_hash,
      Option._dump_migration_states_dir,
      Option._dump_parse,
      Option._dump_scope_maps,
      Option._dump_type_info,
      Option._dump_type_refinement_contexts,
      Option._dump_usr,
      Option._D,
      Option._embed_bitcode_marker,
      Option._embed_bitcode,
      Option._emit_assembly,
      Option._emit_bc,
      Option._emit_dependencies_path,
      Option._emit_dependencies,
      Option._emit_executable,
      Option._emit_fixits_path,
      Option._emit_imported_modules,
      Option._emit_ir,
      Option._emit_library,
      Option._emit_loaded_module_trace_path_EQ,
      Option._emit_loaded_module_trace_path,
      Option._emit_loaded_module_trace,
      Option._emit_migrated_file_path,
      Option._emit_module_doc_path,
      Option._emit_module_doc,
      Option._emit_module_interface_path,
      Option._emit_module_interface,
      Option._emit_module_path_EQ,
      Option._emit_module_path,
      Option._emit_module,
      Option._emit_objc_header_path,
      Option._emit_objc_header,
      Option._emit_object,
      Option._emit_parseable_module_interface_path,
      Option._emit_parseable_module_interface,
      Option._emit_pch,
      Option._emit_reference_dependencies_path,
      Option._emit_reference_dependencies,
      Option._emit_remap_file_path,
      Option._emit_sibgen,
      Option._emit_sib,
      Option._emit_silgen,
      Option._emit_sil,
      Option._emit_sorted_sil,
      Option._stack_promotion_checks,
      Option._emit_syntax,
      Option._emit_tbd_path_EQ,
      Option._emit_tbd_path,
      Option._emit_tbd,
      Option._emit_verbose_sil,
      Option._enable_access_control,
      Option._enable_anonymous_context_mangled_names,
      Option._enable_astscope_lookup,
      Option._enable_batch_mode,
      Option._enable_bridging_pch,
      Option._enable_cxx_interop,
      Option._enable_deserialization_recovery,
      Option._enable_dynamic_replacement_chaining,
      Option._enable_experimental_dependencies,
      Option._enable_experimental_static_assert,
      Option._enable_function_builder_one_way_constraints,
      Option._enable_implicit_dynamic,
      Option._enable_infer_import_as_member,
      Option._enable_large_loadable_types,
      Option._enable_library_evolution,
      Option._enable_llvm_value_names,
      Option._enable_nonfrozen_enum_exhaustivity_diagnostics,
      Option._enable_nskeyedarchiver_diagnostics,
      Option._enable_objc_attr_requires_foundation_module,
      Option._enable_objc_interop,
      Option._enable_operator_designated_types,
      Option._enable_ownership_stripping_after_serialization,
      Option._enable_private_imports,
      Option._enable_resilience,
      Option._enable_sil_opaque_values,
      Option._enable_source_import,
      Option._enable_swift3_objc_inference,
      Option._enable_swiftcall,
      Option._enable_target_os_checking,
      Option._enable_testable_attr_requires_testable_module,
      Option._enable_testing,
      Option._enable_throw_without_try,
      Option._enable_verify_exclusivity,
      Option._enforce_exclusivity_EQ,
      Option._experimental_dependency_include_intrafile,
      Option._external_pass_pipeline_filename,
      Option._F_EQ,
      Option._filelist,
      Option._fixit_all,
      Option._force_public_linkage,
      Option._force_single_frontend_invocation,
      Option._framework,
      Option._Fsystem,
      Option._F,
      Option._gdwarf_types,
      Option._gline_tables_only,
      Option._gnone,
      Option._group_info_path,
      Option._debug_on_sil,
      Option._g,
      Option._help_hidden,
      Option._help_hidden_,
      Option._help,
      Option._help_,
      Option._h,
      Option._I_EQ,
      Option._import_cf_types,
      Option._import_module,
      Option._import_objc_header,
      Option._import_underlying_module,
      Option._in_place,
      Option._incremental,
      Option._indent_switch_case,
      Option._indent_width,
      Option._index_file_path,
      Option._index_file,
      Option._index_ignore_system_modules,
      Option._index_store_path,
      Option._index_system_modules,
      Option._interpret,
      Option._I,
      Option._i,
      Option._j,
      Option._L_EQ,
      Option._lazy_astscopes,
      Option._libc,
      Option._line_range,
      Option._link_objc_runtime,
      Option._lldb_repl,
      Option._L,
      Option._l,
      Option._merge_modules,
      Option._migrate_keep_objc_visibility,
      Option._migrator_update_sdk,
      Option._migrator_update_swift,
      Option._module_cache_path,
      Option._module_interface_preserve_types_as_written,
      Option._module_link_name_EQ,
      Option._module_link_name,
      Option._module_name_EQ,
      Option._module_name,
      Option._no_clang_module_breadcrumbs,
      Option._no_color_diagnostics,
      Option._no_link_objc_runtime,
      Option._no_serialize_debugging_options,
      Option._no_static_executable,
      Option._no_static_stdlib,
      Option._no_stdlib_rpath,
      Option._no_toolchain_stdlib_rpath,
      Option._nostdimport,
      Option._num_threads,
      Option._Onone,
      Option._Oplayground,
      Option._Osize,
      Option._Ounchecked,
      Option._output_file_map_EQ,
      Option._output_file_map,
      Option._output_filelist,
      Option._output_request_graphviz,
      Option._O,
      Option._o,
      Option._package_description_version,
      Option._parse_as_library,
      Option._parse_sil,
      Option._parse_stdlib,
      Option._parseable_output,
      Option._parse,
      Option._pc_macro,
      Option._pch_disable_validation,
      Option._pch_output_dir,
      Option._playground_high_performance,
      Option._playground,
      Option._prebuilt_module_cache_path_EQ,
      Option._prebuilt_module_cache_path,
      Option._primary_filelist,
      Option._primary_file,
      Option._print_ast,
      Option._print_clang_stats,
      Option._print_inst_counts,
      Option._print_llvm_inline_tree,
      Option._print_stats,
      Option._profile_coverage_mapping,
      Option._profile_generate,
      Option._profile_stats_entities,
      Option._profile_stats_events,
      Option._profile_use,
      Option._read_legacy_type_info_path_EQ,
      Option._RemoveRuntimeAsserts,
      Option._repl,
      Option._report_errors_to_debugger,
      Option._require_explicit_availability_target,
      Option._require_explicit_availability,
      Option._resolve_imports,
      Option._resource_dir,
      Option._Rmodule_interface_rebuild,
      Option._Rpass_missed_EQ,
      Option._Rpass_EQ,
      Option._runtime_compatibility_version,
      Option._sanitize_coverage_EQ,
      Option._sanitize_EQ,
      Option._save_optimization_record_path,
      Option._save_optimization_record,
      Option._save_temps,
      Option._sdk,
      Option._serialize_debugging_options,
      Option._serialize_diagnostics_path_EQ,
      Option._serialize_diagnostics_path,
      Option._serialize_diagnostics,
      Option._serialize_module_interface_dependency_hashes,
      Option._serialize_parseable_module_interface_dependency_hashes,
      Option._show_diagnostics_after_fatal,
      Option._sil_debug_serialization,
      Option._sil_inline_caller_benefit_reduction_factor,
      Option._sil_inline_threshold,
      Option._sil_merge_partial_modules,
      Option._sil_unroll_threshold,
      Option._sil_verify_all,
      Option._solver_disable_shrink,
      Option._solver_enable_operator_designated_types,
      Option._solver_expression_time_threshold_EQ,
      Option._solver_memory_threshold,
      Option._solver_shrink_unsolved_threshold,
      Option._stack_promotion_limit,
      Option._static_executable,
      Option._static_stdlib,
      Option._static,
      Option._stats_output_dir,
      Option._stress_astscope_lookup,
      Option._supplementary_output_file_map,
      Option._suppress_static_exclusivity_swap,
      Option._suppress_warnings,
      Option._swift_version,
      Option._switch_checking_invocation_threshold_EQ,
      Option._S,
      Option._tab_width,
      Option._target_cpu,
      Option._target_legacy_spelling,
      Option._target,
      Option._tbd_compatibility_version_EQ,
      Option._tbd_compatibility_version,
      Option._tbd_current_version_EQ,
      Option._tbd_current_version,
      Option._tbd_install_name_EQ,
      Option._tbd_install_name,
      Option._toolchain_stdlib_rpath,
      Option._tools_directory,
      Option._trace_stats_events,
      Option._track_system_dependencies,
      Option._triple,
      Option._type_info_dump_filter_EQ,
      Option._typecheck,
      Option._typo_correction_limit,
      Option._update_code,
      Option._use_jit,
      Option._use_ld,
      Option._use_malloc,
      Option._use_tabs,
      Option._validate_tbd_against_ir_EQ,
      Option._value_recursion_threshold,
      Option._verify_apply_fixes,
      Option._verify_debug_info,
      Option._verify_generic_signatures,
      Option._verify_ignore_unknown,
      Option._verify_syntax_tree,
      Option._verify_type_layout,
      Option._verify,
      Option._version,
      Option._version_,
      Option._vfsoverlay_EQ,
      Option._vfsoverlay,
      Option._v,
      Option._warn_if_astscope_lookup,
      Option._warn_implicit_overrides,
      Option._warn_long_expression_type_checking_EQ,
      Option._warn_long_expression_type_checking,
      Option._warn_long_function_bodies_EQ,
      Option._warn_long_function_bodies,
      Option._warn_swift3_objc_inference_complete,
      Option._warn_swift3_objc_inference_minimal,
      Option._warn_swift3_objc_inference,
      Option._warnings_as_errors,
      Option._whole_module_optimization,
      Option._wmo,
      Option._working_directory_EQ,
      Option._working_directory,
      Option._Xcc,
      Option._Xclang_linker,
      Option._Xfrontend,
      Option._Xlinker,
      Option._Xllvm,
      Option.__DASH_DASH,
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
