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

import ArgumentParser

public struct O: ParsableArguments {
    public init() {}

    @Flag(name: [.customLong("Onone", withSingleDash: true)])
    public var Onone = false

    @Flag(name: [.customLong("Oplayground", withSingleDash: true)])
    public var Oplayground = false

    @Flag(name: [.customLong("Osize", withSingleDash: true)])
    public var Osize = false

    @Flag(name: [.customLong("Ounchecked", withSingleDash: true)])
    public var Ounchecked = false

    @Flag(name: [.customShort("O", allowingJoined: true)])
    public var O = false
}

public struct codeFormatting: ParsableArguments {
    public init() {}
  
    @Flag(name: [.customLong("in-place", withSingleDash: true)])
    public var inPlace = false

    @Flag(name: [.customLong("indent-switch-case", withSingleDash: true)])
    public var indentSwitchCase = false

    @Option(name: [.customLong("indent-width", withSingleDash: true)])
    public var indentWidth = ""

    @Option(name: [.customLong("line-range", withSingleDash: true)])
    public var lineRange = ""

    @Option(name: [.customLong("tab-width", withSingleDash: true)])
    public var tabWidth = ""

    @Flag(name: [.customLong("use-tabs", withSingleDash: true)])
    public var useTabs = false
}

public struct debugCrash: ParsableArguments {
    public init() {}

    @Flag(name: [.customLong("debug-assert-after-parse", withSingleDash: true)])
    public var debugAssertAfterParse = false

    @Flag(name: [.customLong("debug-assert-immediately", withSingleDash: true)])
    public var debugAssertImmediately = false

    @Flag(name: [.customLong("debug-crash-after-parse", withSingleDash: true)])
    public var debugCrashAfterParse = false

    @Flag(name: [.customLong("debug-crash-immediately", withSingleDash: true)])
    public var debugCrashImmediately = false
}

public struct g: ParsableArguments {
    public init() {}

    @Flag(name: [.customLong("gdwarf-types", withSingleDash: true)])
    public var gdwarfTypes = false

    @Flag(name: [.customLong("gline-tables-only", withSingleDash: true)])
    public var glineTablesOnly = false

    @Flag(name: [.customLong("gnone", withSingleDash: true)])
    public var gnone = false

    @Flag(name: [.customShort("g", allowingJoined: true)])
    public var g = false
}

public struct `internal`: ParsableArguments {
    public init() {}
}

public struct internalDebug: ParsableArguments {
    public init() {}

    @Flag(name: [.customLong("driver-always-rebuild-dependents", withSingleDash: true)])
    public var driverAlwaysRebuildDependents = false

    @Option(name: [.customLong("driver-batch-count", withSingleDash: true)])
    public var driverBatchCount = ""

    @Option(name: [.customLong("driver-batch-seed", withSingleDash: true)])
    public var driverBatchSeed = ""

    @Option(name: [.customLong("driver-batch-size-limit", withSingleDash: true)])
    public var driverBatchSizeLimit = ""

    @Flag(name: [.customLong("driver-emit-fine-grained-dependency-dot-file-after-every-import", withSingleDash: true)])
    public var driverEmitFineGrainedDependencyDotFileAfterEveryImport = false

    @Option(name: [.customLong("driver-filelist-threshold", withSingleDash: true)])
    public var driverFilelistThreshold = ""

    @Flag(name: [.customLong("driver-force-response-files", withSingleDash: true)])
    public var driverForceResponseFiles = false

    @Flag(name: [.customLong("driver-print-actions", withSingleDash: true)])
    public var driverPrintActions = false

    @Flag(name: [.customLong("driver-print-bindings", withSingleDash: true)])
    public var driverPrintBindings = false

    @Flag(name: [.customLong("driver-print-derived-output-file-map", withSingleDash: true)])
    public var driverPrintDerivedOutputFileMap = false

    @Flag(name: [.customLong("driver-print-jobs", withSingleDash: true), .customLong("###", withSingleDash: true)])
    public var driverPrintJobs = false

    @Flag(name: [.customLong("driver-print-output-file-map", withSingleDash: true)])
    public var driverPrintOutputFileMap = false

    @Flag(name: [.customLong("driver-show-incremental", withSingleDash: true)])
    public var driverShowIncremental = false

    @Flag(name: [.customLong("driver-show-job-lifecycle", withSingleDash: true)])
    public var driverShowJobLifecycle = false

    @Flag(name: [.customLong("driver-skip-execution", withSingleDash: true)])
    public var driverSkipExecution = false

    @Flag(name: [.customLong("driver-use-filelists", withSingleDash: true)])
    public var driverUseFilelists = false

    @Option(name: [.customLong("driver-use-frontend-path", withSingleDash: true)])
    public var driverUseFrontendPath = ""

    @Flag(name: [.customLong("driver-verify-fine-grained-dependency-graph-after-every-import", withSingleDash: true)])
    public var driverVerifyFineGrainedDependencyGraphAfterEveryImport = false
}

public struct linkerOption: ParsableArguments {
    public init() {}

    @Option(name: [.customLong("framework", withSingleDash: true)])
    public var framework = ""

    @Option(name: [.customShort("L", allowingJoined: true)])
    public var L = ""

    @Option(name: [.customShort("l", allowingJoined: true)])
    public var l = ""
}

public struct modes: ParsableArguments {
    public init() {}

    @Flag(name: [.customLong("compile-module-from-interface", withSingleDash: true), .customLong("build-module-from-parseable-interface", withSingleDash: true)])
    public var compileModuleFromInterface = false

    @Flag(name: [.customLong("deprecated-integrated-repl", withSingleDash: true)])
    public var deprecatedIntegratedRepl = false

    @Flag(name: [.customLong("dump-ast", withSingleDash: true)])
    public var dumpAst = false

    @Flag(name: [.customLong("dump-interface-hash", withSingleDash: true)])
    public var dumpInterfaceHash = false

    @Flag(name: [.customLong("dump-parse", withSingleDash: true)])
    public var dumpParse = false

    @Flag(name: [.customLong("dump-pcm", withSingleDash: true)])
    public var dumpPcm = false

    @Option(name: [.customLong("dump-scope-maps", withSingleDash: true)])
    public var dumpScopeMaps = ""

    @Flag(name: [.customLong("dump-type-info", withSingleDash: true)])
    public var dumpTypeInfo = false

    @Flag(name: [.customLong("dump-type-refinement-contexts", withSingleDash: true)])
    public var dumpTypeRefinementContexts = false

    @Flag(name: [.customLong("emit-assembly", withSingleDash: true), .customShort("S", allowingJoined: true)])
    public var emitAssembly = false

    @Flag(name: [.customLong("emit-bc", withSingleDash: true)])
    public var emitBc = false

    @Flag(name: [.customLong("emit-executable", withSingleDash: true)])
    public var emitExecutable = false

    @Flag(name: [.customLong("emit-imported-modules", withSingleDash: true)])
    public var emitImportedModules = false

    @Flag(name: [.customLong("emit-ir", withSingleDash: true)])
    public var emitIr = false

    @Flag(name: [.customLong("emit-library", withSingleDash: true)])
    public var emitLibrary = false

    @Flag(name: [.customLong("emit-object", withSingleDash: true), .customShort("c", allowingJoined: true)])
    public var emitObject = false

