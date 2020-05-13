//===--------------- Options.swift - Swift Driver Options -----------------===//
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

extension Option {
  public static let INPUT: Option = Option("<input>", .input, attributes: [.argumentIsPath])
  public static let HASHHASHHASH: Option = Option("-###", .flag, alias: Option.driverPrintJobs)
  public static let apiDiffDataDir: Option = Option("-api-diff-data-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Load platform and version specific API migration data files from <path>. Ignored if -api-diff-data-file is specified.")
  public static let apiDiffDataFile: Option = Option("-api-diff-data-file", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "API migration data is from <path>")
  public static let enableAppExtension: Option = Option("-application-extension", .flag, attributes: [.frontend, .noInteractive], helpText: "Restrict code to those available for App Extensions")
  public static let AssertConfig: Option = Option("-assert-config", .separate, attributes: [.frontend], helpText: "Specify the assert_configuration replacement. Possible values are Debug, Release, Unchecked, DisableReplacement.")
  public static let AssumeSingleThreaded: Option = Option("-assume-single-threaded", .flag, attributes: [.helpHidden, .frontend], helpText: "Assume that code will be executed in a single-threaded environment")
  public static let autolinkForceLoad: Option = Option("-autolink-force-load", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Force ld to link against this module even if no symbols are used")
  public static let autolinkLibrary: Option = Option("-autolink-library", .separate, attributes: [.frontend, .noDriver], helpText: "Add dependent library")
  public static let avoidEmitModuleSourceInfo: Option = Option("-avoid-emit-module-source-info", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "don't emit Swift source info file")
  public static let bridgingHeaderDirectoryForPrint: Option = Option("-bridging-header-directory-for-print", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Directory for bridging header to be printed in compatibility header")
  public static let buildModuleFromParseableInterface: Option = Option("-build-module-from-parseable-interface", .flag, alias: Option.compileModuleFromInterface, attributes: [.helpHidden, .frontend, .noDriver], group: .modes)
  public static let buildRequestDependencyGraph: Option = Option("-build-request-dependency-graph", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Build request dependency graph")
  public static let bypassBatchModeChecks: Option = Option("-bypass-batch-mode-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Bypass checks for batch-mode errors.")
  public static let checkOnoneCompleteness: Option = Option("-check-onone-completeness", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print errors if the compile OnoneSupport module is missing symbols")
  public static let codeCompleteCallPatternHeuristics: Option = Option("-code-complete-call-pattern-heuristics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use heuristics to guess whether we want call pattern completions")
  public static let codeCompleteInitsInPostfixExpr: Option = Option("-code-complete-inits-in-postfix-expr", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Include initializers when completing a postfix expression")
  public static let colorDiagnostics: Option = Option("-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Print diagnostics in color")
  public static let compileModuleFromInterface: Option = Option("-compile-module-from-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Treat the (single) input as a swiftinterface and produce a module", group: .modes)
  public static let continueBuildingAfterErrors: Option = Option("-continue-building-after-errors", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Continue building, even after errors are encountered")
  public static let CrossModuleOptimization: Option = Option("-cross-module-optimization", .flag, attributes: [.helpHidden, .frontend], helpText: "Perform cross-module optimization")
  public static let crosscheckUnqualifiedLookup: Option = Option("-crosscheck-unqualified-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Compare legacy DeclContext- to ASTScope-based unqualified name lookup (for debugging)")
  public static let c: Option = Option("-c", .flag, alias: Option.emitObject, attributes: [.frontend, .noInteractive], group: .modes)
  public static let debugAssertAfterParse: Option = Option("-debug-assert-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure after parsing", group: .debugCrash)
  public static let debugAssertImmediately: Option = Option("-debug-assert-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure immediately", group: .debugCrash)
  public static let debugConstraintsAttempt: Option = Option("-debug-constraints-attempt", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint solver at a given attempt")
  public static let debugConstraintsOnLineEQ: Option = Option("-debug-constraints-on-line=", .joined, alias: Option.debugConstraintsOnLine, attributes: [.helpHidden, .frontend, .noDriver])
  public static let debugConstraintsOnLine: Option = Option("-debug-constraints-on-line", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<line>", helpText: "Debug the constraint solver for expressions on <line>")
  public static let debugConstraints: Option = Option("-debug-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint-based type checker")
  public static let debugCrashAfterParse: Option = Option("-debug-crash-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash after parsing", group: .debugCrash)
  public static let debugCrashImmediately: Option = Option("-debug-crash-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash immediately", group: .debugCrash)
  public static let debugCycles: Option = Option("-debug-cycles", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print out debug dumps when cycles are detected in evaluation")
  public static let debugDiagnosticNames: Option = Option("-debug-diagnostic-names", .flag, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Include diagnostic names when printing")
  public static let debugForbidTypecheckPrefix: Option = Option("-debug-forbid-typecheck-prefix", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Triggers llvm fatal_error if typechecker tries to typecheck a decl with the provided prefix name")
  public static let debugGenericSignatures: Option = Option("-debug-generic-signatures", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug generic signatures")
  public static let debugInfoFormat: Option = Option("-debug-info-format=", .joined, attributes: [.frontend], helpText: "Specify the debug info format type to either 'dwarf' or 'codeview'")
  public static let debugInfoStoreInvocation: Option = Option("-debug-info-store-invocation", .flag, attributes: [.frontend], helpText: "Emit the compiler invocation in the debug info.")
  public static let debugPrefixMap: Option = Option("-debug-prefix-map", .separate, attributes: [.frontend], helpText: "Remap source paths in debug info")
  public static let debugTimeCompilation: Option = Option("-debug-time-compilation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Prints the time taken by each compilation phase")
  public static let debugTimeExpressionTypeChecking: Option = Option("-debug-time-expression-type-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each expression")
  public static let debugTimeFunctionBodies: Option = Option("-debug-time-function-bodies", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each function body")
  public static let debuggerSupport: Option = Option("-debugger-support", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Process swift code as if running in the debugger")
  public static let debuggerTestingTransform: Option = Option("-debugger-testing-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Instrument the code with calls to an intrinsic that record the expected values of local variables so they can be compared against the results from the debugger.")
  public static let deprecatedIntegratedRepl: Option = Option("-deprecated-integrated-repl", .flag, attributes: [.frontend, .noBatch], group: .modes)
  public static let diagnosticDocumentationPath: Option = Option("-diagnostic-documentation-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Path to diagnostic documentation resources")
  public static let diagnosticsEditorMode: Option = Option("-diagnostics-editor-mode", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnostics will be used in editor")
  public static let disableAccessControl: Option = Option("-disable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't respect access control restrictions")
  public static let disableArcOpts: Option = Option("-disable-arc-opts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL ARC optimization passes.")
  public static let disableAstscopeLookup: Option = Option("-disable-astscope-lookup", .flag, attributes: [.frontend], helpText: "Disable ASTScope-based unqualified name lookup")
  public static let disableAutolinkFramework: Option = Option("-disable-autolink-framework", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable autolinking against the provided framework")
  public static let disableAutolinkingRuntimeCompatibilityDynamicReplacements: Option = Option("-disable-autolinking-runtime-compatibility-dynamic-replacements", .flag, attributes: [.frontend], helpText: "Do not use autolinking for the dynamic replacement runtime compatibility library")
  public static let disableAutolinkingRuntimeCompatibility: Option = Option("-disable-autolinking-runtime-compatibility", .flag, attributes: [.frontend], helpText: "Do not use autolinking for runtime compatibility libraries")
  public static let disableAvailabilityChecking: Option = Option("-disable-availability-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable checking for potentially unavailable APIs")
  public static let disableBatchMode: Option = Option("-disable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Disable combining frontend jobs into batches")
  public static let disableBridgingPch: Option = Option("-disable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Disable automatic generation of bridging PCH files")
  public static let disableClangimporterSourceImport: Option = Option("-disable-clangimporter-source-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable ClangImporter and forward all requests straight the DWARF importer.")
  public static let disableConcreteTypeMetadataMangledNameAccessors: Option = Option("-disable-concrete-type-metadata-mangled-name-accessors", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable concrete type metadata access by mangled name")
  public static let disableConstraintSolverPerformanceHacks: Option = Option("-disable-constraint-solver-performance-hacks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable all the hacks in the constraint solver")
  public static let disableCrossImportOverlays: Option = Option("-disable-cross-import-overlays", .flag, attributes: [.frontend, .noDriver], helpText: "Do not automatically import declared cross-import overlays.")
  public static let disableDebuggerShadowCopies: Option = Option("-disable-debugger-shadow-copies", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable debugger shadow copies of local variables.This option is only useful for testing the compiler.")
  public static let disableDeserializationRecovery: Option = Option("-disable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't attempt to recover from missing xrefs (etc) in swiftmodules")
  public static let disableDiagnosticPasses: Option = Option("-disable-diagnostic-passes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run diagnostic passes")
  public static let disableFineGrainedDependencies: Option = Option("-disable-fine-grained-dependencies", .flag, attributes: [.helpHidden, .frontend], helpText: "Don't be more selective about incremental recompilation")
  public static let disableGenericMetadataPrespecialization: Option = Option("-disable-generic-metadata-prespecialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not statically specialize metadata for generic types at types that are known to be used in source.")
  public static let disableIncrementalLlvmCodegeneration: Option = Option("-disable-incremental-llvm-codegen", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable incremental llvm code generation.")
  public static let disableInterfaceLockfile: Option = Option("-disable-interface-lock", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't lock interface file when building module")
  public static let disableInvalidEphemeralnessAsError: Option = Option("-disable-invalid-ephemeralness-as-error", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose invalid ephemeral to non-ephemeral conversions as warnings")
  public static let disableLegacyTypeInfo: Option = Option("-disable-legacy-type-info", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Completely disable legacy type layout")
  public static let disableLlvmOptzns: Option = Option("-disable-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run LLVM optimization passes")
  public static let disableLlvmSlpVectorizer: Option = Option("-disable-llvm-slp-vectorizer", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run LLVM SLP vectorizer")
  public static let disableLlvmValueNames: Option = Option("-disable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't add names to local values in LLVM IR")
  public static let disableLlvmVerify: Option = Option("-disable-llvm-verify", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run the LLVM IR verifier.")
  public static let disableMigratorFixits: Option = Option("-disable-migrator-fixits", .flag, attributes: [.frontend, .noInteractive], helpText: "Disable the Migrator phase which automatically applies fix-its")
  public static let disableModulesValidateSystemHeaders: Option = Option("-disable-modules-validate-system-headers", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating system headers in the Clang importer")
  public static let disableNamedLazyMemberLoading: Option = Option("-disable-named-lazy-member-loading", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable per-name lazy member loading")
  public static let disableNonfrozenEnumExhaustivityDiagnostics: Option = Option("-disable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow switches over non-frozen enums without catch-all cases")
  public static let disableNskeyedarchiverDiagnostics: Option = Option("-disable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow classes with unstable mangled names to adopt NSCoding")
  public static let disableObjcAttrRequiresFoundationModule: Option = Option("-disable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable requiring uses of @objc to require importing the Foundation module")
  public static let disableObjcInterop: Option = Option("-disable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable Objective-C interop code generation and config directives")
  public static let disableOnlyOneDependencyFile: Option = Option("-disable-only-one-dependency-file", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Disables incremental build optimization that only produces one dependencies file")
  public static let disableOssaOpts: Option = Option("-disable-ossa-opts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL OSSA optimization passes.")
  public static let disableParserLookup: Option = Option("-disable-parser-lookup", .flag, attributes: [.frontend], helpText: "Disable parser lookup & use ast scope lookup only (experimental)")
  public static let disablePlaygroundTransform: Option = Option("-disable-playground-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable playground transformation")
  public static let disablePreviousImplementationCallsInDynamicReplacements: Option = Option("-disable-previous-implementation-calls-in-dynamic-replacements", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable calling the previous implementation in dynamic replacements")
  public static let disableReflectionMetadata: Option = Option("-disable-reflection-metadata", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of reflection metadata for nominal types")
  public static let disableReflectionNames: Option = Option("-disable-reflection-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of names of stored properties and enum cases inreflection metadata")
  public static let disableRequestBasedIncrementalDependencies: Option = Option("-disable-request-based-incremental-dependencies", .flag, attributes: [.frontend], helpText: "Disable request-based name tracking")
  public static let disableSilOwnershipVerifier: Option = Option("-disable-sil-ownership-verifier", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not verify ownership invariants during SIL Verification ")
  public static let disableSilPartialApply: Option = Option("-disable-sil-partial-apply", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable use of partial_apply in SIL generation")
  public static let disableSilPerfOptzns: Option = Option("-disable-sil-perf-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL performance optimization passes")
  public static let disableSwiftBridgeAttr: Option = Option("-disable-swift-bridge-attr", .flag, attributes: [.helpHidden, .frontend], helpText: "Disable using the swift bridge attribute")
  public static let disableSwiftSpecificLlvmOptzns: Option = Option("-disable-swift-specific-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run Swift specific LLVM optimization passes.")
  public static let disableSwift3ObjcInference: Option = Option("-disable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 4 behavior)")
  public static let disableTargetOsChecking: Option = Option("-disable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking the target OS of serialized modules")
  public static let disableTestableAttrRequiresTestableModule: Option = Option("-disable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking of @testable")
  public static let disableTypeFingerprints: Option = Option("-disable-type-fingerprints", .flag, attributes: [.helpHidden, .frontend], helpText: "Disable per-nominal and extension body fingerprints")
  public static let disableTypeLayouts: Option = Option("-disable-type-layout", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable type layout based lowering")
  public static let disableTypoCorrection: Option = Option("-disable-typo-correction", .flag, attributes: [.frontend, .noDriver], helpText: "Disable typo correction")
  public static let disableVerifyExclusivity: Option = Option("-disable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diable verification of access markers used to enforce exclusivity.")
  public static let driverAlwaysRebuildDependents: Option = Option("-driver-always-rebuild-dependents", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Always rebuild dependents of files that have been modified", group: .internalDebug)
  public static let driverBatchCount: Option = Option("-driver-batch-count", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number of batch-mode partitions, rather than partitioning dynamically", group: .internalDebug)
  public static let driverBatchSeed: Option = Option("-driver-batch-seed", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given seed value to randomize batch-mode partitions", group: .internalDebug)
  public static let driverBatchSizeLimit: Option = Option("-driver-batch-size-limit", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number as the upper limit on dynamic batch-mode partition size", group: .internalDebug)
  public static let driverCompareIncrementalSchemesPathEQ: Option = Option("-driver-compare-incremental-schemes-path=", .joined, alias: Option.driverCompareIncrementalSchemesPath)
  public static let driverCompareIncrementalSchemesPath: Option = Option("-driver-compare-incremental-schemes-path", .separate, attributes: [.doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Path to use for machine-readable comparision")
  public static let driverCompareIncrementalSchemes: Option = Option("-driver-compare-incremental-schemes", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Print a simple message comparing dependencies with source ranges (w/ fallback)")
  public static let driverDumpCompiledSourceDiffs: Option = Option("-driver-dump-compiled-source-diffs", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Show the compiled source diffs read upon startup", group: .internalDebug)
  public static let driverDumpSwiftRanges: Option = Option("-driver-dump-swift-ranges", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Show the unparsed ranges read upon startup", group: .internalDebug)
  public static let driverEmitFineGrainedDependencyDotFileAfterEveryImport: Option = Option("-driver-emit-fine-grained-dependency-dot-file-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Emit dot files every time driver imports an fine-grained swiftdeps file.", group: .internalDebug)
  public static let driverFilelistThresholdEQ: Option = Option("-driver-filelist-threshold=", .joined, alias: Option.driverFilelistThreshold)
  public static let driverFilelistThreshold: Option = Option("-driver-filelist-threshold", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Pass input or output file names as filelists if there are more than <n>", group: .internalDebug)
  public static let driverForceResponseFiles: Option = Option("-driver-force-response-files", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Force the use of response files for testing", group: .internalDebug)
  public static let driverMode: Option = Option("--driver-mode=", .joined, attributes: [.helpHidden], helpText: "Set the driver mode to either 'swift' or 'swiftc'")
  public static let driverPrintActions: Option = Option("-driver-print-actions", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of actions to perform", group: .internalDebug)
  public static let driverPrintBindings: Option = Option("-driver-print-bindings", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of job inputs and outputs", group: .internalDebug)
  public static let driverPrintDerivedOutputFileMap: Option = Option("-driver-print-derived-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the derived output file map", group: .internalDebug)
  public static let driverPrintJobs: Option = Option("-driver-print-jobs", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of jobs to execute", group: .internalDebug)
  public static let driverPrintOutputFileMap: Option = Option("-driver-print-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the output file map", group: .internalDebug)
  public static let driverShowIncremental: Option = Option("-driver-show-incremental", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "With -v, dump information about why files are being rebuilt", group: .internalDebug)
  public static let driverShowJobLifecycle: Option = Option("-driver-show-job-lifecycle", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Show every step in the lifecycle of driver jobs", group: .internalDebug)
  public static let driverSkipExecution: Option = Option("-driver-skip-execution", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Skip execution of subtasks when performing compilation", group: .internalDebug)
  public static let driverTimeCompilation: Option = Option("-driver-time-compilation", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Prints the total time it took to execute all compilation tasks")
  public static let driverUseFilelists: Option = Option("-driver-use-filelists", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Pass input files as filelists whenever possible", group: .internalDebug)
  public static let driverUseFrontendPath: Option = Option("-driver-use-frontend-path", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given executable to perform compilations. Arguments can be passed as a ';' separated list", group: .internalDebug)
  public static let driverVerifyFineGrainedDependencyGraphAfterEveryImport: Option = Option("-driver-verify-fine-grained-dependency-graph-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Debug DriverGraph by verifying it after every import", group: .internalDebug)
  public static let dumpApiPath: Option = Option("-dump-api-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The path to output swift interface files for the compiled source files")
  public static let dumpAst: Option = Option("-dump-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and dump AST(s)", group: .modes)
  public static let dumpClangDiagnostics: Option = Option("-dump-clang-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dump Clang diagnostics to stderr")
  public static let dumpInterfaceHash: Option = Option("-dump-interface-hash", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Parse input file(s) and dump interface token hash(es)", group: .modes)
  public static let dumpMigrationStatesDir: Option = Option("-dump-migration-states-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Dump the input text, output text, and states for migration to <path>")
  public static let dumpParse: Option = Option("-dump-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s) and dump AST(s)", group: .modes)
  public static let dumpPcm: Option = Option("-dump-pcm", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Dump debugging information about a precompiled Clang module", group: .modes)
  public static let dumpScopeMaps: Option = Option("-dump-scope-maps", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<expanded-or-list-of-line:column>", helpText: "Parse and type-check input file(s) and dump the scope map(s)", group: .modes)
  public static let dumpTypeInfo: Option = Option("-dump-type-info", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Output YAML dump of fixed-size types from all imported modules", group: .modes)
  public static let dumpTypeRefinementContexts: Option = Option("-dump-type-refinement-contexts", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Type-check input file(s) and dump type refinement contexts(s)", group: .modes)
  public static let dumpUsr: Option = Option("-dump-usr", .flag, attributes: [.frontend, .noInteractive], helpText: "Dump USR for each declaration reference")
  public static let D: Option = Option("-D", .joinedOrSeparate, attributes: [.frontend], helpText: "Marks a conditional compilation flag as true")
  public static let embedBitcodeMarker: Option = Option("-embed-bitcode-marker", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed placeholder LLVM IR data as a marker")
  public static let embedBitcode: Option = Option("-embed-bitcode", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed LLVM IR bitcode as data")
  public static let embedTbdForModule: Option = Option("-embed-tbd-for-module", .separate, attributes: [.frontend], helpText: "Embed symbols from the module in the emitted tbd file")
  public static let emitAssembly: Option = Option("-emit-assembly", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit assembly file(s) (-S)", group: .modes)
  public static let emitBc: Option = Option("-emit-bc", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM BC file(s)", group: .modes)
  public static let emitCompiledSourcePath: Option = Option("-emit-compiled-source-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output compiled source to <path>")
  public static let emitCompiledSource: Option = Option("-emit-compiled-source", .flag, attributes: [.frontend, .noDriver], helpText: "Emit compiled source")
  public static let emitDependenciesPath: Option = Option("-emit-dependencies-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output basic Make-compatible dependencies file to <path>")
  public static let emitDependencies: Option = Option("-emit-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit basic Make-compatible dependencies files")
  public static let emitExecutable: Option = Option("-emit-executable", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a linked executable", group: .modes)
  public static let emitFineGrainedDependencySourcefileDotFiles: Option = Option("-emit-fine-grained-dependency-sourcefile-dot-files", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Emit dot files for every source file.", group: .internalDebug)
  public static let emitFixitsPath: Option = Option("-emit-fixits-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output compiler fixits as source edits to <path>")
  public static let emitImportedModules: Option = Option("-emit-imported-modules", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a list of the imported modules", group: .modes)
  public static let emitIr: Option = Option("-emit-ir", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM IR file(s)", group: .modes)
  public static let emitLdaddCfilePath: Option = Option("-emit-ldadd-cfile-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Generate .c file defining symbols to add back")
  public static let emitLibrary: Option = Option("-emit-library", .flag, attributes: [.noInteractive], helpText: "Emit a linked library", group: .modes)
  public static let emitLoadedModuleTracePathEQ: Option = Option("-emit-loaded-module-trace-path=", .joined, alias: Option.emitLoadedModuleTracePath, attributes: [.frontend, .noInteractive, .argumentIsPath])
  public static let emitLoadedModuleTracePath: Option = Option("-emit-loaded-module-trace-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Emit the loaded module trace JSON to <path>")
  public static let emitLoadedModuleTrace: Option = Option("-emit-loaded-module-trace", .flag, attributes: [.frontend, .noInteractive], helpText: "Emit a JSON file containing information about what modules were loaded")
  public static let emitMigratedFilePath: Option = Option("-emit-migrated-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the migrated source file to <path>")
  public static let emitModuleDocPath: Option = Option("-emit-module-doc-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output module documentation file <path>")
  public static let emitModuleDoc: Option = Option("-emit-module-doc", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a module documentation file based on documentation comments")
  public static let emitModuleInterfacePath: Option = Option("-emit-module-interface-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Output module interface file to <path>")
  public static let emitModuleInterface: Option = Option("-emit-module-interface", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Output module interface file")
  public static let emitModulePathEQ: Option = Option("-emit-module-path=", .joined, alias: Option.emitModulePath, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let emitModulePath: Option = Option("-emit-module-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit an importable module to <path>")
  public static let emitModuleSourceInfoPath: Option = Option("-emit-module-source-info-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Output module source info file to <path>")
  public static let emitModuleSourceInfo: Option = Option("-emit-module-source-info", .flag, attributes: [.frontend, .noDriver], helpText: "Output module source info file")
  public static let emitModule: Option = Option("-emit-module", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit an importable module")
  public static let emitObjcHeaderPath: Option = Option("-emit-objc-header-path", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit an Objective-C header file to <path>")
  public static let emitObjcHeader: Option = Option("-emit-objc-header", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit an Objective-C header file")
  public static let emitObject: Option = Option("-emit-object", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit object file(s) (-c)", group: .modes)
  public static let emitParseableModuleInterfacePath: Option = Option("-emit-parseable-module-interface-path", .separate, alias: Option.emitModuleInterfacePath, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let emitParseableModuleInterface: Option = Option("-emit-parseable-module-interface", .flag, alias: Option.emitModuleInterface, attributes: [.helpHidden, .noInteractive, .doesNotAffectIncrementalBuild])
  public static let emitPch: Option = Option("-emit-pch", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit PCH for imported Objective-C header file", group: .modes)
  public static let emitPcm: Option = Option("-emit-pcm", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a precompiled Clang module from a module map", group: .modes)
  public static let emitPrivateModuleInterfacePath: Option = Option("-emit-private-module-interface-path", .separate, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Output private module interface file to <path>")
  public static let emitReferenceDependenciesPath: Option = Option("-emit-reference-dependencies-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output Swift-style dependencies file to <path>")
  public static let emitReferenceDependencies: Option = Option("-emit-reference-dependencies", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a Swift-style dependencies file")
  public static let emitRemapFilePath: Option = Option("-emit-remap-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the replacement map describing Swift Migrator changes to <path>")
  public static let emitSibgen: Option = Option("-emit-sibgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + raw SIL file(s)", group: .modes)
  public static let emitSib: Option = Option("-emit-sib", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + canonical SIL file(s)", group: .modes)
  public static let emitSilgen: Option = Option("-emit-silgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit raw SIL file(s)", group: .modes)
  public static let emitSil: Option = Option("-emit-sil", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit canonical SIL file(s)", group: .modes)
  public static let emitSortedSil: Option = Option("-emit-sorted-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When printing SIL, print out all sil entities sorted by name to ease diffing")
  public static let stackPromotionChecks: Option = Option("-emit-stack-promotion-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit runtime checks for correct stack promotion of objects.")
  public static let emitSwiftRangesPath: Option = Option("-emit-swift-ranges-path", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Output unparsed ranges to <path>")
  public static let emitSwiftRanges: Option = Option("-emit-swift-ranges", .flag, attributes: [.frontend, .noDriver], helpText: "Emit unparsed source ranges")
  public static let emitSyntax: Option = Option("-emit-syntax", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Parse input file(s) and emit the Syntax tree(s) as JSON", group: .modes)
  public static let emitTbdPathEQ: Option = Option("-emit-tbd-path=", .joined, alias: Option.emitTbdPath, attributes: [.frontend, .noInteractive, .argumentIsPath])
  public static let emitTbdPath: Option = Option("-emit-tbd-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Emit the TBD file to <path>")
  public static let emitTbd: Option = Option("-emit-tbd", .flag, attributes: [.frontend, .noInteractive], helpText: "Emit a TBD file")
  public static let emitVerboseSil: Option = Option("-emit-verbose-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit locations during SIL emission")
  public static let enableAccessControl: Option = Option("-enable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Respect access control restrictions")
  public static let enableAnonymousContextMangledNames: Option = Option("-enable-anonymous-context-mangled-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable emission of mangled names in anonymous context descriptors")
  public static let enableAstscopeLookup: Option = Option("-enable-astscope-lookup", .flag, attributes: [.frontend], helpText: "Enable ASTScope-based unqualified name lookup")
  public static let enableBatchMode: Option = Option("-enable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Enable combining frontend jobs into batches")
  public static let enableBridgingPch: Option = Option("-enable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Enable automatic generation of bridging PCH files")
  public static let enableCrossImportOverlays: Option = Option("-enable-cross-import-overlays", .flag, attributes: [.frontend, .noDriver], helpText: "Automatically import declared cross-import overlays.")
  public static let enableCxxInterop: Option = Option("-enable-cxx-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable C++ interop code generation and config directives")
  public static let enableDeserializationRecovery: Option = Option("-enable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Attempt to recover from missing xrefs (etc) in swiftmodules")
  public static let enableDynamicReplacementChaining: Option = Option("-enable-dynamic-replacement-chaining", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable chaining of dynamic replacements")
  public static let enableExperimentalAdditiveArithmeticDerivation: Option = Option("-enable-experimental-additive-arithmetic-derivation", .flag, attributes: [.frontend], helpText: "Enable experimental 'AdditiveArithmetic' derived conformances")
  public static let enableExperimentalConcisePoundFile: Option = Option("-enable-experimental-concise-pound-file", .flag, attributes: [.frontend], helpText: "Enable experimental concise '#file' identifier")
  public static let enableExperimentalDiagnosticFormatting: Option = Option("-enable-experimental-diagnostic-formatting", .flag, attributes: [.frontend, .noDriver], helpText: "Enable experimental diagnostic formatting features.")
  public static let enableExperimentalForwardModeDifferentiation: Option = Option("-enable-experimental-forward-mode-differentiation", .flag, attributes: [.frontend], helpText: "Enable experimental forward mode differentiation")
  public static let enableExperimentalStaticAssert: Option = Option("-enable-experimental-static-assert", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental #assert")
  public static let enableFineGrainedDependencies: Option = Option("-enable-fine-grained-dependencies", .flag, attributes: [.helpHidden, .frontend], helpText: "Be more selective about incremental recompilation")
  public static let enableImplicitDynamic: Option = Option("-enable-implicit-dynamic", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add 'dynamic' to all declarations")
  public static let enableInferImportAsMember: Option = Option("-enable-infer-import-as-member", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Infer when a global could be imported as a member")
  public static let enableInvalidEphemeralnessAsError: Option = Option("-enable-invalid-ephemeralness-as-error", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose invalid ephemeral to non-ephemeral conversions as errors")
  public static let enableLargeLoadableTypes: Option = Option("-enable-large-loadable-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable Large Loadable types IRGen pass")
  public static let enableLibraryEvolution: Option = Option("-enable-library-evolution", .flag, attributes: [.frontend, .moduleInterface], helpText: "Build the module to allow binary-compatible library evolution")
  public static let enableLlvmValueNames: Option = Option("-enable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add names to local values in LLVM IR")
  public static let enableNonfrozenEnumExhaustivityDiagnostics: Option = Option("-enable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose switches over non-frozen enums without catch-all cases")
  public static let enableNskeyedarchiverDiagnostics: Option = Option("-enable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose classes with unstable mangled names adopting NSCoding")
  public static let enableObjcAttrRequiresFoundationModule: Option = Option("-enable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable requiring uses of @objc to require importing the Foundation module")
  public static let enableObjcInterop: Option = Option("-enable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable Objective-C interop code generation and config directives")
  public static let enableOnlyOneDependencyFile: Option = Option("-enable-only-one-dependency-file", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Enables incremental build optimization that only produces one dependencies file")
  public static let enableOperatorDesignatedTypes: Option = Option("-enable-operator-designated-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable operator designated types")
  public static let enableOwnershipStrippingAfterSerialization: Option = Option("-enable-ownership-stripping-after-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Strip ownership after serialization")
  public static let enablePrivateImports: Option = Option("-enable-private-imports", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal and private API to be accessed")
  public static let enableRequestBasedIncrementalDependencies: Option = Option("-enable-request-based-incremental-dependencies", .flag, attributes: [.frontend], helpText: "Enable request-based name tracking")
  public static let enableResilience: Option = Option("-enable-resilience", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Deprecated, use -enable-library-evolution instead")
  public static let enableSilOpaqueValues: Option = Option("-enable-sil-opaque-values", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable SIL Opaque Values")
  public static let enableSourceImport: Option = Option("-enable-source-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable importing of Swift source files")
  public static let enableSourceRangeDependencies: Option = Option("-enable-source-range-dependencies", .flag, helpText: "Try using source range information")
  public static let enableSpecDevirt: Option = Option("-enable-spec-devirt", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable speculative devirtualization pass.")
  public static let enableSubstSilFunctionTypesForFunctionValues: Option = Option("-enable-subst-sil-function-types-for-function-values", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use substituted function types for SIL type lowering of function values")
  public static let enableSwift3ObjcInference: Option = Option("-enable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable Swift 3's @objc inference rules for NSObject-derived classes and 'dynamic' members (emulates Swift 3 behavior)")
  public static let enableSwiftcall: Option = Option("-enable-swiftcall", .flag, attributes: [.frontend, .noDriver], helpText: "Enable the use of LLVM swiftcall support")
  public static let enableTargetOsChecking: Option = Option("-enable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking the target OS of serialized modules")
  public static let enableTestableAttrRequiresTestableModule: Option = Option("-enable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking of @testable")
  public static let enableTesting: Option = Option("-enable-testing", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal API to be accessed for testing")
  public static let enableThrowWithoutTry: Option = Option("-enable-throw-without-try", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow throwing function calls without 'try'")
  public static let enableTypeFingerprints: Option = Option("-enable-type-fingerprints", .flag, attributes: [.helpHidden, .frontend], helpText: "Enable per-nominal and extension body fingerprints")
  public static let enableTypeLayouts: Option = Option("-enable-type-layout", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable type layout based lowering")
  public static let enableVerifyExclusivity: Option = Option("-enable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable verification of access markers used to enforce exclusivity.")
  public static let enforceExclusivityEQ: Option = Option("-enforce-exclusivity=", .joined, attributes: [.frontend, .moduleInterface], metaVar: "<enforcement>", helpText: "Enforce law of exclusivity")
  public static let experimentalPrintFullConvention: Option = Option("-experimental-print-full-convention", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface, emit additional @convention arguments, regardless of whether they were written in the source")
  public static let experimentalSkipNonInlinableFunctionBodies: Option = Option("-experimental-skip-non-inlinable-function-bodies", .flag, attributes: [.helpHidden, .frontend], helpText: "Skip type-checking and SIL generation for non-inlinable function bodies")
  public static let externalPassPipelineFilename: Option = Option("-external-pass-pipeline-filename", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<pass_pipeline_file>", helpText: "Use the pass pipeline defined by <pass_pipeline_file>")
  public static let FEQ: Option = Option("-F=", .joined, alias: Option.F, attributes: [.frontend, .argumentIsPath])
  public static let filelist: Option = Option("-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify source inputs in a file rather than on the command line")
  public static let fineGrainedDependencyIncludeIntrafile: Option = Option("-fine-grained-dependency-include-intrafile", .flag, attributes: [.helpHidden, .frontend], helpText: "Include within-file dependencies.")
  public static let fixitAll: Option = Option("-fixit-all", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Apply all fixits from diagnostics without any filtering")
  public static let forcePublicLinkage: Option = Option("-force-public-linkage", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force public linkage for private symbols. Used by LLDB.")
  public static let forceSingleFrontendInvocation: Option = Option("-force-single-frontend-invocation", .flag, alias: Option.wholeModuleOptimization, attributes: [.helpHidden, .frontend, .noInteractive])
  public static let framework: Option = Option("-framework", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a framework which should be linked against", group: .linkerOption)
  public static let Fsystem: Option = Option("-Fsystem", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to system framework search path")
  public static let functionSections: Option = Option("-function-sections", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit functions to separate sections.")
  public static let F: Option = Option("-F", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to framework search path")
  public static let gdwarfTypes: Option = Option("-gdwarf-types", .flag, attributes: [.frontend], helpText: "Emit full DWARF type info.", group: .g)
  public static let glineTablesOnly: Option = Option("-gline-tables-only", .flag, attributes: [.frontend], helpText: "Emit minimal debug info for backtraces only", group: .g)
  public static let gnone: Option = Option("-gnone", .flag, attributes: [.frontend], helpText: "Don't emit debug info", group: .g)
  public static let groupInfoPath: Option = Option("-group-info-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The path to collect the group information of the compiled module")
  public static let debugOnSil: Option = Option("-gsil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Write the SIL into a file and generate debug-info to debug on SIL  level.")
  public static let g: Option = Option("-g", .flag, attributes: [.frontend], helpText: "Emit debug info. This is the preferred setting for debugging with LLDB.", group: .g)
  public static let helpHidden: Option = Option("-help-hidden", .flag, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options")
  public static let helpHidden_: Option = Option("--help-hidden", .flag, alias: Option.helpHidden, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options")
  public static let help: Option = Option("-help", .flag, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options")
  public static let help_: Option = Option("--help", .flag, alias: Option.help, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options")
  public static let h: Option = Option("-h", .flag, alias: Option.help)
  public static let IEQ: Option = Option("-I=", .joined, alias: Option.I, attributes: [.frontend, .argumentIsPath])
  public static let ignoreModuleSourceInfo: Option = Option("-ignore-module-source-info", .flag, attributes: [.frontend, .noDriver], helpText: "Avoid getting source location from .swiftsourceinfo files")
  public static let importCfTypes: Option = Option("-import-cf-types", .flag, attributes: [.helpHidden, .frontend], helpText: "Recognize and import CF types as class types")
  public static let importModule: Option = Option("-import-module", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Implicitly import the specified module")
  public static let importObjcHeader: Option = Option("-import-objc-header", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Implicitly imports an Objective-C header file")
  public static let importUnderlyingModule: Option = Option("-import-underlying-module", .flag, attributes: [.frontend, .noInteractive], helpText: "Implicitly imports the Objective-C half of a module")
  public static let inPlace: Option = Option("-in-place", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Overwrite input file with formatted file.", group: .codeFormatting)
  public static let incremental: Option = Option("-incremental", .flag, attributes: [.helpHidden, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Perform an incremental build if possible")
  public static let indentSwitchCase: Option = Option("-indent-switch-case", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Indent cases in switch statements.", group: .codeFormatting)
  public static let indentWidth: Option = Option("-indent-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Number of characters to indent.", group: .codeFormatting)
  public static let indexFilePath: Option = Option("-index-file-path", .separate, attributes: [.noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Produce index data for file <path>")
  public static let indexFile: Option = Option("-index-file", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Produce index data for a source file", group: .modes)
  public static let indexIgnoreStdlib: Option = Option("-index-ignore-stdlib", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Avoid emitting index data for the standard library.")
  public static let indexIgnoreSystemModules: Option = Option("-index-ignore-system-modules", .flag, attributes: [.noInteractive], helpText: "Avoid indexing system modules")
  public static let indexStorePath: Option = Option("-index-store-path", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<path>", helpText: "Store indexing data to <path>")
  public static let indexSystemModules: Option = Option("-index-system-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit index data for imported serialized swift system modules")
  public static let interpret: Option = Option("-interpret", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Immediate mode", group: .modes)
  public static let I: Option = Option("-I", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to the import search path")
  public static let i: Option = Option("-i", .flag, group: .modes)
  public static let j: Option = Option("-j", .joinedOrSeparate, attributes: [.doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Number of commands to execute in parallel")
  public static let LEQ: Option = Option("-L=", .joined, alias: Option.L, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let lazyAstscopes: Option = Option("-lazy-astscopes", .flag, attributes: [.frontend, .noDriver], helpText: "Build ASTScopes lazily")
  public static let libc: Option = Option("-libc", .separate, helpText: "libc runtime library to use")
  public static let lineRange: Option = Option("-line-range", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n:n>", helpText: "<start line>:<end line>. Formats a range of lines (1-based). Can only be used with one input file.", group: .codeFormatting)
  public static let linkObjcRuntime: Option = Option("-link-objc-runtime", .flag, attributes: [.doesNotAffectIncrementalBuild])
  public static let lldbRepl: Option = Option("-lldb-repl", .flag, attributes: [.helpHidden, .noBatch], helpText: "LLDB-enhanced REPL mode", group: .modes)
  public static let L: Option = Option("-L", .joinedOrSeparate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Add directory to library link search path", group: .linkerOption)
  public static let l: Option = Option("-l", .joined, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a library which should be linked against", group: .linkerOption)
  public static let mergeModules: Option = Option("-merge-modules", .flag, attributes: [.frontend, .noDriver], helpText: "Merge the input modules without otherwise processing them", group: .modes)
  public static let migrateKeepObjcVisibility: Option = Option("-migrate-keep-objc-visibility", .flag, attributes: [.frontend, .noInteractive], helpText: "When migrating, add '@objc' to declarations that would've been implicitly visible in Swift 3")
  public static let migratorUpdateSdk: Option = Option("-migrator-update-sdk", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.")
  public static let migratorUpdateSwift: Option = Option("-migrator-update-swift", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.")
  public static let moduleCachePath: Option = Option("-module-cache-path", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Specifies the Clang module cache path")
  public static let moduleInterfacePreserveTypesAsWritten: Option = Option("-module-interface-preserve-types-as-written", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface, preserve types as they were written in the source")
  public static let moduleLinkNameEQ: Option = Option("-module-link-name=", .joined, alias: Option.moduleLinkName, attributes: [.frontend])
  public static let moduleLinkName: Option = Option("-module-link-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Library to link against when using this module")
  public static let moduleNameEQ: Option = Option("-module-name=", .joined, alias: Option.moduleName, attributes: [.frontend])
  public static let moduleName: Option = Option("-module-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Name of the module to build")
  public static let noClangModuleBreadcrumbs: Option = Option("-no-clang-module-breadcrumbs", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't emit DWARF skeleton CUs for imported Clang modules. Use this when building a redistributable static archive.")
  public static let noColorDiagnostics: Option = Option("-no-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Do not print diagnostics in color")
  public static let noLinkObjcRuntime: Option = Option("-no-link-objc-runtime", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't link in additions to the Objective-C runtime")
  public static let noSerializeDebuggingOptions: Option = Option("-no-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Never serialize options for debugging (default: only for apps)")
  public static let noStaticExecutable: Option = Option("-no-static-executable", .flag, attributes: [.helpHidden], helpText: "Don't statically link the executable")
  public static let noStaticStdlib: Option = Option("-no-static-stdlib", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't statically link the Swift standard library")
  public static let noStdlibRpath: Option = Option("-no-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't add any rpath entries.")
  public static let noToolchainStdlibRpath: Option = Option("-no-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Do not add an rpath entry for the toolchain's standard library (default)")
  public static let noWarningsAsErrors: Option = Option("-no-warnings-as-errors", .flag, attributes: [.frontend], helpText: "Don't treat warnings as errors")
  public static let noWholeModuleOptimization: Option = Option("-no-whole-module-optimization", .flag, attributes: [.frontend, .noInteractive], helpText: "Disable optimizing input files together instead of individually")
  public static let nostdimport: Option = Option("-nostdimport", .flag, attributes: [.frontend], helpText: "Don't search the standard library import path for modules")
  public static let numThreads: Option = Option("-num-threads", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Enable multi-threading and specify number of threads")
  public static let Onone: Option = Option("-Onone", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile without any optimization", group: .O)
  public static let Oplayground: Option = Option("-Oplayground", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Compile with optimizations appropriate for a playground", group: .O)
  public static let Osize: Option = Option("-Osize", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and target small code size", group: .O)
  public static let Ounchecked: Option = Option("-Ounchecked", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and remove runtime safety checks", group: .O)
  public static let outputFileMapEQ: Option = Option("-output-file-map=", .joined, alias: Option.outputFileMap, attributes: [.noInteractive, .argumentIsPath])
  public static let outputFileMap: Option = Option("-output-file-map", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "A file which specifies the location of outputs")
  public static let outputFilelist: Option = Option("-output-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify outputs in a file rather than on the command line")
  public static let outputRequestGraphviz: Option = Option("-output-request-graphviz", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit GraphViz output visualizing the request dependency graph")
  public static let O: Option = Option("-O", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations", group: .O)
  public static let o: Option = Option("-o", .joinedOrSeparate, attributes: [.frontend, .noInteractive, .autolinkExtract, .moduleWrap, .indent, .argumentIsPath], metaVar: "<file>", helpText: "Write output to <file>")
  public static let packageDescriptionVersion: Option = Option("-package-description-version", .separate, attributes: [.helpHidden, .frontend, .moduleInterface], metaVar: "<vers>", helpText: "The version number to be applied on the input for the PackageDescription availability kind")
  public static let parseAsLibrary: Option = Option("-parse-as-library", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file(s) as libraries, not scripts")
  public static let parseSil: Option = Option("-parse-sil", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file as SIL code, not Swift source")
  public static let parseStdlib: Option = Option("-parse-stdlib", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Parse the input file(s) as the Swift standard library")
  public static let parseableOutput: Option = Option("-parseable-output", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit textual output in a parseable format")
  public static let parse: Option = Option("-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s)", group: .modes)
  public static let pcMacro: Option = Option("-pc-macro", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the 'program counter simulation' macro")
  public static let pchDisableValidation: Option = Option("-pch-disable-validation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating the persistent PCH")
  public static let pchOutputDir: Option = Option("-pch-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to persist automatically created precompiled bridging headers")
  public static let playgroundHighPerformance: Option = Option("-playground-high-performance", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Omit instrumentation that has a high runtime performance impact")
  public static let playground: Option = Option("-playground", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the playground semantics and transformation")
  public static let prebuiltModuleCachePathEQ: Option = Option("-prebuilt-module-cache-path=", .joined, alias: Option.prebuiltModuleCachePath, attributes: [.helpHidden, .frontend, .noDriver])
  public static let prebuiltModuleCachePath: Option = Option("-prebuilt-module-cache-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Directory of prebuilt modules for loading module interfaces")
  public static let prespecializeGenericMetadata: Option = Option("-prespecialize-generic-metadata", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Statically specialize metadata for generic types at types that are known to be used in source.")
  public static let previousModuleInstallnameMapFile: Option = Option("-previous-module-installname-map-file", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Path to a Json file indicating module name to installname map for @_originallyDefinedIn")
  public static let primaryFilelist: Option = Option("-primary-filelist", .separate, attributes: [.frontend, .noDriver], helpText: "Specify primary inputs in a file rather than on the command line")
  public static let primaryFile: Option = Option("-primary-file", .separate, attributes: [.frontend, .noDriver], helpText: "Produce output for this file, not the whole module")
  public static let printAst: Option = Option("-print-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and pretty print AST(s)", group: .modes)
  public static let printClangStats: Option = Option("-print-clang-stats", .flag, attributes: [.frontend, .noDriver], helpText: "Print Clang importer statistics")
  public static let printEducationalNotes: Option = Option("-print-educational-notes", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Include educational notes in printed diagnostic output, if available")
  public static let printInstCounts: Option = Option("-print-inst-counts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Before IRGen, count all the various SIL instructions. Must be used in conjunction with -print-stats.")
  public static let printLlvmInlineTree: Option = Option("-print-llvm-inline-tree", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print the LLVM inline tree.")
  public static let printStats: Option = Option("-print-stats", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print various statistics")
  public static let printTargetInfo: Option = Option("-print-target-info", .flag, attributes: [.frontend], metaVar: "<triple>", helpText: "Print target information for the given target <triple>, such as x86_64-apple-macos10.9")
  public static let profileCoverageMapping: Option = Option("-profile-coverage-mapping", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate coverage data for use with profiled execution counts")
  public static let profileGenerate: Option = Option("-profile-generate", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate instrumented code to collect execution counts")
  public static let profileStatsEntities: Option = Option("-profile-stats-entities", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir, subdivided by source entity")
  public static let profileStatsEvents: Option = Option("-profile-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir")
  public static let profileUse: Option = Option("-profile-use=", .commaJoined, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<profdata>", helpText: "Supply a profdata file to enable profile-guided optimization")
  public static let emitCrossImportRemarks: Option = Option("-Rcross-import", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit a remark if a cross-import of a module is triggered.")
  public static let readLegacyTypeInfoPathEQ: Option = Option("-read-legacy-type-info-path=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Read legacy type layout from the given path instead of default path")
  public static let RemoveRuntimeAsserts: Option = Option("-remove-runtime-asserts", .flag, attributes: [.frontend], helpText: "Remove runtime safety checks.")
  public static let repl: Option = Option("-repl", .flag, attributes: [.helpHidden, .frontend, .noBatch], helpText: "REPL mode (the default if there is no input file)", group: .modes)
  public static let reportErrorsToDebugger: Option = Option("-report-errors-to-debugger", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, will be removed in future versions.")
  public static let requireExplicitAvailabilityTarget: Option = Option("-require-explicit-availability-target", .separate, attributes: [.frontend, .noInteractive], metaVar: "<target>", helpText: "Suggest fix-its adding @available(<target>, *) to public declarations without availability")
  public static let requireExplicitAvailability: Option = Option("-require-explicit-availability", .flag, attributes: [.frontend, .noInteractive], helpText: "Require explicit availability on public declarations")
  public static let resolveImports: Option = Option("-resolve-imports", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and resolve imports in input file(s)", group: .modes)
  public static let resourceDir: Option = Option("-resource-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], metaVar: "</usr/lib/swift>", helpText: "The directory that holds the compiler resource files")
  public static let RmoduleInterfaceRebuild: Option = Option("-Rmodule-interface-rebuild", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emits a remark if an imported module needs to be re-compiled from its module interface")
  public static let RpassMissedEQ: Option = Option("-Rpass-missed=", .joined, attributes: [.frontend], helpText: "Report missed transformations by optimization passes whose name matches the given POSIX regular expression")
  public static let RpassEQ: Option = Option("-Rpass=", .joined, attributes: [.frontend], helpText: "Report performed transformations by optimization passes whose name matches the given POSIX regular expression")
  public static let runtimeCompatibilityVersion: Option = Option("-runtime-compatibility-version", .separate, attributes: [.frontend], helpText: "Link compatibility library for Swift runtime version, or 'none'")
  public static let sanitizeCoverageEQ: Option = Option("-sanitize-coverage=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<type>", helpText: "Specify the type of coverage instrumentation for Sanitizers and additional options separated by commas")
  public static let sanitizeRecoverEQ: Option = Option("-sanitize-recover=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<check>", helpText: "Specify which sanitizer runtime checks (see -sanitize=) will generate instrumentation that allows error recovery. Listed checks should be comma separated. Default behavior is to not allow error recovery.")
  public static let sanitizeEQ: Option = Option("-sanitize=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<check>", helpText: "Turn on runtime checks for erroneous behavior.")
  public static let saveOptimizationRecordPasses: Option = Option("-save-optimization-record-passes", .separate, attributes: [.frontend], metaVar: "<regex>", helpText: "Only include passes which match a specified regular expression inthe generated optimization record (by default, include all passes)")
  public static let saveOptimizationRecordPath: Option = Option("-save-optimization-record-path", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Specify the file name of any generated optimization record")
  public static let saveOptimizationRecordEQ: Option = Option("-save-optimization-record=", .joined, attributes: [.frontend], metaVar: "<format>", helpText: "Generate an optimization record file in a specific format (default: YAML)")
  public static let saveOptimizationRecord: Option = Option("-save-optimization-record", .flag, attributes: [.frontend], helpText: "Generate a YAML optimization record file")
  public static let saveTemps: Option = Option("-save-temps", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Save intermediate compilation results")
  public static let scanDependencies: Option = Option("-scan-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Scan dependencies of the given Swift sources", group: .modes)
  public static let sdk: Option = Option("-sdk", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<sdk>", helpText: "Compile against <sdk>")
  public static let serializeDebuggingOptions: Option = Option("-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Always serialize options for debugging (default: only for apps)")
  public static let serializeDiagnosticsPathEQ: Option = Option("-serialize-diagnostics-path=", .joined, alias: Option.serializeDiagnosticsPath, attributes: [.frontend, .noBatch, .doesNotAffectIncrementalBuild, .argumentIsPath])
  public static let serializeDiagnosticsPath: Option = Option("-serialize-diagnostics-path", .separate, attributes: [.frontend, .noBatch, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Emit a serialized diagnostics file to <path>")
  public static let serializeDiagnostics: Option = Option("-serialize-diagnostics", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Serialize diagnostics in a binary format")
  public static let serializeModuleInterfaceDependencyHashes: Option = Option("-serialize-module-interface-dependency-hashes", .flag, attributes: [.frontend, .noDriver])
  public static let serializeParseableModuleInterfaceDependencyHashes: Option = Option("-serialize-parseable-module-interface-dependency-hashes", .flag, alias: Option.serializeModuleInterfaceDependencyHashes, attributes: [.frontend, .noDriver])
  public static let showDiagnosticsAfterFatal: Option = Option("-show-diagnostics-after-fatal", .flag, attributes: [.frontend, .noDriver], helpText: "Keep emitting subsequent diagnostics after a fatal error")
  public static let silDebugSerialization: Option = Option("-sil-debug-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not eliminate functions in Mandatory Inlining/SILCombine dead functions. (for debugging only)")
  public static let silInlineCallerBenefitReductionFactor: Option = Option("-sil-inline-caller-benefit-reduction-factor", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<2>", helpText: "Controls the aggressiveness of performance inlining in -Osize mode by reducing the base benefits of a caller (lower value permits more inlining!)")
  public static let silInlineThreshold: Option = Option("-sil-inline-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<50>", helpText: "Controls the aggressiveness of performance inlining")
  public static let silMergePartialModules: Option = Option("-sil-merge-partial-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Merge SIL from all partial swiftmodules into the final module")
  public static let silUnrollThreshold: Option = Option("-sil-unroll-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<250>", helpText: "Controls the aggressiveness of loop unrolling")
  public static let silVerifyAll: Option = Option("-sil-verify-all", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Verify SIL after each transform")
  public static let silVerifyNone: Option = Option("-sil-verify-none", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Completely disable SIL verification")
  public static let solverDisableShrink: Option = Option("-solver-disable-shrink", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the shrink phase of expression type checking")
  public static let solverEnableOperatorDesignatedTypes: Option = Option("-solver-enable-operator-designated-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable operator designated types in constraint solver")
  public static let solverExpressionTimeThresholdEQ: Option = Option("-solver-expression-time-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver])
  public static let solverMemoryThreshold: Option = Option("-solver-memory-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the upper bound for memory consumption, in bytes, by the constraint solver")
  public static let solverShrinkUnsolvedThreshold: Option = Option("-solver-shrink-unsolved-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set The upper bound to number of sub-expressions unsolved before termination of the shrink phrase")
  public static let stackPromotionLimit: Option = Option("-stack-promotion-limit", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Limit the size of stack promoted objects to the provided number of bytes.")
  public static let staticExecutable: Option = Option("-static-executable", .flag, helpText: "Statically link the executable")
  public static let staticStdlib: Option = Option("-static-stdlib", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Statically link the Swift standard library")
  public static let `static`: Option = Option("-static", .flag, attributes: [.frontend, .noInteractive, .moduleInterface], helpText: "Make this module statically linkable and make the output of -emit-library a static library.")
  public static let statsOutputDir: Option = Option("-stats-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to write unified compilation-statistics files to")
  public static let stressAstscopeLookup: Option = Option("-stress-astscope-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Stress ASTScope-based unqualified name lookup (for testing)")
  public static let supplementaryOutputFileMap: Option = Option("-supplementary-output-file-map", .separate, attributes: [.frontend, .noDriver], helpText: "Specify supplementary outputs in a file rather than on the command line")
  public static let suppressStaticExclusivitySwap: Option = Option("-suppress-static-exclusivity-swap", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Suppress static violations of exclusive access with swap()")
  public static let suppressWarnings: Option = Option("-suppress-warnings", .flag, attributes: [.frontend], helpText: "Suppress all warnings")
  public static let swiftVersion: Option = Option("-swift-version", .separate, attributes: [.frontend, .moduleInterface], metaVar: "<vers>", helpText: "Interpret input according to a specific Swift language version number")
  public static let switchCheckingInvocationThresholdEQ: Option = Option("-switch-checking-invocation-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver])
  public static let S: Option = Option("-S", .flag, alias: Option.emitAssembly, attributes: [.frontend, .noInteractive], group: .modes)
  public static let tabWidth: Option = Option("-tab-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Width of tab character.", group: .codeFormatting)
  public static let targetCpu: Option = Option("-target-cpu", .separate, attributes: [.frontend, .moduleInterface], helpText: "Generate code for a particular CPU variant")
  public static let targetSdkVersion: Option = Option("-target-sdk-version", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The version of target SDK used for compilation")
  public static let targetVariantSdkVersion: Option = Option("-target-variant-sdk-version", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The version of target variant SDK used for compilation")
  public static let targetVariant: Option = Option("-target-variant", .separate, attributes: [.frontend], helpText: "Generate 'zippered' code for macCatalyst that can run on the specified variant target triple in addition to the main -target triple")
  public static let targetLegacySpelling: Option = Option("--target=", .joined, alias: Option.target, attributes: [.frontend])
  public static let target: Option = Option("-target", .separate, attributes: [.frontend, .moduleWrap, .moduleInterface], metaVar: "<triple>", helpText: "Generate code for the given target <triple>, such as x86_64-apple-macos10.9")
  public static let tbdCompatibilityVersionEQ: Option = Option("-tbd-compatibility-version=", .joined, alias: Option.tbdCompatibilityVersion, attributes: [.frontend, .noDriver])
  public static let tbdCompatibilityVersion: Option = Option("-tbd-compatibility-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The compatibility_version to use in an emitted TBD file")
  public static let tbdCurrentVersionEQ: Option = Option("-tbd-current-version=", .joined, alias: Option.tbdCurrentVersion, attributes: [.frontend, .noDriver])
  public static let tbdCurrentVersion: Option = Option("-tbd-current-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The current_version to use in an emitted TBD file")
  public static let tbdInstallNameEQ: Option = Option("-tbd-install_name=", .joined, alias: Option.tbdInstallName, attributes: [.frontend, .noDriver])
  public static let tbdInstallName: Option = Option("-tbd-install_name", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "The install_name to use in an emitted TBD file")
  public static let tbdIsInstallapi: Option = Option("-tbd-is-installapi", .flag, attributes: [.frontend, .noDriver], helpText: "If the TBD file should indicate it's being generated during InstallAPI")
  public static let toolchainStdlibRpath: Option = Option("-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Add an rpath entry for the toolchain's standard library, rather than the OS's")
  public static let toolsDirectory: Option = Option("-tools-directory", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<directory>", helpText: "Look for external executables (ld, clang, binutils) in <directory>")
  public static let traceStatsEvents: Option = Option("-trace-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Trace changes to stats in -stats-output-dir")
  public static let trackSystemDependencies: Option = Option("-track-system-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Track system dependencies while emitting Make-style dependencies")
  public static let triple: Option = Option("-triple", .separate, alias: Option.target, attributes: [.frontend, .noDriver])
  public static let typeInfoDumpFilterEQ: Option = Option("-type-info-dump-filter=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "One of 'all', 'resilient' or 'fragile'")
  public static let typecheck: Option = Option("-typecheck", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s)", group: .modes)
  public static let typoCorrectionLimit: Option = Option("-typo-correction-limit", .separate, attributes: [.helpHidden, .frontend], metaVar: "<n>", helpText: "Limit the number of times the compiler will attempt typo correction to <n>")
  public static let updateCode: Option = Option("-update-code", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Update Swift code")
  public static let useClangFunctionTypes: Option = Option("-use-clang-function-types", .flag, attributes: [.frontend, .noDriver], helpText: "Use stored Clang function types for computing canonical types.")
  public static let useJit: Option = Option("-use-jit", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Register Objective-C classes as if the JIT were in use")
  public static let useLd: Option = Option("-use-ld=", .joined, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies the linker to be used")
  public static let useMalloc: Option = Option("-use-malloc", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allocate internal data structures using malloc (for memory debugging)")
  public static let useTabs: Option = Option("-use-tabs", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Use tabs for indentation.", group: .codeFormatting)
  public static let validateTbdAgainstIrEQ: Option = Option("-validate-tbd-against-ir=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<level>", helpText: "Compare the symbols in the IR against the TBD file that would be generated.")
  public static let valueRecursionThreshold: Option = Option("-value-recursion-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the maximum depth for direct recursion in value types")
  public static let verifyAllSubstitutionMaps: Option = Option("-verify-all-substitution-maps", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Verify all SubstitutionMaps on construction")
  public static let verifyApplyFixes: Option = Option("-verify-apply-fixes", .flag, attributes: [.frontend, .noDriver], helpText: "Like -verify, but updates the original source file")
  public static let verifyDebugInfo: Option = Option("-verify-debug-info", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Verify the binary representation of debug output.")
  public static let verifyGenericSignatures: Option = Option("-verify-generic-signatures", .separate, attributes: [.frontend, .noDriver], metaVar: "<module-name>", helpText: "Verify the generic signatures in the given module")
  public static let verifyIgnoreUnknown: Option = Option("-verify-ignore-unknown", .flag, attributes: [.frontend, .noDriver], helpText: "Allow diagnostics for '<unknown>' location in verify mode")
  public static let verifyIncrementalDependencies: Option = Option("-verify-incremental-dependencies", .flag, attributes: [.helpHidden, .frontend], helpText: "Enable the dependency verifier for each frontend job")
  public static let verifySyntaxTree: Option = Option("-verify-syntax-tree", .flag, attributes: [.frontend, .noDriver], helpText: "Verify that no unknown nodes exist in the libSyntax tree")
  public static let verifyTypeLayout: Option = Option("-verify-type-layout", .joinedOrSeparate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<type>", helpText: "Verify compile-time and runtime type layout information for type")
  public static let verify: Option = Option("-verify", .flag, attributes: [.frontend, .noDriver], helpText: "Verify diagnostics against expected-{error|warning|note} annotations")
  public static let version: Option = Option("-version", .flag, helpText: "Print version information and exit")
  public static let version_: Option = Option("--version", .flag, alias: Option.version, helpText: "Print version information and exit")
  public static let vfsoverlayEQ: Option = Option("-vfsoverlay=", .joined, alias: Option.vfsoverlay)
  public static let vfsoverlay: Option = Option("-vfsoverlay", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to VFS overlay file")
  public static let v: Option = Option("-v", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Show commands to run and use verbose output")
  public static let warnIfAstscopeLookup: Option = Option("-warn-if-astscope-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Print a warning if ASTScope lookup is used")
  public static let warnImplicitOverrides: Option = Option("-warn-implicit-overrides", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about implicit overrides of protocol members")
  public static let warnLongExpressionTypeCheckingEQ: Option = Option("-warn-long-expression-type-checking=", .joined, alias: Option.warnLongExpressionTypeChecking, attributes: [.helpHidden, .frontend, .noDriver])
  public static let warnLongExpressionTypeChecking: Option = Option("-warn-long-expression-type-checking", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms")
  public static let warnLongFunctionBodiesEQ: Option = Option("-warn-long-function-bodies=", .joined, alias: Option.warnLongFunctionBodies, attributes: [.helpHidden, .frontend, .noDriver])
  public static let warnLongFunctionBodies: Option = Option("-warn-long-function-bodies", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms")
  public static let warnSwift3ObjcInferenceComplete: Option = Option("-warn-swift3-objc-inference-complete", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about deprecated @objc inference in Swift 3 for every declaration that will no longer be inferred as @objc in Swift 4")
  public static let warnSwift3ObjcInferenceMinimal: Option = Option("-warn-swift3-objc-inference-minimal", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about deprecated @objc inference in Swift 3 based on direct uses of the Objective-C entrypoint")
  public static let warnSwift3ObjcInference: Option = Option("-warn-swift3-objc-inference", .flag, alias: Option.warnSwift3ObjcInferenceComplete, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild])
  public static let warningsAsErrors: Option = Option("-warnings-as-errors", .flag, attributes: [.frontend], helpText: "Treat warnings as errors")
  public static let wholeModuleOptimization: Option = Option("-whole-module-optimization", .flag, attributes: [.frontend, .noInteractive], helpText: "Optimize input files together instead of individually")
  public static let wmo: Option = Option("-wmo", .flag, alias: Option.wholeModuleOptimization, attributes: [.helpHidden, .frontend, .noInteractive])
  public static let workingDirectoryEQ: Option = Option("-working-directory=", .joined, alias: Option.workingDirectory)
  public static let workingDirectory: Option = Option("-working-directory", .separate, metaVar: "<path>", helpText: "Resolve file paths relative to the specified directory")
  public static let Xcc: Option = Option("-Xcc", .separate, attributes: [.frontend], metaVar: "<arg>", helpText: "Pass <arg> to the C/C++/Objective-C compiler")
  public static let XclangLinker: Option = Option("-Xclang-linker", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to Clang when it is use for linking.")
  public static let Xfrontend: Option = Option("-Xfrontend", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to the Swift frontend")
  public static let Xlinker: Option = Option("-Xlinker", .separate, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies an option which should be passed to the linker")
  public static let Xllvm: Option = Option("-Xllvm", .separate, attributes: [.helpHidden, .frontend], metaVar: "<arg>", helpText: "Pass <arg> to LLVM.")
  public static let DASHDASH: Option = Option("--", .remaining, attributes: [.frontend, .doesNotAffectIncrementalBuild])
}

extension Option {
  public static var allOptions: [Option] {
    return [
      Option.INPUT,
      Option.HASHHASHHASH,
      Option.apiDiffDataDir,
      Option.apiDiffDataFile,
      Option.enableAppExtension,
      Option.AssertConfig,
      Option.AssumeSingleThreaded,
      Option.autolinkForceLoad,
      Option.autolinkLibrary,
      Option.avoidEmitModuleSourceInfo,
      Option.bridgingHeaderDirectoryForPrint,
      Option.buildModuleFromParseableInterface,
      Option.buildRequestDependencyGraph,
      Option.bypassBatchModeChecks,
      Option.checkOnoneCompleteness,
      Option.codeCompleteCallPatternHeuristics,
      Option.codeCompleteInitsInPostfixExpr,
      Option.colorDiagnostics,
      Option.compileModuleFromInterface,
      Option.continueBuildingAfterErrors,
      Option.CrossModuleOptimization,
      Option.crosscheckUnqualifiedLookup,
      Option.c,
      Option.debugAssertAfterParse,
      Option.debugAssertImmediately,
      Option.debugConstraintsAttempt,
      Option.debugConstraintsOnLineEQ,
      Option.debugConstraintsOnLine,
      Option.debugConstraints,
      Option.debugCrashAfterParse,
      Option.debugCrashImmediately,
      Option.debugCycles,
      Option.debugDiagnosticNames,
      Option.debugForbidTypecheckPrefix,
      Option.debugGenericSignatures,
      Option.debugInfoFormat,
      Option.debugInfoStoreInvocation,
      Option.debugPrefixMap,
      Option.debugTimeCompilation,
      Option.debugTimeExpressionTypeChecking,
      Option.debugTimeFunctionBodies,
      Option.debuggerSupport,
      Option.debuggerTestingTransform,
      Option.deprecatedIntegratedRepl,
      Option.diagnosticDocumentationPath,
      Option.diagnosticsEditorMode,
      Option.disableAccessControl,
      Option.disableArcOpts,
      Option.disableAstscopeLookup,
      Option.disableAutolinkFramework,
      Option.disableAutolinkingRuntimeCompatibilityDynamicReplacements,
      Option.disableAutolinkingRuntimeCompatibility,
      Option.disableAvailabilityChecking,
      Option.disableBatchMode,
      Option.disableBridgingPch,
      Option.disableClangimporterSourceImport,
      Option.disableConcreteTypeMetadataMangledNameAccessors,
      Option.disableConstraintSolverPerformanceHacks,
      Option.disableCrossImportOverlays,
      Option.disableDebuggerShadowCopies,
      Option.disableDeserializationRecovery,
      Option.disableDiagnosticPasses,
      Option.disableFineGrainedDependencies,
      Option.disableGenericMetadataPrespecialization,
      Option.disableIncrementalLlvmCodegeneration,
      Option.disableInterfaceLockfile,
      Option.disableInvalidEphemeralnessAsError,
      Option.disableLegacyTypeInfo,
      Option.disableLlvmOptzns,
      Option.disableLlvmSlpVectorizer,
      Option.disableLlvmValueNames,
      Option.disableLlvmVerify,
      Option.disableMigratorFixits,
      Option.disableModulesValidateSystemHeaders,
      Option.disableNamedLazyMemberLoading,
      Option.disableNonfrozenEnumExhaustivityDiagnostics,
      Option.disableNskeyedarchiverDiagnostics,
      Option.disableObjcAttrRequiresFoundationModule,
      Option.disableObjcInterop,
      Option.disableOnlyOneDependencyFile,
      Option.disableOssaOpts,
      Option.disableParserLookup,
      Option.disablePlaygroundTransform,
      Option.disablePreviousImplementationCallsInDynamicReplacements,
      Option.disableReflectionMetadata,
      Option.disableReflectionNames,
      Option.disableRequestBasedIncrementalDependencies,
      Option.disableSilOwnershipVerifier,
      Option.disableSilPartialApply,
      Option.disableSilPerfOptzns,
      Option.disableSwiftBridgeAttr,
      Option.disableSwiftSpecificLlvmOptzns,
      Option.disableSwift3ObjcInference,
      Option.disableTargetOsChecking,
      Option.disableTestableAttrRequiresTestableModule,
      Option.disableTypeFingerprints,
      Option.disableTypeLayouts,
      Option.disableTypoCorrection,
      Option.disableVerifyExclusivity,
      Option.driverAlwaysRebuildDependents,
      Option.driverBatchCount,
      Option.driverBatchSeed,
      Option.driverBatchSizeLimit,
      Option.driverCompareIncrementalSchemesPathEQ,
      Option.driverCompareIncrementalSchemesPath,
      Option.driverCompareIncrementalSchemes,
      Option.driverDumpCompiledSourceDiffs,
      Option.driverDumpSwiftRanges,
      Option.driverEmitFineGrainedDependencyDotFileAfterEveryImport,
      Option.driverFilelistThresholdEQ,
      Option.driverFilelistThreshold,
      Option.driverForceResponseFiles,
      Option.driverMode,
      Option.driverPrintActions,
      Option.driverPrintBindings,
      Option.driverPrintDerivedOutputFileMap,
      Option.driverPrintJobs,
      Option.driverPrintOutputFileMap,
      Option.driverShowIncremental,
      Option.driverShowJobLifecycle,
      Option.driverSkipExecution,
      Option.driverTimeCompilation,
      Option.driverUseFilelists,
      Option.driverUseFrontendPath,
      Option.driverVerifyFineGrainedDependencyGraphAfterEveryImport,
      Option.dumpApiPath,
      Option.dumpAst,
      Option.dumpClangDiagnostics,
      Option.dumpInterfaceHash,
      Option.dumpMigrationStatesDir,
      Option.dumpParse,
      Option.dumpPcm,
      Option.dumpScopeMaps,
      Option.dumpTypeInfo,
      Option.dumpTypeRefinementContexts,
      Option.dumpUsr,
      Option.D,
      Option.embedBitcodeMarker,
      Option.embedBitcode,
      Option.embedTbdForModule,
      Option.emitAssembly,
      Option.emitBc,
      Option.emitCompiledSourcePath,
      Option.emitCompiledSource,
      Option.emitDependenciesPath,
      Option.emitDependencies,
      Option.emitExecutable,
      Option.emitFineGrainedDependencySourcefileDotFiles,
      Option.emitFixitsPath,
      Option.emitImportedModules,
      Option.emitIr,
      Option.emitLdaddCfilePath,
      Option.emitLibrary,
      Option.emitLoadedModuleTracePathEQ,
      Option.emitLoadedModuleTracePath,
      Option.emitLoadedModuleTrace,
      Option.emitMigratedFilePath,
      Option.emitModuleDocPath,
      Option.emitModuleDoc,
      Option.emitModuleInterfacePath,
      Option.emitModuleInterface,
      Option.emitModulePathEQ,
      Option.emitModulePath,
      Option.emitModuleSourceInfoPath,
      Option.emitModuleSourceInfo,
      Option.emitModule,
      Option.emitObjcHeaderPath,
      Option.emitObjcHeader,
      Option.emitObject,
      Option.emitParseableModuleInterfacePath,
      Option.emitParseableModuleInterface,
      Option.emitPch,
      Option.emitPcm,
      Option.emitPrivateModuleInterfacePath,
      Option.emitReferenceDependenciesPath,
      Option.emitReferenceDependencies,
      Option.emitRemapFilePath,
      Option.emitSibgen,
      Option.emitSib,
      Option.emitSilgen,
      Option.emitSil,
      Option.emitSortedSil,
      Option.stackPromotionChecks,
      Option.emitSwiftRangesPath,
      Option.emitSwiftRanges,
      Option.emitSyntax,
      Option.emitTbdPathEQ,
      Option.emitTbdPath,
      Option.emitTbd,
      Option.emitVerboseSil,
      Option.enableAccessControl,
      Option.enableAnonymousContextMangledNames,
      Option.enableAstscopeLookup,
      Option.enableBatchMode,
      Option.enableBridgingPch,
      Option.enableCrossImportOverlays,
      Option.enableCxxInterop,
      Option.enableDeserializationRecovery,
      Option.enableDynamicReplacementChaining,
      Option.enableExperimentalAdditiveArithmeticDerivation,
      Option.enableExperimentalConcisePoundFile,
      Option.enableExperimentalDiagnosticFormatting,
      Option.enableExperimentalForwardModeDifferentiation,
      Option.enableExperimentalStaticAssert,
      Option.enableFineGrainedDependencies,
      Option.enableImplicitDynamic,
      Option.enableInferImportAsMember,
      Option.enableInvalidEphemeralnessAsError,
      Option.enableLargeLoadableTypes,
      Option.enableLibraryEvolution,
      Option.enableLlvmValueNames,
      Option.enableNonfrozenEnumExhaustivityDiagnostics,
      Option.enableNskeyedarchiverDiagnostics,
      Option.enableObjcAttrRequiresFoundationModule,
      Option.enableObjcInterop,
      Option.enableOnlyOneDependencyFile,
      Option.enableOperatorDesignatedTypes,
      Option.enableOwnershipStrippingAfterSerialization,
      Option.enablePrivateImports,
      Option.enableRequestBasedIncrementalDependencies,
      Option.enableResilience,
      Option.enableSilOpaqueValues,
      Option.enableSourceImport,
      Option.enableSourceRangeDependencies,
      Option.enableSpecDevirt,
      Option.enableSubstSilFunctionTypesForFunctionValues,
      Option.enableSwift3ObjcInference,
      Option.enableSwiftcall,
      Option.enableTargetOsChecking,
      Option.enableTestableAttrRequiresTestableModule,
      Option.enableTesting,
      Option.enableThrowWithoutTry,
      Option.enableTypeFingerprints,
      Option.enableTypeLayouts,
      Option.enableVerifyExclusivity,
      Option.enforceExclusivityEQ,
      Option.experimentalPrintFullConvention,
      Option.experimentalSkipNonInlinableFunctionBodies,
      Option.externalPassPipelineFilename,
      Option.FEQ,
      Option.filelist,
      Option.fineGrainedDependencyIncludeIntrafile,
      Option.fixitAll,
      Option.forcePublicLinkage,
      Option.forceSingleFrontendInvocation,
      Option.framework,
      Option.Fsystem,
      Option.functionSections,
      Option.F,
      Option.gdwarfTypes,
      Option.glineTablesOnly,
      Option.gnone,
      Option.groupInfoPath,
      Option.debugOnSil,
      Option.g,
      Option.helpHidden,
      Option.helpHidden_,
      Option.help,
      Option.help_,
      Option.h,
      Option.IEQ,
      Option.ignoreModuleSourceInfo,
      Option.importCfTypes,
      Option.importModule,
      Option.importObjcHeader,
      Option.importUnderlyingModule,
      Option.inPlace,
      Option.incremental,
      Option.indentSwitchCase,
      Option.indentWidth,
      Option.indexFilePath,
      Option.indexFile,
      Option.indexIgnoreStdlib,
      Option.indexIgnoreSystemModules,
      Option.indexStorePath,
      Option.indexSystemModules,
      Option.interpret,
      Option.I,
      Option.i,
      Option.j,
      Option.LEQ,
      Option.lazyAstscopes,
      Option.libc,
      Option.lineRange,
      Option.linkObjcRuntime,
      Option.lldbRepl,
      Option.L,
      Option.l,
      Option.mergeModules,
      Option.migrateKeepObjcVisibility,
      Option.migratorUpdateSdk,
      Option.migratorUpdateSwift,
      Option.moduleCachePath,
      Option.moduleInterfacePreserveTypesAsWritten,
      Option.moduleLinkNameEQ,
      Option.moduleLinkName,
      Option.moduleNameEQ,
      Option.moduleName,
      Option.noClangModuleBreadcrumbs,
      Option.noColorDiagnostics,
      Option.noLinkObjcRuntime,
      Option.noSerializeDebuggingOptions,
      Option.noStaticExecutable,
      Option.noStaticStdlib,
      Option.noStdlibRpath,
      Option.noToolchainStdlibRpath,
      Option.noWarningsAsErrors,
      Option.noWholeModuleOptimization,
      Option.nostdimport,
      Option.numThreads,
      Option.Onone,
      Option.Oplayground,
      Option.Osize,
      Option.Ounchecked,
      Option.outputFileMapEQ,
      Option.outputFileMap,
      Option.outputFilelist,
      Option.outputRequestGraphviz,
      Option.O,
      Option.o,
      Option.packageDescriptionVersion,
      Option.parseAsLibrary,
      Option.parseSil,
      Option.parseStdlib,
      Option.parseableOutput,
      Option.parse,
      Option.pcMacro,
      Option.pchDisableValidation,
      Option.pchOutputDir,
      Option.playgroundHighPerformance,
      Option.playground,
      Option.prebuiltModuleCachePathEQ,
      Option.prebuiltModuleCachePath,
      Option.prespecializeGenericMetadata,
      Option.previousModuleInstallnameMapFile,
      Option.primaryFilelist,
      Option.primaryFile,
      Option.printAst,
      Option.printClangStats,
      Option.printEducationalNotes,
      Option.printInstCounts,
      Option.printLlvmInlineTree,
      Option.printStats,
      Option.printTargetInfo,
      Option.profileCoverageMapping,
      Option.profileGenerate,
      Option.profileStatsEntities,
      Option.profileStatsEvents,
      Option.profileUse,
      Option.emitCrossImportRemarks,
      Option.readLegacyTypeInfoPathEQ,
      Option.RemoveRuntimeAsserts,
      Option.repl,
      Option.reportErrorsToDebugger,
      Option.requireExplicitAvailabilityTarget,
      Option.requireExplicitAvailability,
      Option.resolveImports,
      Option.resourceDir,
      Option.RmoduleInterfaceRebuild,
      Option.RpassMissedEQ,
      Option.RpassEQ,
      Option.runtimeCompatibilityVersion,
      Option.sanitizeCoverageEQ,
      Option.sanitizeRecoverEQ,
      Option.sanitizeEQ,
      Option.saveOptimizationRecordPasses,
      Option.saveOptimizationRecordPath,
      Option.saveOptimizationRecordEQ,
      Option.saveOptimizationRecord,
      Option.saveTemps,
      Option.scanDependencies,
      Option.sdk,
      Option.serializeDebuggingOptions,
      Option.serializeDiagnosticsPathEQ,
      Option.serializeDiagnosticsPath,
      Option.serializeDiagnostics,
      Option.serializeModuleInterfaceDependencyHashes,
      Option.serializeParseableModuleInterfaceDependencyHashes,
      Option.showDiagnosticsAfterFatal,
      Option.silDebugSerialization,
      Option.silInlineCallerBenefitReductionFactor,
      Option.silInlineThreshold,
      Option.silMergePartialModules,
      Option.silUnrollThreshold,
      Option.silVerifyAll,
      Option.silVerifyNone,
      Option.solverDisableShrink,
      Option.solverEnableOperatorDesignatedTypes,
      Option.solverExpressionTimeThresholdEQ,
      Option.solverMemoryThreshold,
      Option.solverShrinkUnsolvedThreshold,
      Option.stackPromotionLimit,
      Option.staticExecutable,
      Option.staticStdlib,
      Option.`static`,
      Option.statsOutputDir,
      Option.stressAstscopeLookup,
      Option.supplementaryOutputFileMap,
      Option.suppressStaticExclusivitySwap,
      Option.suppressWarnings,
      Option.swiftVersion,
      Option.switchCheckingInvocationThresholdEQ,
      Option.S,
      Option.tabWidth,
      Option.targetCpu,
      Option.targetSdkVersion,
      Option.targetVariantSdkVersion,
      Option.targetVariant,
      Option.targetLegacySpelling,
      Option.target,
      Option.tbdCompatibilityVersionEQ,
      Option.tbdCompatibilityVersion,
      Option.tbdCurrentVersionEQ,
      Option.tbdCurrentVersion,
      Option.tbdInstallNameEQ,
      Option.tbdInstallName,
      Option.tbdIsInstallapi,
      Option.toolchainStdlibRpath,
      Option.toolsDirectory,
      Option.traceStatsEvents,
      Option.trackSystemDependencies,
      Option.triple,
      Option.typeInfoDumpFilterEQ,
      Option.typecheck,
      Option.typoCorrectionLimit,
      Option.updateCode,
      Option.useClangFunctionTypes,
      Option.useJit,
      Option.useLd,
      Option.useMalloc,
      Option.useTabs,
      Option.validateTbdAgainstIrEQ,
      Option.valueRecursionThreshold,
      Option.verifyAllSubstitutionMaps,
      Option.verifyApplyFixes,
      Option.verifyDebugInfo,
      Option.verifyGenericSignatures,
      Option.verifyIgnoreUnknown,
      Option.verifyIncrementalDependencies,
      Option.verifySyntaxTree,
      Option.verifyTypeLayout,
      Option.verify,
      Option.version,
      Option.version_,
      Option.vfsoverlayEQ,
      Option.vfsoverlay,
      Option.v,
      Option.warnIfAstscopeLookup,
      Option.warnImplicitOverrides,
      Option.warnLongExpressionTypeCheckingEQ,
      Option.warnLongExpressionTypeChecking,
      Option.warnLongFunctionBodiesEQ,
      Option.warnLongFunctionBodies,
      Option.warnSwift3ObjcInferenceComplete,
      Option.warnSwift3ObjcInferenceMinimal,
      Option.warnSwift3ObjcInference,
      Option.warningsAsErrors,
      Option.wholeModuleOptimization,
      Option.wmo,
      Option.workingDirectoryEQ,
      Option.workingDirectory,
      Option.Xcc,
      Option.XclangLinker,
      Option.Xfrontend,
      Option.Xlinker,
      Option.Xllvm,
      Option.DASHDASH,
    ]
  }
}

extension Option {
  public enum Group {
    case O
    case codeFormatting
    case debugCrash
    case g
    case `internal`
    case internalDebug
    case linkerOption
    case modes
  }
}

extension Option.Group {
  public var name: String {
    switch self {
      case .O:
        return "<optimization level options>"
      case .codeFormatting:
        return "<code formatting options>"
      case .debugCrash:
        return "<automatic crashing options>"
      case .g:
        return "<debug info options>"
      case .`internal`:
        return "<swift internal options>"
      case .internalDebug:
        return "<swift debug/development internal options>"
      case .linkerOption:
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
      case .codeFormatting:
        return nil
      case .debugCrash:
        return nil
      case .g:
        return nil
      case .`internal`:
        return nil
      case .internalDebug:
        return "DEBUG/DEVELOPMENT OPTIONS"
      case .linkerOption:
        return nil
      case .modes:
        return "MODES"
    }
  }
}
