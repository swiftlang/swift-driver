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

struct O: ParsableArguments {
    @Flag(name: [.customLong("Onone", withSingleDash: true)])
    var Onone = false

    @Flag(name: [.customLong("Oplayground", withSingleDash: true)])
    var Oplayground = false

    @Flag(name: [.customLong("Osize", withSingleDash: true)])
    var Osize = false

    @Flag(name: [.customLong("Ounchecked", withSingleDash: true)])
    var Ounchecked = false

    @Flag(name: [.customShort("O", allowingJoined: true)])
    var O = false
}

struct codeFormatting: ParsableArguments {
    @Flag(name: [.customLong("in-place", withSingleDash: true)])
    var inPlace = false

    @Flag(name: [.customLong("indent-switch-case", withSingleDash: true)])
    var indentSwitchCase = false

    @Option(name: [.customLong("indent-width", withSingleDash: true)])
    var indentWidth = ""

    @Option(name: [.customLong("line-range", withSingleDash: true)])
    var lineRange = ""

    @Option(name: [.customLong("tab-width", withSingleDash: true)])
    var tabWidth = ""

    @Flag(name: [.customLong("use-tabs", withSingleDash: true)])
    var useTabs = false
}

struct debugCrash: ParsableArguments {}

struct g: ParsableArguments {
    @Flag(name: [.customLong("gdwarf-types", withSingleDash: true)])
    var gdwarfTypes = false

    @Flag(name: [.customLong("gline-tables-only", withSingleDash: true)])
    var glineTablesOnly = false

    @Flag(name: [.customLong("gnone", withSingleDash: true)])
    var gnone = false

    @Flag(name: [.customShort("g", allowingJoined: true)])
    var g = false
}

struct `internal`: ParsableArguments {}

struct internalDebug: ParsableArguments {
    @Flag(name: [.customLong("driver-always-rebuild-dependents", withSingleDash: true)])
    var driverAlwaysRebuildDependents = false

    @Option(name: [.customLong("driver-batch-count", withSingleDash: true)])
    var driverBatchCount = ""

    @Option(name: [.customLong("driver-batch-seed", withSingleDash: true)])
    var driverBatchSeed = ""

    @Option(name: [.customLong("driver-batch-size-limit", withSingleDash: true)])
    var driverBatchSizeLimit = ""

    @Flag(name: [.customLong("driver-emit-fine-grained-dependency-dot-file-after-every-import", withSingleDash: true)])
    var driverEmitFineGrainedDependencyDotFileAfterEveryImport = false

    @Option(name: [.customLong("driver-filelist-threshold", withSingleDash: true)])
    var driverFilelistThreshold = ""

    @Flag(name: [.customLong("driver-force-response-files", withSingleDash: true)])
    var driverForceResponseFiles = false

    @Flag(name: [.customLong("driver-print-actions", withSingleDash: true)])
    var driverPrintActions = false

    @Flag(name: [.customLong("driver-print-bindings", withSingleDash: true)])
    var driverPrintBindings = false

    @Flag(name: [.customLong("driver-print-derived-output-file-map", withSingleDash: true)])
    var driverPrintDerivedOutputFileMap = false

    @Flag(name: [.customLong("driver-print-jobs", withSingleDash: true), .customLong("###", withSingleDash: true)])
    var driverPrintJobs = false

    @Flag(name: [.customLong("driver-print-output-file-map", withSingleDash: true)])
    var driverPrintOutputFileMap = false

    @Flag(name: [.customLong("driver-show-incremental", withSingleDash: true)])
    var driverShowIncremental = false

    @Flag(name: [.customLong("driver-show-job-lifecycle", withSingleDash: true)])
    var driverShowJobLifecycle = false

    @Flag(name: [.customLong("driver-skip-execution", withSingleDash: true)])
    var driverSkipExecution = false

    @Flag(name: [.customLong("driver-use-filelists", withSingleDash: true)])
    var driverUseFilelists = false

    @Option(name: [.customLong("driver-use-frontend-path", withSingleDash: true)])
    var driverUseFrontendPath = ""

    @Flag(name: [.customLong("driver-verify-fine-grained-dependency-graph-after-every-import", withSingleDash: true)])
    var driverVerifyFineGrainedDependencyGraphAfterEveryImport = false
}