    @Flag(name: [.customLong("emit-pch", withSingleDash: true)])
    public var emitPch = false

    @Flag(name: [.customLong("emit-pcm", withSingleDash: true)])
    public var emitPcm = false

    @Flag(name: [.customLong("emit-sibgen", withSingleDash: true)])
    public var emitSibgen = false

    @Flag(name: [.customLong("emit-sib", withSingleDash: true)])
    public var emitSib = false

    @Flag(name: [.customLong("emit-silgen", withSingleDash: true)])
    public var emitSilgen = false

    @Flag(name: [.customLong("emit-sil", withSingleDash: true)])
    public var emitSil = false

    @Flag(name: [.customLong("emit-supported-features", withSingleDash: true)])
    public var emitSupportedFeatures = false

    @Flag(name: [.customLong("emit-syntax", withSingleDash: true)])
    public var emitSyntax = false

    @Flag(name: [.customLong("index-file", withSingleDash: true)])
    public var indexFile = false

    @Flag(name: [.customLong("interpret", withSingleDash: true)])
    public var interpret = false

    @Flag(name: [.customShort("i", allowingJoined: true)])
    public var i = false

    @Flag(name: [.customLong("lldb-repl", withSingleDash: true)])
    public var lldbRepl = false

    @Flag(name: [.customLong("merge-modules", withSingleDash: true)])
    public var mergeModules = false

    @Flag(name: [.customLong("parse", withSingleDash: true)])
    public var parse = false

    @Flag(name: [.customLong("print-ast", withSingleDash: true)])
    public var printAst = false

    @Flag(name: [.customLong("repl", withSingleDash: true)])
    public var repl = false

    @Flag(name: [.customLong("resolve-imports", withSingleDash: true)])
    public var resolveImports = false

    @Flag(name: [.customLong("scan-dependencies", withSingleDash: true)])
    public var scanDependencies = false

    @Flag(name: [.customLong("typecheck-module-from-interface", withSingleDash: true)])
    public var typecheckModuleFromInterface = false

    @Flag(name: [.customLong("typecheck", withSingleDash: true)])
    public var typecheck = false
}

public struct General: ParsableArguments {
    public init() {}

    @Argument()
    public var INPUT = [] as [String]

    @Option(name: [.customLong("api-diff-data-dir", withSingleDash: true)])
    public var apiDiffDataDir = ""

    @Option(name: [.customLong("api-diff-data-file", withSingleDash: true)])
    public var apiDiffDataFile = ""

    @Flag(name: [.customLong("application-extension", withSingleDash: true)])
    public var enableAppExtension = false

    @Option(name: [.customLong("assert-config", withSingleDash: true)])
    public var AssertConfig = ""

    @Flag(name: [.customLong("assume-single-threaded", withSingleDash: true)])
    public var AssumeSingleThreaded = false

    @Flag(name: [.customLong("autolink-force-load", withSingleDash: true)])
    public var autolinkForceLoad = false

    @Option(name: [.customLong("autolink-library", withSingleDash: true)])
    public var autolinkLibrary = ""

    @Flag(name: [.customLong("avoid-emit-module-source-info", withSingleDash: true)])
    public var avoidEmitModuleSourceInfo = false

    @Option(name: [.customLong("bad-file-descriptor-retry-count", withSingleDash: true)])
    public var badFileDescriptorRetryCount = ""

    @Option(name: [.customLong("batch-scan-input-file", withSingleDash: true)])
    public var batchScanInputFile = ""

    @Option(name: [.customLong("bridging-header-directory-for-print", withSingleDash: true)])
    public var bridgingHeaderDirectoryForPrint = ""

    @Flag(name: [.customLong("bypass-batch-mode-checks", withSingleDash: true)])
    public var bypassBatchModeChecks = false

    @Option(name: [.customLong("candidate-module-file", withSingleDash: true)])
    public var candidateModuleFile = ""

    @Flag(name: [.customLong("check-onone-completeness", withSingleDash: true)])
    public var checkOnoneCompleteness = false

    @Flag(name: [.customLong("code-complete-call-pattern-heuristics", withSingleDash: true)])
    public var codeCompleteCallPatternHeuristics = false

    @Flag(name: [.customLong("code-complete-inits-in-postfix-expr", withSingleDash: true)])
    public var codeCompleteInitsInPostfixExpr = false

    @Flag(name: [.customLong("color-diagnostics", withSingleDash: true)])
    public var colorDiagnostics = false

    @Flag(name: [.customLong("continue-building-after-errors", withSingleDash: true)])
    public var continueBuildingAfterErrors = false

    @Option(name: [.customLong("coverage-prefix-map", withSingleDash: true)])
    public var coveragePrefixMap = ""

    @Flag(name: [.customLong("cross-module-optimization", withSingleDash: true)])
    public var CrossModuleOptimization = false

    @Flag(name: [.customLong("crosscheck-unqualified-lookup", withSingleDash: true)])
    public var crosscheckUnqualifiedLookup = false

    @Option(name: [.customLong("debug-constraints-attempt", withSingleDash: true)])
    public var debugConstraintsAttempt = ""

    @Option(name: [.customLong("debug-constraints-on-line", withSingleDash: true)])
    public var debugConstraintsOnLine = ""

    @Flag(name: [.customLong("debug-constraints", withSingleDash: true)])
    public var debugConstraints = false

    @Flag(name: [.customLong("debug-cycles", withSingleDash: true)])
    public var debugCycles = false

    @Flag(name: [.customLong("debug-diagnostic-names", withSingleDash: true)])
    public var debugDiagnosticNames = false

    @Flag(name: [.customLong("debug-emit-invalid-swiftinterface-syntax", withSingleDash: true)])
    public var debugEmitInvalidSwiftinterfaceSyntax = false

    @Option(name: [.customLong("debug-forbid-typecheck-prefix", withSingleDash: true)])
    public var debugForbidTypecheckPrefix = ""

    @Flag(name: [.customLong("debug-generic-signatures", withSingleDash: true)])
    public var debugGenericSignatures = false

    @Option(name: [.customLong("debug-info-format", withSingleDash: true)])
    public var debugInfoFormat = ""

    @Flag(name: [.customLong("debug-info-store-invocation", withSingleDash: true)])
    public var debugInfoStoreInvocation = false

    @Option(name: [.customLong("debug-prefix-map", withSingleDash: true)])
    public var debugPrefixMap = ""

    @Flag(name: [.customLong("debug-time-expression-type-checking", withSingleDash: true)])
    public var debugTimeExpressionTypeChecking = false

    @Flag(name: [.customLong("debug-time-function-bodies", withSingleDash: true)])
    public var debugTimeFunctionBodies = false

    @Flag(name: [.customLong("debugger-support", withSingleDash: true)])
    public var debuggerSupport = false

    @Flag(name: [.customLong("debugger-testing-transform", withSingleDash: true)])
    public var debuggerTestingTransform = false

    @Option(name: [.customLong("define-availability", withSingleDash: true)])
    public var defineAvailability = ""

    @Option(name: [.customLong("diagnostic-documentation-path", withSingleDash: true)])
    public var diagnosticDocumentationPath = ""

    @Option(name: [.customLong("diagnostic-style", withSingleDash: true)])
    public var diagnosticStyle = ""

    @Flag(name: [.customLong("diagnostics-editor-mode", withSingleDash: true)])
    public var diagnosticsEditorMode = false

    @Flag(name: [.customLong("disable-access-control", withSingleDash: true)])
    public var disableAccessControl = false

    @Flag(name: [.customLong("disable-arc-opts", withSingleDash: true)])
    public var disableArcOpts = false

    @Flag(name: [.customLong("disable-ast-verifier", withSingleDash: true)])
    public var disableAstVerifier = false

    @Option(name: [.customLong("disable-autolink-framework", withSingleDash: true)])
    public var disableAutolinkFramework = ""

    @Flag(name: [.customLong("disable-autolinking-runtime-compatibility-dynamic-replacements", withSingleDash: true)])
    public var disableAutolinkingRuntimeCompatibilityDynamicReplacements = false

    @Flag(name: [.customLong("disable-autolinking-runtime-compatibility", withSingleDash: true)])
    public var disableAutolinkingRuntimeCompatibility = false

    @Flag(name: [.customLong("disable-availability-checking", withSingleDash: true)])
    public var disableAvailabilityChecking = false

    @Flag(name: [.customLong("disable-batch-mode", withSingleDash: true)])
    public var disableBatchMode = false

    @Flag(name: [.customLong("disable-bridging-pch", withSingleDash: true)])
    public var disableBridgingPch = false

    @Flag(name: [.customLong("disable-building-interface", withSingleDash: true)])
    public var disableBuildingInterface = false

    @Flag(name: [.customLong("disable-clangimporter-source-import", withSingleDash: true)])
    public var disableClangimporterSourceImport = false

    @Flag(name: [.customLong("disable-concrete-type-metadata-mangled-name-accessors", withSingleDash: true)])
    public var disableConcreteTypeMetadataMangledNameAccessors = false

    @Flag(name: [.customLong("disable-conformance-availability-errors", withSingleDash: true)])
    public var disableConformanceAvailabilityErrors = false

    @Flag(name: [.customLong("disable-constraint-solver-performance-hacks", withSingleDash: true)])
    public var disableConstraintSolverPerformanceHacks = false

    @Flag(name: [.customLong("disable-cross-import-overlays", withSingleDash: true)])
    public var disableCrossImportOverlays = false

    @Flag(name: [.customLong("disable-debugger-shadow-copies", withSingleDash: true)])
    public var disableDebuggerShadowCopies = false

    @Flag(name: [.customLong("disable-deserialization-recovery", withSingleDash: true)])
    public var disableDeserializationRecovery = false

    @Flag(name: [.customLong("disable-diagnostic-passes", withSingleDash: true)])
    public var disableDiagnosticPasses = false

    @Flag(name: [.customLong("disable-fuzzy-forward-scan-trailing-closure-matching", withSingleDash: true)])
    public var disableFuzzyForwardScanTrailingClosureMatching = false

    @Flag(name: [.customLong("disable-generic-metadata-prespecialization", withSingleDash: true)])
    public var disableGenericMetadataPrespecialization = false

    @Flag(name: [.customLong("disable-implicit-concurrency-module-import", withSingleDash: true)])
    public var disableImplicitConcurrencyModuleImport = false

    @Flag(name: [.customLong("disable-implicit-swift-modules", withSingleDash: true)])
    public var disableImplicitSwiftModules = false

    @Flag(name: [.customLong("disable-incremental-llvm-codegen", withSingleDash: true)])
    public var disableIncrementalLlvmCodegeneration = false

    @Flag(name: [.customLong("disable-interface-lock", withSingleDash: true)])
    public var disableInterfaceLockfile = false

    @Flag(name: [.customLong("disable-invalid-ephemeralness-as-error", withSingleDash: true)])
    public var disableInvalidEphemeralnessAsError = false

    @Flag(name: [.customLong("disable-legacy-type-info", withSingleDash: true)])
    public var disableLegacyTypeInfo = false

    @Flag(name: [.customLong("disable-llvm-optzns", withSingleDash: true)])
    public var disableLlvmOptzns = false

    @Flag(name: [.customLong("disable-llvm-slp-vectorizer", withSingleDash: true)])
    public var disableLlvmSlpVectorizer = false

    @Flag(name: [.customLong("disable-llvm-value-names", withSingleDash: true)])
    public var disableLlvmValueNames = false

    @Flag(name: [.customLong("disable-llvm-verify", withSingleDash: true)])
    public var disableLlvmVerify = false

    @Flag(name: [.customLong("disable-migrator-fixits", withSingleDash: true)])
    public var disableMigratorFixits = false

    @Flag(name: [.customLong("disable-modules-validate-system-headers", withSingleDash: true)])
    public var disableModulesValidateSystemHeaders = false

    @Flag(name: [.customLong("disable-named-lazy-member-loading", withSingleDash: true)])
    public var disableNamedLazyMemberLoading = false

    @Flag(name: [.customLong("disable-new-operator-lookup", withSingleDash: true)])
    public var disableNewOperatorLookup = false

    @Flag(name: [.customLong("disable-nonfrozen-enum-exhaustivity-diagnostics", withSingleDash: true)])
    public var disableNonfrozenEnumExhaustivityDiagnostics = false

    @Flag(name: [.customLong("disable-nskeyedarchiver-diagnostics", withSingleDash: true)])
    public var disableNskeyedarchiverDiagnostics = false

    @Flag(name: [.customLong("disable-objc-attr-requires-foundation-module", withSingleDash: true)])
    public var disableObjcAttrRequiresFoundationModule = false

    @Flag(name: [.customLong("disable-objc-interop", withSingleDash: true)])
    public var disableObjcInterop = false

    @Flag(name: [.customLong("disable-only-one-dependency-file", withSingleDash: true)])
    public var disableOnlyOneDependencyFile = false

    @Flag(name: [.customLong("disable-ossa-opts", withSingleDash: true)])
    public var disableOssaOpts = false

    @Flag(name: [.customLong("disable-playground-transform", withSingleDash: true)])
    public var disablePlaygroundTransform = false

    @Flag(name: [.customLong("disable-previous-implementation-calls-in-dynamic-replacements", withSingleDash: true)])
    public var disablePreviousImplementationCallsInDynamicReplacements = false

    @Flag(name: [.customLong("disable-reflection-metadata", withSingleDash: true)])
    public var disableReflectionMetadata = false

    @Flag(name: [.customLong("disable-reflection-names", withSingleDash: true)])
    public var disableReflectionNames = false

    @Flag(name: [.customLong("disable-request-based-incremental-dependencies", withSingleDash: true)])
    public var disableRequestBasedIncrementalDependencies = false

    @Flag(name: [.customLong("disable-sil-ownership-verifier", withSingleDash: true)])
    public var disableSilOwnershipVerifier = false

    @Flag(name: [.customLong("disable-sil-partial-apply", withSingleDash: true)])
    public var disableSilPartialApply = false

    @Flag(name: [.customLong("disable-sil-perf-optzns", withSingleDash: true)])
    public var disableSilPerfOptzns = false

    @Flag(name: [.customLong("disable-swift-bridge-attr", withSingleDash: true)])
    public var disableSwiftBridgeAttr = false

    @Flag(name: [.customLong("disable-swift-specific-llvm-optzns", withSingleDash: true)])
    public var disableSwiftSpecificLlvmOptzns = false