struct linkerOption: ParsableArguments {
    @Option(name: [.customLong("framework", withSingleDash: true)])
    var framework = ""

    @Option(name: [.customShort("L", allowingJoined: true)])
    var L = ""

    @Option(name: [.customShort("l", allowingJoined: true)])
    var l = ""
}

struct modes: ParsableArguments {
    @Flag(name: [.customLong("deprecated-integrated-repl", withSingleDash: true)])
    var deprecatedIntegratedRepl = false

    @Flag(name: [.customLong("dump-ast", withSingleDash: true)])
    var dumpAst = false

    @Flag(name: [.customLong("dump-parse", withSingleDash: true)])
    var dumpParse = false

    @Flag(name: [.customLong("dump-pcm", withSingleDash: true)])
    var dumpPcm = false

    @Option(name: [.customLong("dump-scope-maps", withSingleDash: true)])
    var dumpScopeMaps = ""

    @Flag(name: [.customLong("dump-type-info", withSingleDash: true)])
    var dumpTypeInfo = false

    @Flag(name: [.customLong("dump-type-refinement-contexts", withSingleDash: true)])
    var dumpTypeRefinementContexts = false

    @Flag(name: [.customLong("emit-assembly", withSingleDash: true), .customShort("S", allowingJoined: true)])
    var emitAssembly = false

    @Flag(name: [.customLong("emit-bc", withSingleDash: true)])
    var emitBc = false

    @Flag(name: [.customLong("emit-executable", withSingleDash: true)])
    var emitExecutable = false

    @Flag(name: [.customLong("emit-imported-modules", withSingleDash: true)])
    var emitImportedModules = false

    @Flag(name: [.customLong("emit-ir", withSingleDash: true)])
    var emitIr = false

    @Flag(name: [.customLong("emit-library", withSingleDash: true)])
    var emitLibrary = false

    @Flag(name: [.customLong("emit-object", withSingleDash: true), .customShort("c", allowingJoined: true)])
    var emitObject = false

    @Flag(name: [.customLong("emit-pcm", withSingleDash: true)])
    var emitPcm = false

    @Flag(name: [.customLong("emit-sibgen", withSingleDash: true)])
    var emitSibgen = false

    @Flag(name: [.customLong("emit-sib", withSingleDash: true)])
    var emitSib = false

    @Flag(name: [.customLong("emit-silgen", withSingleDash: true)])
    var emitSilgen = false

    @Flag(name: [.customLong("emit-sil", withSingleDash: true)])
    var emitSil = false

    @Flag(name: [.customLong("emit-supported-features", withSingleDash: true)])
    var emitSupportedFeatures = false

    @Flag(name: [.customLong("index-file", withSingleDash: true)])
    var indexFile = false

    @Flag(name: [.customShort("i", allowingJoined: true)])
    var i = false

    @Flag(name: [.customLong("lldb-repl", withSingleDash: true)])
    var lldbRepl = false

    @Flag(name: [.customLong("parse", withSingleDash: true)])
    var parse = false

    @Flag(name: [.customLong("print-ast", withSingleDash: true)])
    var printAst = false

    @Flag(name: [.customLong("repl", withSingleDash: true)])
    var repl = false

    @Flag(name: [.customLong("resolve-imports", withSingleDash: true)])
    var resolveImports = false

    @Flag(name: [.customLong("scan-dependencies", withSingleDash: true)])
    var scanDependencies = false

    @Flag(name: [.customLong("typecheck", withSingleDash: true)])
    var typecheck = false
}

struct General: ParsableArguments {
    @Argument()
    var INPUT = [] as [String]

    @Option(name: [.customLong("api-diff-data-dir", withSingleDash: true)])
    var apiDiffDataDir = ""

    @Option(name: [.customLong("api-diff-data-file", withSingleDash: true)])
    var apiDiffDataFile = ""

    @Flag(name: [.customLong("application-extension", withSingleDash: true)])
    var enableAppExtension = false

    @Option(name: [.customLong("assert-config", withSingleDash: true)])
    var AssertConfig = ""

    @Flag(name: [.customLong("assume-single-threaded", withSingleDash: true)])
    var AssumeSingleThreaded = false