    @Flag(name: [.customLong("disable-swift3-objc-inference", withSingleDash: true)])
    public var disableSwift3ObjcInference = false

    @Flag(name: [.customLong("disable-target-os-checking", withSingleDash: true)])
    public var disableTargetOsChecking = false

    @Flag(name: [.customLong("disable-testable-attr-requires-testable-module", withSingleDash: true)])
    public var disableTestableAttrRequiresTestableModule = false

    @Flag(name: [.customLong("disable-type-layout", withSingleDash: true)])
    public var disableTypeLayouts = false

    @Flag(name: [.customLong("disable-typo-correction", withSingleDash: true)])
    public var disableTypoCorrection = false

    @Flag(name: [.customLong("disable-verify-exclusivity", withSingleDash: true)])
    public var disableVerifyExclusivity = false

    @Flag(name: [.customLong("disallow-use-new-driver", withSingleDash: true)])
    public var disallowForwardingDriver = false

    @Option(name: [.customLong("driver-mode", withSingleDash: true)])
    public var driverMode = ""

    @Flag(name: [.customLong("driver-time-compilation", withSingleDash: true)])
    public var driverTimeCompilation = false

    @Option(name: [.customLong("dump-api-path", withSingleDash: true)])
    public var dumpApiPath = ""

    @Flag(name: [.customLong("dump-clang-diagnostics", withSingleDash: true)])
    public var dumpClangDiagnostics = false

    @Option(name: [.customLong("dump-jit", withSingleDash: true)])
    public var dumpJit = ""

    @Option(name: [.customLong("dump-migration-states-dir", withSingleDash: true)])
    public var dumpMigrationStatesDir = ""

    @Flag(name: [.customLong("dump-usr", withSingleDash: true)])
    public var dumpUsr = false

    @Option(name: [.customShort("D", allowingJoined: true)])
    public var D = ""

    @Flag(name: [.customLong("embed-bitcode-marker", withSingleDash: true)])
    public var embedBitcodeMarker = false

    @Flag(name: [.customLong("embed-bitcode", withSingleDash: true)])
    public var embedBitcode = false

    @Option(name: [.customLong("embed-tbd-for-module", withSingleDash: true)])
    public var embedTbdForModule = ""

    @Option(name: [.customLong("emit-dependencies-path", withSingleDash: true)])
    public var emitDependenciesPath = ""

    @Flag(name: [.customLong("emit-dependencies", withSingleDash: true)])
    public var emitDependencies = false

    @Flag(name: [.customLong("emit-fine-grained-dependency-sourcefile-dot-files", withSingleDash: true)])
    public var emitFineGrainedDependencySourcefileDotFiles = false

    @Option(name: [.customLong("emit-fixits-path", withSingleDash: true)])
    public var emitFixitsPath = ""

    @Option(name: [.customLong("emit-ldadd-cfile-path", withSingleDash: true)])
    public var emitLdaddCfilePath = ""

    @Option(name: [.customLong("emit-loaded-module-trace-path", withSingleDash: true)])
    public var emitLoadedModuleTracePath = ""

    @Flag(name: [.customLong("emit-loaded-module-trace", withSingleDash: true)])
    public var emitLoadedModuleTrace = false

    @Option(name: [.customLong("emit-migrated-file-path", withSingleDash: true)])
    public var emitMigratedFilePath = ""

    @Option(name: [.customLong("emit-module-doc-path", withSingleDash: true)])
    public var emitModuleDocPath = ""

    @Flag(name: [.customLong("emit-module-doc", withSingleDash: true)])
    public var emitModuleDoc = false

    @Option(name: [.customLong("emit-module-interface-path", withSingleDash: true), .customLong("emit-parseable-module-interface-path", withSingleDash: true)])
    public var emitModuleInterfacePath = ""

    @Flag(name: [.customLong("emit-module-interface", withSingleDash: true), .customLong("emit-parseable-module-interface", withSingleDash: true)])
    public var emitModuleInterface = false

    @Option(name: [.customLong("emit-module-path", withSingleDash: true)])
    public var emitModulePath = ""

    @Option(name: [.customLong("emit-module-source-info-path", withSingleDash: true)])
    public var emitModuleSourceInfoPath = ""

    @Flag(name: [.customLong("emit-module-source-info", withSingleDash: true)])
    public var emitModuleSourceInfo = false

    @Option(name: [.customLong("emit-module-summary-path", withSingleDash: true)])
    public var emitModuleSummaryPath = ""

    @Flag(name: [.customLong("emit-module-summary", withSingleDash: true)])
    public var emitModuleSummary = false

    @Flag(name: [.customLong("emit-module", withSingleDash: true)])
    public var emitModule = false

    @Option(name: [.customLong("emit-objc-header-path", withSingleDash: true)])
    public var emitObjcHeaderPath = ""

    @Flag(name: [.customLong("emit-objc-header", withSingleDash: true)])
    public var emitObjcHeader = false

    @Option(name: [.customLong("emit-private-module-interface-path", withSingleDash: true)])
    public var emitPrivateModuleInterfacePath = ""

    @Option(name: [.customLong("emit-reference-dependencies-path", withSingleDash: true)])
    public var emitReferenceDependenciesPath = ""

    @Flag(name: [.customLong("emit-reference-dependencies", withSingleDash: true)])
    public var emitReferenceDependencies = false

    @Option(name: [.customLong("emit-remap-file-path", withSingleDash: true)])
    public var emitRemapFilePath = ""

    @Flag(name: [.customLong("emit-sorted-sil", withSingleDash: true)])
    public var emitSortedSil = false

    @Flag(name: [.customLong("emit-stack-promotion-checks", withSingleDash: true)])
    public var stackPromotionChecks = false

    @Option(name: [.customLong("emit-tbd-path", withSingleDash: true)])
    public var emitTbdPath = ""

    @Flag(name: [.customLong("emit-tbd", withSingleDash: true)])
    public var emitTbd = false

    @Flag(name: [.customLong("emit-verbose-sil", withSingleDash: true)])
    public var emitVerboseSil = false

    @Flag(name: [.customLong("enable-access-control", withSingleDash: true)])
    public var enableAccessControl = false

    @Flag(name: [.customLong("enable-anonymous-context-mangled-names", withSingleDash: true)])
    public var enableAnonymousContextMangledNames = false

    @Flag(name: [.customLong("enable-ast-verifier", withSingleDash: true)])
    public var enableAstVerifier = false

    @Flag(name: [.customLong("enable-batch-mode", withSingleDash: true)])
    public var enableBatchMode = false

    @Flag(name: [.customLong("enable-bridging-pch", withSingleDash: true)])
    public var enableBridgingPch = false

    @Flag(name: [.customLong("enable-conformance-availability-errors", withSingleDash: true)])
    public var enableConformanceAvailabilityErrors = false

    @Flag(name: [.customLong("enable-cross-import-overlays", withSingleDash: true)])
    public var enableCrossImportOverlays = false

    @Flag(name: [.customLong("enable-cxx-interop", withSingleDash: true)])
    public var enableCxxInterop = false

    @Flag(name: [.customLong("enable-deserialization-recovery", withSingleDash: true)])
    public var enableDeserializationRecovery = false

    @Flag(name: [.customLong("enable-dynamic-replacement-chaining", withSingleDash: true)])
    public var enableDynamicReplacementChaining = false

    @Flag(name: [.customLong("enable-experimental-additive-arithmetic-derivation", withSingleDash: true)])
    public var enableExperimentalAdditiveArithmeticDerivation = false

    @Flag(name: [.customLong("enable-experimental-concise-pound-file", withSingleDash: true)])
    public var enableExperimentalConcisePoundFile = false

    @Flag(name: [.customLong("enable-experimental-concurrency", withSingleDash: true)])
    public var enableExperimentalConcurrency = false

    @Flag(name: [.customLong("enable-experimental-cross-module-incremental-build", withSingleDash: true)])
    public var enableExperimentalCrossModuleIncrementalBuild = false

    @Flag(name: [.customLong("enable-experimental-cxx-interop", withSingleDash: true)])
    public var enableExperimentalCxxInterop = false

    @Flag(name: [.customLong("enable-experimental-forward-mode-differentiation", withSingleDash: true)])
    public var enableExperimentalForwardModeDifferentiation = false

    @Flag(name: [.customLong("enable-experimental-prespecialization", withSingleDash: true)])
    public var enableExperimentalPrespecialization = false

    @Flag(name: [.customLong("enable-experimental-static-assert", withSingleDash: true)])
    public var enableExperimentalStaticAssert = false

    @Flag(name: [.customLong("enable-fuzzy-forward-scan-trailing-closure-matching", withSingleDash: true)])
    public var enableFuzzyForwardScanTrailingClosureMatching = false

    @Flag(name: [.customLong("enable-implicit-dynamic", withSingleDash: true)])
    public var enableImplicitDynamic = false

    @Flag(name: [.customLong("enable-infer-import-as-member", withSingleDash: true)])
    public var enableInferImportAsMember = false

    @Flag(name: [.customLong("enable-invalid-ephemeralness-as-error", withSingleDash: true)])
    public var enableInvalidEphemeralnessAsError = false

    @Flag(name: [.customLong("enable-library-evolution", withSingleDash: true)])
    public var enableLibraryEvolution = false

    @Flag(name: [.customLong("enable-llvm-value-names", withSingleDash: true)])
    public var enableLlvmValueNames = false

    @Flag(name: [.customLong("enable-new-operator-lookup", withSingleDash: true)])
    public var enableNewOperatorLookup = false

    @Flag(name: [.customLong("enable-nonfrozen-enum-exhaustivity-diagnostics", withSingleDash: true)])
    public var enableNonfrozenEnumExhaustivityDiagnostics = false

    @Flag(name: [.customLong("enable-nskeyedarchiver-diagnostics", withSingleDash: true)])
    public var enableNskeyedarchiverDiagnostics = false

    @Flag(name: [.customLong("enable-objc-attr-requires-foundation-module", withSingleDash: true)])
    public var enableObjcAttrRequiresFoundationModule = false

    @Flag(name: [.customLong("enable-objc-interop", withSingleDash: true)])
    public var enableObjcInterop = false

    @Flag(name: [.customLong("enable-only-one-dependency-file", withSingleDash: true)])
    public var enableOnlyOneDependencyFile = false

    @Flag(name: [.customLong("enable-operator-designated-types", withSingleDash: true)])
    public var enableOperatorDesignatedTypes = false

    @Flag(name: [.customLong("enable-private-imports", withSingleDash: true)])
    public var enablePrivateImports = false

    @Flag(name: [.customLong("enable-request-based-incremental-dependencies", withSingleDash: true)])
    public var enableRequestBasedIncrementalDependencies = false

    @Flag(name: [.customLong("enable-resilience", withSingleDash: true)])
    public var enableResilience = false

    @Flag(name: [.customLong("enable-sil-opaque-values", withSingleDash: true)])
    public var enableSilOpaqueValues = false

    @Flag(name: [.customLong("enable-source-import", withSingleDash: true)])
    public var enableSourceImport = false

    @Flag(name: [.customLong("enable-spec-devirt", withSingleDash: true)])
    public var enableSpecDevirt = false

    @Flag(name: [.customLong("enable-swift3-objc-inference", withSingleDash: true)])
    public var enableSwift3ObjcInference = false

    @Flag(name: [.customLong("enable-swiftcall", withSingleDash: true)])
    public var enableSwiftcall = false

    @Flag(name: [.customLong("enable-target-os-checking", withSingleDash: true)])
    public var enableTargetOsChecking = false

    @Flag(name: [.customLong("enable-testable-attr-requires-testable-module", withSingleDash: true)])
    public var enableTestableAttrRequiresTestableModule = false

    @Flag(name: [.customLong("enable-testing", withSingleDash: true)])
    public var enableTesting = false

    @Flag(name: [.customLong("enable-throw-without-try", withSingleDash: true)])
    public var enableThrowWithoutTry = false

    @Flag(name: [.customLong("enable-type-layout", withSingleDash: true)])
    public var enableTypeLayouts = false

    @Flag(name: [.customLong("enable-verify-exclusivity", withSingleDash: true)])
    public var enableVerifyExclusivity = false

    @Flag(name: [.customLong("enable-volatile-modules", withSingleDash: true)])
    public var enableVolatileModules = false

    @Option(name: [.customLong("enforce-exclusivity", withSingleDash: true)])
    public var enforceExclusivityEQ = ""

    @Option(name: [.customLong("entry-point-function-name", withSingleDash: true)])
    public var entryPointFunctionName = ""

    @Flag(name: [.customLong("experimental-allow-module-with-compiler-errors", withSingleDash: true)])
    public var experimentalAllowModuleWithCompilerErrors = false

    @Option(name: [.customLong("experimental-cxx-stdlib", withSingleDash: true)])
    public var experimentalCxxStdlib = ""

    @Flag(name: [.customLong("experimental-one-way-closure-params", withSingleDash: true)])
    public var experimentalOneWayClosureParams = false

    @Flag(name: [.customLong("experimental-print-full-convention", withSingleDash: true)])
    public var experimentalPrintFullConvention = false

    @Flag(name: [.customLong("experimental-skip-all-function-bodies", withSingleDash: true)])
    public var experimentalSkipAllFunctionBodies = false

    @Flag(name: [.customLong("experimental-skip-non-inlinable-function-bodies-without-types", withSingleDash: true)])
    public var experimentalSkipNonInlinableFunctionBodiesWithoutTypes = false

    @Flag(name: [.customLong("experimental-skip-non-inlinable-function-bodies", withSingleDash: true)])
    public var experimentalSkipNonInlinableFunctionBodies = false

    @Flag(name: [.customLong("experimental-spi-imports", withSingleDash: true)])
    public var experimentalSpiImports = false

    @Option(name: [.customLong("explicit-swift-module-map-file", withSingleDash: true)])
    public var explictSwiftModuleMap = ""

    @Option(name: [.customLong("external-pass-pipeline-filename", withSingleDash: true)])
    public var externalPassPipelineFilename = ""

    @Option(name: [.customLong("filelist", withSingleDash: true)])
    public var filelist = ""

    @Flag(name: [.customLong("fixit-all", withSingleDash: true)])
    public var fixitAll = false

    @Flag(name: [.customLong("force-public-linkage", withSingleDash: true)])
    public var forcePublicLinkage = false