    @Flag(name: [.customLong("autolink-force-load", withSingleDash: true)])
    var autolinkForceLoad = false

    @Flag(name: [.customLong("avoid-emit-module-source-info", withSingleDash: true)])
    var avoidEmitModuleSourceInfo = false

    @Flag(name: [.customLong("color-diagnostics", withSingleDash: true)])
    var colorDiagnostics = false

    @Flag(name: [.customLong("continue-building-after-errors", withSingleDash: true)])
    var continueBuildingAfterErrors = false

    @Option(name: [.customLong("coverage-prefix-map", withSingleDash: true)])
    var coveragePrefixMap = ""

    @Flag(name: [.customLong("cross-module-optimization", withSingleDash: true)])
    var CrossModuleOptimization = false

    @Flag(name: [.customLong("debug-diagnostic-names", withSingleDash: true)])
    var debugDiagnosticNames = false

    @Option(name: [.customLong("debug-info-format", withSingleDash: true)])
    var debugInfoFormat = ""

    @Flag(name: [.customLong("debug-info-store-invocation", withSingleDash: true)])
    var debugInfoStoreInvocation = false

    @Option(name: [.customLong("debug-prefix-map", withSingleDash: true)])
    var debugPrefixMap = ""

    @Option(name: [.customLong("define-availability", withSingleDash: true)])
    var defineAvailability = ""

    @Option(name: [.customLong("diagnostic-style", withSingleDash: true)])
    var diagnosticStyle = ""

    @Flag(name: [.customLong("disable-autolinking-runtime-compatibility-dynamic-replacements", withSingleDash: true)])
    var disableAutolinkingRuntimeCompatibilityDynamicReplacements = false

    @Flag(name: [.customLong("disable-autolinking-runtime-compatibility", withSingleDash: true)])
    var disableAutolinkingRuntimeCompatibility = false

    @Flag(name: [.customLong("disable-batch-mode", withSingleDash: true)])
    var disableBatchMode = false

    @Flag(name: [.customLong("disable-bridging-pch", withSingleDash: true)])
    var disableBridgingPch = false

    @Flag(name: [.customLong("disable-fuzzy-forward-scan-trailing-closure-matching", withSingleDash: true)])
    var disableFuzzyForwardScanTrailingClosureMatching = false

    @Flag(name: [.customLong("disable-migrator-fixits", withSingleDash: true)])
    var disableMigratorFixits = false

    @Flag(name: [.customLong("disable-only-one-dependency-file", withSingleDash: true)])
    var disableOnlyOneDependencyFile = false

    @Flag(name: [.customLong("disable-request-based-incremental-dependencies", withSingleDash: true)])
    var disableRequestBasedIncrementalDependencies = false

    @Flag(name: [.customLong("disable-swift-bridge-attr", withSingleDash: true)])
    var disableSwiftBridgeAttr = false

    @Flag(name: [.customLong("disallow-use-new-driver", withSingleDash: true)])
    var disallowForwardingDriver = false

    @Option(name: [.customLong("driver-mode", withSingleDash: true)])
    var driverMode = ""

    @Flag(name: [.customLong("driver-time-compilation", withSingleDash: true)])
    var driverTimeCompilation = false

    @Option(name: [.customLong("dump-migration-states-dir", withSingleDash: true)])
    var dumpMigrationStatesDir = ""

    @Flag(name: [.customLong("dump-usr", withSingleDash: true)])
    var dumpUsr = false

    @Option(name: [.customShort("D", allowingJoined: true)])
    var D = ""

    @Flag(name: [.customLong("embed-bitcode-marker", withSingleDash: true)])
    var embedBitcodeMarker = false

    @Flag(name: [.customLong("embed-bitcode", withSingleDash: true)])
    var embedBitcode = false

    @Option(name: [.customLong("embed-tbd-for-module", withSingleDash: true)])
    var embedTbdForModule = ""

    @Flag(name: [.customLong("emit-dependencies", withSingleDash: true)])
    var emitDependencies = false

    @Flag(name: [.customLong("emit-fine-grained-dependency-sourcefile-dot-files", withSingleDash: true)])
    var emitFineGrainedDependencySourcefileDotFiles = false

    @Option(name: [.customLong("emit-loaded-module-trace-path", withSingleDash: true)])
    var emitLoadedModuleTracePath = ""