    @Flag(name: [.customLong("frontend-parseable-output", withSingleDash: true)])
    public var frontendParseableOutput = false

    @Option(name: [.customLong("Fsystem", withSingleDash: true)])
    public var Fsystem = ""

    @Flag(name: [.customLong("function-sections", withSingleDash: true)])
    public var functionSections = false

    @Option(name: [.customShort("F", allowingJoined: true)])
    public var F = ""

    @Option(name: [.customLong("group-info-path", withSingleDash: true)])
    public var groupInfoPath = ""

    @Flag(name: [.customLong("gsil", withSingleDash: true)])
    public var debugOnSil = false

    @Flag(name: [.customLong("help-hidden", withSingleDash: true), .customLong("help-hidden", withSingleDash: true)])
    public var helpHidden = false

    @Flag(name: [.customLong("help", withSingleDash: true), .customLong("help", withSingleDash: true), .customShort("h", allowingJoined: true)])
    public var help = false

    @Flag(name: [.customLong("ignore-always-inline", withSingleDash: true)])
    public var ignoreAlwaysInline = false

    @Flag(name: [.customLong("ignore-module-source-info", withSingleDash: true)])
    public var ignoreModuleSourceInfo = false

    @Flag(name: [.customLong("import-cf-types", withSingleDash: true)])
    public var importCfTypes = false

    @Option(name: [.customLong("import-module", withSingleDash: true)])
    public var importModule = ""

    @Option(name: [.customLong("import-objc-header", withSingleDash: true)])
    public var importObjcHeader = ""

    @Flag(name: [.customLong("import-prescan", withSingleDash: true)])
    public var importPrescan = false

    @Flag(name: [.customLong("import-underlying-module", withSingleDash: true)])
    public var importUnderlyingModule = false

    @Flag(name: [.customLong("incremental", withSingleDash: true)])
    public var incremental = false

    @Option(name: [.customLong("index-file-path", withSingleDash: true)])
    public var indexFilePath = ""

    @Flag(name: [.customLong("index-ignore-stdlib", withSingleDash: true)])
    public var indexIgnoreStdlib = false

    @Flag(name: [.customLong("index-ignore-system-modules", withSingleDash: true)])
    public var indexIgnoreSystemModules = false

    @Option(name: [.customLong("index-store-path", withSingleDash: true)])
    public var indexStorePath = ""

    @Flag(name: [.customLong("index-system-modules", withSingleDash: true)])
    public var indexSystemModules = false

    @Option(name: [.customShort("I", allowingJoined: true)])
    public var I = ""

    @Option(name: [.customShort("j", allowingJoined: true)])
    public var j = ""

    @Option(name: [.customLong("libc", withSingleDash: true)])
    public var libc = ""

    @Flag(name: [.customLong("link-objc-runtime", withSingleDash: true)])
    public var linkObjcRuntime = false

    @Option(name: [.customLong("locale", withSingleDash: true)])
    public var locale = ""

    @Option(name: [.customLong("localization-path", withSingleDash: true)])
    public var localizationPath = ""

    @Option(name: [.customLong("lto", withSingleDash: true)])
    public var lto = ""

    @Flag(name: [.customLong("migrate-keep-objc-visibility", withSingleDash: true)])
    public var migrateKeepObjcVisibility = false

    @Flag(name: [.customLong("migrator-update-sdk", withSingleDash: true)])
    public var migratorUpdateSdk = false

    @Flag(name: [.customLong("migrator-update-swift", withSingleDash: true)])
    public var migratorUpdateSwift = false

    @Option(name: [.customLong("module-cache-path", withSingleDash: true)])
    public var moduleCachePath = ""

    @Flag(name: [.customLong("module-interface-preserve-types-as-written", withSingleDash: true)])
    public var moduleInterfacePreserveTypesAsWritten = false

    @Option(name: [.customLong("module-link-name", withSingleDash: true)])
    public var moduleLinkName = ""

    @Option(name: [.customLong("module-name", withSingleDash: true)])
    public var moduleName = ""

    @Flag(name: [.customLong("no-clang-module-breadcrumbs", withSingleDash: true)])
    public var noClangModuleBreadcrumbs = false

    @Flag(name: [.customLong("no-color-diagnostics", withSingleDash: true)])
    public var noColorDiagnostics = false

    @Flag(name: [.customLong("no-link-objc-runtime", withSingleDash: true)])
    public var noLinkObjcRuntime = false

    @Flag(name: [.customLong("no-serialize-debugging-options", withSingleDash: true)])
    public var noSerializeDebuggingOptions = false

    @Flag(name: [.customLong("no-static-executable", withSingleDash: true)])
    public var noStaticExecutable = false

    @Flag(name: [.customLong("no-static-stdlib", withSingleDash: true)])
    public var noStaticStdlib = false

    @Flag(name: [.customLong("no-stdlib-rpath", withSingleDash: true)])
    public var noStdlibRpath = false

    @Flag(name: [.customLong("no-toolchain-stdlib-rpath", withSingleDash: true)])
    public var noToolchainStdlibRpath = false

    @Flag(name: [.customLong("no-verify-emitted-module-interface", withSingleDash: true)])
    public var noVerifyEmittedModuleInterface = false

    @Flag(name: [.customLong("no-warnings-as-errors", withSingleDash: true)])
    public var noWarningsAsErrors = false

    @Flag(name: [.customLong("no-whole-module-optimization", withSingleDash: true)])
    public var noWholeModuleOptimization = false

    @Flag(name: [.customLong("nostdimport", withSingleDash: true)])
    public var nostdimport = false

    @Option(name: [.customLong("num-threads", withSingleDash: true)])
    public var numThreads = ""

    @Flag(name: [.customLong("only-use-extra-clang-opts", withSingleDash: true)])
    public var extraClangOptionsOnly = false

    @Option(name: [.customLong("output-file-map", withSingleDash: true)])
    public var outputFileMap = ""

    @Option(name: [.customLong("output-filelist", withSingleDash: true)])
    public var outputFilelist = ""

    @Option(name: [.customShort("o", allowingJoined: true)])
    public var o = ""

    @Option(name: [.customLong("package-description-version", withSingleDash: true)])
    public var packageDescriptionVersion = ""

    @Flag(name: [.customLong("parse-as-library", withSingleDash: true)])
    public var parseAsLibrary = false

    @Flag(name: [.customLong("parse-sil", withSingleDash: true)])
    public var parseSil = false

    @Flag(name: [.customLong("parse-stdlib", withSingleDash: true)])
    public var parseStdlib = false

    @Flag(name: [.customLong("parseable-output", withSingleDash: true)])
    public var parseableOutput = false

    @Flag(name: [.customLong("pc-macro", withSingleDash: true)])
    public var pcMacro = false

    @Flag(name: [.customLong("pch-disable-validation", withSingleDash: true)])
    public var pchDisableValidation = false

    @Option(name: [.customLong("pch-output-dir", withSingleDash: true)])
    public var pchOutputDir = ""

    @Option(name: [.customLong("placeholder-dependency-module-map-file", withSingleDash: true)])
    public var placeholderDependencyModuleMap = ""

    @Flag(name: [.customLong("playground-high-performance", withSingleDash: true)])
    public var playgroundHighPerformance = false

    @Flag(name: [.customLong("playground", withSingleDash: true)])
    public var playground = false

    @Option(name: [.customLong("prebuilt-module-cache-path", withSingleDash: true)])
    public var prebuiltModuleCachePath = ""

    @Flag(name: [.customLong("prespecialize-generic-metadata", withSingleDash: true)])
    public var prespecializeGenericMetadata = false

    @Option(name: [.customLong("previous-module-installname-map-file", withSingleDash: true)])
    public var previousModuleInstallnameMapFile = ""

    @Option(name: [.customLong("primary-filelist", withSingleDash: true)])
    public var primaryFilelist = ""

    @Option(name: [.customLong("primary-file", withSingleDash: true)])
    public var primaryFile = ""

    @Flag(name: [.customLong("print-clang-stats", withSingleDash: true)])
    public var printClangStats = false

    @Flag(name: [.customLong("print-educational-notes", withSingleDash: true)])
    public var printEducationalNotes = false

    @Flag(name: [.customLong("print-inst-counts", withSingleDash: true)])
    public var printInstCounts = false

    @Flag(name: [.customLong("print-llvm-inline-tree", withSingleDash: true)])
    public var printLlvmInlineTree = false

    @Flag(name: [.customLong("print-stats", withSingleDash: true)])
    public var printStats = false

    @Flag(name: [.customLong("print-target-info", withSingleDash: true)])
    public var printTargetInfo = false

    @Flag(name: [.customLong("profile-coverage-mapping", withSingleDash: true)])
    public var profileCoverageMapping = false

    @Flag(name: [.customLong("profile-generate", withSingleDash: true)])
    public var profileGenerate = false

    @Flag(name: [.customLong("profile-stats-entities", withSingleDash: true)])
    public var profileStatsEntities = false

    @Flag(name: [.customLong("profile-stats-events", withSingleDash: true)])
    public var profileStatsEvents = false

    @Option(name: [.customLong("profile-use", withSingleDash: true)])
    public var profileUse = ""

    @Flag(name: [.customLong("Rcross-import", withSingleDash: true)])
    public var emitCrossImportRemarks = false

    @Option(name: [.customLong("read-legacy-type-info-path", withSingleDash: true)])
    public var readLegacyTypeInfoPathEQ = ""

    @Flag(name: [.customLong("remove-runtime-asserts", withSingleDash: true)])
    public var RemoveRuntimeAsserts = false

    @Option(name: [.customLong("require-explicit-availability-target", withSingleDash: true)])
    public var requireExplicitAvailabilityTarget = ""

    @Flag(name: [.customLong("require-explicit-availability", withSingleDash: true)])
    public var requireExplicitAvailability = false

    @Option(name: [.customLong("resource-dir", withSingleDash: true)])
    public var resourceDir = ""

    @Flag(name: [.customLong("Rmodule-interface-rebuild", withSingleDash: true)])
    public var RmoduleInterfaceRebuild = false

    @Flag(name: [.customLong("Rmodule-loading", withSingleDash: true)])
    public var remarkLoadingModule = false

    @Option(name: [.customLong("Rpass-missed", withSingleDash: true)])
    public var RpassMissedEQ = ""

    @Option(name: [.customLong("Rpass", withSingleDash: true)])
    public var RpassEQ = ""

    @Option(name: [.customLong("runtime-compatibility-version", withSingleDash: true)])
    public var runtimeCompatibilityVersion = ""

    @Flag(name: [.customLong("sanitize-address-use-odr-indicator", withSingleDash: true)])
    public var sanitizeAddressUseOdrIndicator = false

    @Option(name: [.customLong("sanitize-coverage", withSingleDash: true)])
    public var sanitizeCoverageEQ = ""

    @Option(name: [.customLong("sanitize-recover", withSingleDash: true)])
    public var sanitizeRecoverEQ = ""

    @Option(name: [.customLong("sanitize", withSingleDash: true)])
    public var sanitizeEQ = ""

    @Option(name: [.customLong("save-optimization-record-passes", withSingleDash: true)])
    public var saveOptimizationRecordPasses = ""

    @Option(name: [.customLong("save-optimization-record-path", withSingleDash: true)])
    public var saveOptimizationRecordPath = ""

    @Option(name: [.customLong("save-optimization-record", withSingleDash: true)])
    public var saveOptimizationRecordEQ = ""

    @Flag(name: [.customLong("save-optimization-record", withSingleDash: true)])
    public var saveOptimizationRecord = false

    @Flag(name: [.customLong("save-temps", withSingleDash: true)])
    public var saveTemps = false

    @Option(name: [.customLong("sdk", withSingleDash: true)])
    public var sdk = ""

    @Flag(name: [.customLong("serialize-debugging-options", withSingleDash: true)])
    public var serializeDebuggingOptions = false

    @Option(name: [.customLong("serialize-diagnostics-path", withSingleDash: true)])
    public var serializeDiagnosticsPath = ""

    @Flag(name: [.customLong("serialize-diagnostics", withSingleDash: true)])
    public var serializeDiagnostics = false

    @Flag(name: [.customLong("serialize-module-interface-dependency-hashes", withSingleDash: true), .customLong("serialize-parseable-module-interface-dependency-hashes", withSingleDash: true)])
    public var serializeModuleInterfaceDependencyHashes = false

    @Flag(name: [.customLong("show-diagnostics-after-fatal", withSingleDash: true)])
    public var showDiagnosticsAfterFatal = false

    @Flag(name: [.customLong("sil-debug-serialization", withSingleDash: true)])
    public var silDebugSerialization = false

    @Option(name: [.customLong("sil-inline-caller-benefit-reduction-factor", withSingleDash: true)])
    public var silInlineCallerBenefitReductionFactor = ""

    @Option(name: [.customLong("sil-inline-threshold", withSingleDash: true)])
    public var silInlineThreshold = ""

    @Flag(name: [.customLong("sil-stop-optzns-before-lowering-ownership", withSingleDash: true)])
    public var silStopOptznsBeforeLoweringOwnership = false

    @Option(name: [.customLong("sil-unroll-threshold", withSingleDash: true)])
    public var silUnrollThreshold = ""

    @Flag(name: [.customLong("sil-verify-all", withSingleDash: true)])
    public var silVerifyAll = false

    @Flag(name: [.customLong("sil-verify-none", withSingleDash: true)])
    public var silVerifyNone = false

    @Flag(name: [.customLong("solver-disable-shrink", withSingleDash: true)])
    public var solverDisableShrink = false

    @Option(name: [.customLong("solver-expression-time-threshold", withSingleDash: true)])
    public var solverExpressionTimeThresholdEQ = ""

    @Option(name: [.customLong("solver-memory-threshold", withSingleDash: true)])
    public var solverMemoryThreshold = ""

    @Option(name: [.customLong("solver-shrink-unsolved-threshold", withSingleDash: true)])
    public var solverShrinkUnsolvedThreshold = ""

    @Option(name: [.customLong("stack-promotion-limit", withSingleDash: true)])
    public var stackPromotionLimit = ""

    @Flag(name: [.customLong("static-executable", withSingleDash: true)])
    public var staticExecutable = false

    @Flag(name: [.customLong("static-stdlib", withSingleDash: true)])
    public var staticStdlib = false

    @Flag(name: [.customLong("static", withSingleDash: true)])
    public var `static` = false