    @Flag(name: [.customLong("emit-loaded-module-trace", withSingleDash: true)])
    var emitLoadedModuleTrace = false

    @Option(name: [.customLong("emit-module-interface-path", withSingleDash: true), .customLong("emit-parseable-module-interface-path", withSingleDash: true)])
    var emitModuleInterfacePath = ""

    @Flag(name: [.customLong("emit-module-interface", withSingleDash: true), .customLong("emit-parseable-module-interface", withSingleDash: true)])
    var emitModuleInterface = false

    @Option(name: [.customLong("emit-module-path", withSingleDash: true)])
    var emitModulePath = ""

    @Option(name: [.customLong("emit-module-source-info-path", withSingleDash: true)])
    var emitModuleSourceInfoPath = ""

    @Option(name: [.customLong("emit-module-summary-path", withSingleDash: true)])
    var emitModuleSummaryPath = ""

    @Flag(name: [.customLong("emit-module-summary", withSingleDash: true)])
    var emitModuleSummary = false

    @Flag(name: [.customLong("emit-module", withSingleDash: true)])
    var emitModule = false

    @Option(name: [.customLong("emit-objc-header-path", withSingleDash: true)])
    var emitObjcHeaderPath = ""

    @Flag(name: [.customLong("emit-objc-header", withSingleDash: true)])
    var emitObjcHeader = false

    @Option(name: [.customLong("emit-private-module-interface-path", withSingleDash: true)])
    var emitPrivateModuleInterfacePath = ""

    @Option(name: [.customLong("emit-tbd-path", withSingleDash: true)])
    var emitTbdPath = ""

    @Flag(name: [.customLong("emit-tbd", withSingleDash: true)])
    var emitTbd = false

    @Flag(name: [.customLong("enable-batch-mode", withSingleDash: true)])
    var enableBatchMode = false

    @Flag(name: [.customLong("enable-bridging-pch", withSingleDash: true)])
    var enableBridgingPch = false

    @Flag(name: [.customLong("enable-experimental-additive-arithmetic-derivation", withSingleDash: true)])
    var enableExperimentalAdditiveArithmeticDerivation = false

    @Flag(name: [.customLong("enable-experimental-concise-pound-file", withSingleDash: true)])
    var enableExperimentalConcisePoundFile = false

    @Flag(name: [.customLong("enable-experimental-cross-module-incremental-build", withSingleDash: true)])
    var enableExperimentalCrossModuleIncrementalBuild = false

    @Flag(name: [.customLong("enable-experimental-cxx-interop", withSingleDash: true)])
    var enableExperimentalCxxInterop = false

    @Flag(name: [.customLong("enable-experimental-forward-mode-differentiation", withSingleDash: true)])
    var enableExperimentalForwardModeDifferentiation = false

    @Flag(name: [.customLong("enable-fuzzy-forward-scan-trailing-closure-matching", withSingleDash: true)])
    var enableFuzzyForwardScanTrailingClosureMatching = false

    @Flag(name: [.customLong("enable-library-evolution", withSingleDash: true)])
    var enableLibraryEvolution = false

    @Flag(name: [.customLong("enable-only-one-dependency-file", withSingleDash: true)])
    var enableOnlyOneDependencyFile = false

    @Flag(name: [.customLong("enable-private-imports", withSingleDash: true)])
    var enablePrivateImports = false

    @Flag(name: [.customLong("enable-request-based-incremental-dependencies", withSingleDash: true)])
    var enableRequestBasedIncrementalDependencies = false

    @Flag(name: [.customLong("enable-testing", withSingleDash: true)])
    var enableTesting = false

    @Option(name: [.customLong("enforce-exclusivity", withSingleDash: true)])
    var enforceExclusivityEQ = ""

    @Option(name: [.customLong("experimental-cxx-stdlib", withSingleDash: true)])
    var experimentalCxxStdlib = ""

    @Flag(name: [.customLong("experimental-skip-non-inlinable-function-bodies-without-types", withSingleDash: true)])
    var experimentalSkipNonInlinableFunctionBodiesWithoutTypes = false

    @Flag(name: [.customLong("experimental-skip-non-inlinable-function-bodies", withSingleDash: true)])
    var experimentalSkipNonInlinableFunctionBodies = false