    @Option(name: [.customLong("stats-output-dir", withSingleDash: true)])
    public var statsOutputDir = ""

    @Option(name: [.customLong("supplementary-output-file-map", withSingleDash: true)])
    public var supplementaryOutputFileMap = ""

    @Flag(name: [.customLong("suppress-static-exclusivity-swap", withSingleDash: true)])
    public var suppressStaticExclusivitySwap = false

    @Flag(name: [.customLong("suppress-warnings", withSingleDash: true)])
    public var suppressWarnings = false

    @Option(name: [.customLong("swift-module-file", withSingleDash: true)])
    public var swiftModuleFile = ""

    @Option(name: [.customLong("swift-version", withSingleDash: true)])
    public var swiftVersion = ""

    @Option(name: [.customLong("switch-checking-invocation-threshold", withSingleDash: true)])
    public var switchCheckingInvocationThresholdEQ = ""

    @Option(name: [.customLong("target-cpu", withSingleDash: true)])
    public var targetCpu = ""

    @Option(name: [.customLong("target-sdk-version", withSingleDash: true)])
    public var targetSdkVersion = ""

    @Option(name: [.customLong("target-public variant-sdk-version", withSingleDash: true)])
    public var targetVariantSdkVersion = ""

    @Option(name: [.customLong("target-public variant", withSingleDash: true)])
    public var targetVariant = ""

    @Option(name: [.customLong("target", withSingleDash: true), .customLong("triple", withSingleDash: true)])
    public var target = ""

    @Option(name: [.customLong("tbd-compatibility-version", withSingleDash: true)])
    public var tbdCompatibilityVersion = ""

    @Option(name: [.customLong("tbd-current-version", withSingleDash: true)])
    public var tbdCurrentVersion = ""

    @Option(name: [.customLong("tbd-install_name", withSingleDash: true)])
    public var tbdInstallName = ""

    @Flag(name: [.customLong("tbd-is-installapi", withSingleDash: true)])
    public var tbdIsInstallapi = false

    @Option(name: [.customLong("testable-import-module", withSingleDash: true)])
    public var testableImportModule = ""

    @Flag(name: [.customLong("toolchain-stdlib-rpath", withSingleDash: true)])
    public var toolchainStdlibRpath = false

    @Option(name: [.customLong("tools-directory", withSingleDash: true)])
    public var toolsDirectory = ""

    @Flag(name: [.customLong("trace-stats-events", withSingleDash: true)])
    public var traceStatsEvents = false

    @Flag(name: [.customLong("track-system-dependencies", withSingleDash: true)])
    public var trackSystemDependencies = false

    @Option(name: [.customLong("type-info-dump-filter", withSingleDash: true)])
    public var typeInfoDumpFilterEQ = ""

    @Option(name: [.customLong("typo-correction-limit", withSingleDash: true)])
    public var typoCorrectionLimit = ""

    @Flag(name: [.customLong("update-code", withSingleDash: true)])
    public var updateCode = false

    @Flag(name: [.customLong("use-clang-function-types", withSingleDash: true)])
    public var useClangFunctionTypes = false

    @Flag(name: [.customLong("use-jit", withSingleDash: true)])
    public var useJit = false

    @Option(name: [.customLong("use-ld", withSingleDash: true)])
    public var useLd = ""

    @Flag(name: [.customLong("use-malloc", withSingleDash: true)])
    public var useMalloc = false

    @Flag(name: [.customLong("use-static-resource-dir", withSingleDash: true)])
    public var useStaticResourceDir = false

    @Option(name: [.customLong("validate-tbd-against-ir", withSingleDash: true)])
    public var validateTbdAgainstIrEQ = ""

    @Option(name: [.customLong("value-recursion-threshold", withSingleDash: true)])
    public var valueRecursionThreshold = ""

    @Option(name: [.customLong("verify-additional-file", withSingleDash: true)])
    public var verifyAdditionalFile = ""

    @Flag(name: [.customLong("verify-all-substitution-maps", withSingleDash: true)])
    public var verifyAllSubstitutionMaps = false

    @Flag(name: [.customLong("verify-apply-fixes", withSingleDash: true)])
    public var verifyApplyFixes = false

    @Flag(name: [.customLong("verify-debug-info", withSingleDash: true)])
    public var verifyDebugInfo = false

    @Flag(name: [.customLong("verify-emitted-module-interface", withSingleDash: true)])
    public var verifyEmittedModuleInterface = false

    @Option(name: [.customLong("verify-generic-signatures", withSingleDash: true)])
    public var verifyGenericSignatures = ""

    @Flag(name: [.customLong("verify-ignore-unknown", withSingleDash: true)])
    public var verifyIgnoreUnknown = false

    @Flag(name: [.customLong("verify-incremental-dependencies", withSingleDash: true)])
    public var verifyIncrementalDependencies = false

    @Flag(name: [.customLong("verify-syntax-tree", withSingleDash: true)])
    public var verifySyntaxTree = false

    @Option(name: [.customLong("verify-type-layout", withSingleDash: true)])
    public var verifyTypeLayout = ""

    @Flag(name: [.customLong("verify", withSingleDash: true)])
    public var verify = false

    @Flag(name: [.customLong("version", withSingleDash: true), .customLong("version", withSingleDash: true)])
    public var version = false

    @Option(name: [.customLong("vfsoverlay", withSingleDash: true)])
    public var vfsoverlay = ""

    @Flag(name: [.customShort("v", allowingJoined: true)])
    public var v = false

    @Flag(name: [.customLong("warn-implicit-overrides", withSingleDash: true)])
    public var warnImplicitOverrides = false

    @Option(name: [.customLong("warn-long-expression-type-checking", withSingleDash: true)])
    public var warnLongExpressionTypeChecking = ""

    @Option(name: [.customLong("warn-long-function-bodies", withSingleDash: true)])
    public var warnLongFunctionBodies = ""

    @Flag(name: [.customLong("warn-swift3-objc-inference-complete", withSingleDash: true), .customLong("warn-swift3-objc-inference", withSingleDash: true)])
    public var warnSwift3ObjcInferenceComplete = false

    @Flag(name: [.customLong("warn-swift3-objc-inference-minimal", withSingleDash: true)])
    public var warnSwift3ObjcInferenceMinimal = false

    @Flag(name: [.customLong("warnings-as-errors", withSingleDash: true)])
    public var warningsAsErrors = false

    @Flag(name: [.customLong("whole-module-optimization", withSingleDash: true), .customLong("force-single-frontend-invocation", withSingleDash: true), .customLong("wmo", withSingleDash: true)])
    public var wholeModuleOptimization = false

    @Option(name: [.customLong("working-directory", withSingleDash: true)])
    public var workingDirectory = ""

    @Option(name: [.customLong("Xcc", withSingleDash: true)])
    public var Xcc = ""

    @Option(name: [.customLong("Xclang-linker", withSingleDash: true)])
    public var XclangLinker = ""

    @Option(name: [.customLong("Xfrontend", withSingleDash: true)])
    public var Xfrontend = ""

    @Option(name: [.customLong("Xlinker", withSingleDash: true)])
    public var Xlinker = ""

    @Option(name: [.customLong("Xllvm", withSingleDash: true)])
    public var Xllvm = ""
}