    @Flag(name: [.customLong("fixit-all", withSingleDash: true)])
    var fixitAll = false

    @Option(name: [.customLong("Fsystem", withSingleDash: true)])
    var Fsystem = ""

    @Option(name: [.customShort("F", allowingJoined: true)])
    var F = ""

    @Flag(name: [.customLong("help-hidden", withSingleDash: true), .customLong("help-hidden", withSingleDash: true)])
    var helpHidden = false

    @Flag(name: [.customLong("help", withSingleDash: true), .customLong("help", withSingleDash: true), .customShort("h", allowingJoined: true)])
    var help = false

    @Flag(name: [.customLong("import-cf-types", withSingleDash: true)])
    var importCfTypes = false

    @Option(name: [.customLong("import-objc-header", withSingleDash: true)])
    var importObjcHeader = ""

    @Flag(name: [.customLong("import-underlying-module", withSingleDash: true)])
    var importUnderlyingModule = false

    @Flag(name: [.customLong("incremental", withSingleDash: true)])
    var incremental = false

    @Option(name: [.customLong("index-file-path", withSingleDash: true)])
    var indexFilePath = ""

    @Flag(name: [.customLong("index-ignore-system-modules", withSingleDash: true)])
    var indexIgnoreSystemModules = false

    @Option(name: [.customLong("index-store-path", withSingleDash: true)])
    var indexStorePath = ""

    @Option(name: [.customShort("I", allowingJoined: true)])
    var I = ""

    @Option(name: [.customShort("j", allowingJoined: true)])
    var j = ""

    @Option(name: [.customLong("libc", withSingleDash: true)])
    var libc = ""

    @Flag(name: [.customLong("link-objc-runtime", withSingleDash: true)])
    var linkObjcRuntime = false

    @Option(name: [.customLong("locale", withSingleDash: true)])
    var locale = ""

    @Option(name: [.customLong("localization-path", withSingleDash: true)])
    var localizationPath = ""

    @Option(name: [.customLong("lto", withSingleDash: true)])
    var lto = ""

    @Flag(name: [.customLong("migrate-keep-objc-visibility", withSingleDash: true)])
    var migrateKeepObjcVisibility = false

    @Flag(name: [.customLong("migrator-update-sdk", withSingleDash: true)])
    var migratorUpdateSdk = false

    @Flag(name: [.customLong("migrator-update-swift", withSingleDash: true)])
    var migratorUpdateSwift = false

    @Option(name: [.customLong("module-cache-path", withSingleDash: true)])
    var moduleCachePath = ""

    @Option(name: [.customLong("module-link-name", withSingleDash: true)])
    var moduleLinkName = ""

    @Option(name: [.customLong("module-name", withSingleDash: true)])
    var moduleName = ""

    @Flag(name: [.customLong("no-color-diagnostics", withSingleDash: true)])
    var noColorDiagnostics = false

    @Flag(name: [.customLong("no-link-objc-runtime", withSingleDash: true)])
    var noLinkObjcRuntime = false

    @Flag(name: [.customLong("no-static-executable", withSingleDash: true)])
    var noStaticExecutable = false

    @Flag(name: [.customLong("no-static-stdlib", withSingleDash: true)])
    var noStaticStdlib = false

    @Flag(name: [.customLong("no-stdlib-rpath", withSingleDash: true)])
    var noStdlibRpath = false

    @Flag(name: [.customLong("no-toolchain-stdlib-rpath", withSingleDash: true)])
    var noToolchainStdlibRpath = false

    @Flag(name: [.customLong("no-verify-emitted-module-interface", withSingleDash: true)])
    var noVerifyEmittedModuleInterface = false

    @Flag(name: [.customLong("no-warnings-as-errors", withSingleDash: true)])
    var noWarningsAsErrors = false

    @Flag(name: [.customLong("no-whole-module-optimization", withSingleDash: true)])
    var noWholeModuleOptimization = false

    @Flag(name: [.customLong("nostdimport", withSingleDash: true)])
    var nostdimport = false

    @Option(name: [.customLong("num-threads", withSingleDash: true)])
    var numThreads = ""

    @Option(name: [.customLong("output-file-map", withSingleDash: true)])
    var outputFileMap = ""

    @Option(name: [.customShort("o", allowingJoined: true)])
    var o = ""

    @Option(name: [.customLong("package-description-version", withSingleDash: true)])
    var packageDescriptionVersion = ""

    @Flag(name: [.customLong("parse-as-library", withSingleDash: true)])
    var parseAsLibrary = false

    @Flag(name: [.customLong("parse-sil", withSingleDash: true)])
    var parseSil = false

    @Flag(name: [.customLong("parse-stdlib", withSingleDash: true)])
    var parseStdlib = false

    @Flag(name: [.customLong("parseable-output", withSingleDash: true)])
    var parseableOutput = false

    @Option(name: [.customLong("pch-output-dir", withSingleDash: true)])
    var pchOutputDir = ""

    @Flag(name: [.customLong("print-educational-notes", withSingleDash: true)])
    var printEducationalNotes = false

    @Flag(name: [.customLong("print-target-info", withSingleDash: true)])
    var printTargetInfo = false

    @Flag(name: [.customLong("profile-coverage-mapping", withSingleDash: true)])
    var profileCoverageMapping = false

    @Flag(name: [.customLong("profile-generate", withSingleDash: true)])
    var profileGenerate = false

    @Flag(name: [.customLong("profile-stats-entities", withSingleDash: true)])
    var profileStatsEntities = false

    @Flag(name: [.customLong("profile-stats-events", withSingleDash: true)])
    var profileStatsEvents = false

    @Option(name: [.customLong("profile-use", withSingleDash: true)])
    var profileUse = ""

    @Flag(name: [.customLong("Rcross-import", withSingleDash: true)])
    var emitCrossImportRemarks = false

    @Flag(name: [.customLong("remove-runtime-asserts", withSingleDash: true)])
    var RemoveRuntimeAsserts = false

    @Option(name: [.customLong("require-explicit-availability-target", withSingleDash: true)])
    var requireExplicitAvailabilityTarget = ""

    @Flag(name: [.customLong("require-explicit-availability", withSingleDash: true)])
    var requireExplicitAvailability = false

    @Option(name: [.customLong("resource-dir", withSingleDash: true)])
    var resourceDir = ""

    @Flag(name: [.customLong("Rmodule-loading", withSingleDash: true)])
    var remarkLoadingModule = false

    @Option(name: [.customLong("Rpass-missed", withSingleDash: true)])
    var RpassMissedEQ = ""

    @Option(name: [.customLong("Rpass", withSingleDash: true)])
    var RpassEQ = ""

    @Option(name: [.customLong("runtime-compatibility-version", withSingleDash: true)])
    var runtimeCompatibilityVersion = ""

    @Flag(name: [.customLong("sanitize-address-use-odr-indicator", withSingleDash: true)])
    var sanitizeAddressUseOdrIndicator = false

    @Option(name: [.customLong("sanitize-coverage", withSingleDash: true)])
    var sanitizeCoverageEQ = ""

    @Option(name: [.customLong("sanitize-recover", withSingleDash: true)])
    var sanitizeRecoverEQ = ""

    @Option(name: [.customLong("sanitize", withSingleDash: true)])
    var sanitizeEQ = ""

    @Option(name: [.customLong("save-optimization-record-passes", withSingleDash: true)])
    var saveOptimizationRecordPasses = ""

    @Option(name: [.customLong("save-optimization-record-path", withSingleDash: true)])
    var saveOptimizationRecordPath = ""

    @Option(name: [.customLong("save-optimization-record", withSingleDash: true)])
    var saveOptimizationRecordEQ = ""

    @Flag(name: [.customLong("save-optimization-record", withSingleDash: true)])
    var saveOptimizationRecord = false

    @Flag(name: [.customLong("save-temps", withSingleDash: true)])
    var saveTemps = false

    @Option(name: [.customLong("sdk", withSingleDash: true)])
    var sdk = ""

    @Option(name: [.customLong("serialize-diagnostics-path", withSingleDash: true)])
    var serializeDiagnosticsPath = ""

    @Flag(name: [.customLong("serialize-diagnostics", withSingleDash: true)])
    var serializeDiagnostics = false

    @Option(name: [.customLong("solver-memory-threshold", withSingleDash: true)])
    var solverMemoryThreshold = ""

    @Option(name: [.customLong("solver-shrink-unsolved-threshold", withSingleDash: true)])
    var solverShrinkUnsolvedThreshold = ""

    @Flag(name: [.customLong("static-executable", withSingleDash: true)])
    var staticExecutable = false

    @Flag(name: [.customLong("static-stdlib", withSingleDash: true)])
    var staticStdlib = false

    @Flag(name: [.customLong("static", withSingleDash: true)])
    var `static` = false

    @Option(name: [.customLong("stats-output-dir", withSingleDash: true)])
    var statsOutputDir = ""

    @Flag(name: [.customLong("suppress-warnings", withSingleDash: true)])
    var suppressWarnings = false

    @Option(name: [.customLong("swift-version", withSingleDash: true)])
    var swiftVersion = ""

    @Option(name: [.customLong("target-cpu", withSingleDash: true)])
    var targetCpu = ""

    @Option(name: [.customLong("target-variant", withSingleDash: true)])
    var targetVariant = ""

    @Option(name: [.customLong("target", withSingleDash: true), .customLong("triple", withSingleDash: true)])
    var target = ""

    @Flag(name: [.customLong("toolchain-stdlib-rpath", withSingleDash: true)])
    var toolchainStdlibRpath = false

    @Option(name: [.customLong("tools-directory", withSingleDash: true)])
    var toolsDirectory = ""

    @Flag(name: [.customLong("trace-stats-events", withSingleDash: true)])
    var traceStatsEvents = false

    @Flag(name: [.customLong("track-system-dependencies", withSingleDash: true)])
    var trackSystemDependencies = false

    @Option(name: [.customLong("typo-correction-limit", withSingleDash: true)])
    var typoCorrectionLimit = ""

    @Flag(name: [.customLong("update-code", withSingleDash: true)])
    var updateCode = false

    @Option(name: [.customLong("use-ld", withSingleDash: true)])
    var useLd = ""

    @Option(name: [.customLong("value-recursion-threshold", withSingleDash: true)])
    var valueRecursionThreshold = ""

    @Flag(name: [.customLong("verify-debug-info", withSingleDash: true)])
    var verifyDebugInfo = false

    @Flag(name: [.customLong("verify-emitted-module-interface", withSingleDash: true)])
    var verifyEmittedModuleInterface = false

    @Flag(name: [.customLong("verify-incremental-dependencies", withSingleDash: true)])
    var verifyIncrementalDependencies = false

    @Flag(name: [.customLong("version", withSingleDash: true), .customLong("version", withSingleDash: true)])
    var version = false

    @Option(name: [.customLong("vfsoverlay", withSingleDash: true)])
    var vfsoverlay = ""

    @Flag(name: [.customShort("v", allowingJoined: true)])
    var v = false

    @Flag(name: [.customLong("warn-implicit-overrides", withSingleDash: true)])
    var warnImplicitOverrides = false

    @Flag(name: [.customLong("warn-swift3-objc-inference-complete", withSingleDash: true), .customLong("warn-swift3-objc-inference", withSingleDash: true)])
    var warnSwift3ObjcInferenceComplete = false

    @Flag(name: [.customLong("warn-swift3-objc-inference-minimal", withSingleDash: true)])
    var warnSwift3ObjcInferenceMinimal = false

    @Flag(name: [.customLong("warnings-as-errors", withSingleDash: true)])
    var warningsAsErrors = false

    @Flag(name: [.customLong("whole-module-optimization", withSingleDash: true), .customLong("force-single-frontend-invocation", withSingleDash: true), .customLong("wmo", withSingleDash: true)])
    var wholeModuleOptimization = false

    @Option(name: [.customLong("working-directory", withSingleDash: true)])
    var workingDirectory = ""

    @Option(name: [.customLong("Xcc", withSingleDash: true)])
    var Xcc = ""

    @Option(name: [.customLong("Xclang-linker", withSingleDash: true)])
    var XclangLinker = ""

    @Option(name: [.customLong("Xfrontend", withSingleDash: true)])
    var Xfrontend = ""

    @Option(name: [.customLong("Xlinker", withSingleDash: true)])
    var Xlinker = ""

    @Option(name: [.customLong("Xllvm", withSingleDash: true)])
    var Xllvm = ""
}

