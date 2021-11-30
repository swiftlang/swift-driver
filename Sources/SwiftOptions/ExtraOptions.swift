//===--------------- ExtraOptions.swift - Swift Driver Extra Options ------===//
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
  public static let driverPrintGraphviz: Option = Option("-driver-print-graphviz", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Write the job graph as a graphviz file", group: .internalDebug)

  public static let driverExplicitModuleBuild: Option = Option("-explicit-module-build", .flag, attributes: [.helpHidden], helpText: "Prebuild module dependencies to make them explicit")
  public static let driverExperimentalExplicitModuleBuild: Option = Option("-experimental-explicit-module-build", .flag, alias: Option.driverExplicitModuleBuild, attributes: [.helpHidden], helpText: "Prebuild module dependencies to make them explicit")
  public static let driverScanDependenciesNonLib: Option = Option("-nonlib-dependency-scanner", .flag, attributes: [.helpHidden], helpText: "Use calls to `swift-frontend -scan-dependencies` instead of dedicated dependency scanning library")
  public static let driverWarnUnusedOptions: Option = Option("-driver-warn-unused-options", .flag, attributes: [.helpHidden], helpText: "Emit warnings for any provided options which are unused by the driver")
  public static let emitModuleSeparately: Option = Option("-experimental-emit-module-separately", .flag, attributes: [.helpHidden], helpText: "Emit module files as a distinct job")
  public static let emitModuleSeparatelyWMO: Option = Option("-emit-module-separately-wmo", .flag, attributes: [.helpHidden], helpText: "Emit module files as a distinct job in wmo builds")
  public static let noEmitModuleSeparatelyWMO: Option = Option("-no-emit-module-separately-wmo", .flag, attributes: [.helpHidden], helpText: "Emit module files as a distinct job in wmo builds")
  public static let useFrontendParseableOutput: Option = Option("-use-frontend-parseable-output", .flag, attributes: [.helpHidden], helpText: "Emit parseable-output from swift-frontend jobs instead of from the driver")

  // API digester operations
  public static let emitDigesterBaseline: Option = Option("-emit-digester-baseline", .flag, attributes: [.noInteractive, .supplementaryOutput], helpText: "Emit a baseline file for the module using the API digester")
  public static let emitDigesterBaselinePath: Option = Option("-emit-digester-baseline-path", .separate, attributes: [.noInteractive, .supplementaryOutput, .argumentIsPath], metaVar: "<path>", helpText: "Emit a baseline file for the module to <path> using the API digester")
  public static let compareToBaselinePath: Option = Option("-compare-to-baseline-path", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Compare the built module to the baseline at <path> and diagnose breaking changes using the API digester")
  public static let serializeBreakingChangesPath: Option = Option("-serialize-breaking-changes-path", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Serialize breaking changes found by the API digester to <path>")
  public static let digesterBreakageAllowlistPath: Option = Option("-digester-breakage-allowlist-path", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "The path to a list of permitted breaking changes the API digester should ignore")
  public static let digesterMode: Option = Option("-digester-mode", .separate, attributes: [.noInteractive], metaVar: "<api|abi>", helpText: "Whether the API digester should run in API or ABI mode (defaults to API checking)")

  public static var extraOptions: [Option] {
    return [
      Option.driverPrintGraphviz,
      Option.driverExplicitModuleBuild,
      Option.driverExperimentalExplicitModuleBuild,
      Option.driverScanDependenciesNonLib,
      Option.driverWarnUnusedOptions,
      Option.emitModuleSeparately,
      Option.emitModuleSeparatelyWMO,
      Option.noEmitModuleSeparatelyWMO,
      Option.useFrontendParseableOutput,
      Option.emitDigesterBaseline,
      Option.emitDigesterBaselinePath,
      Option.compareToBaselinePath,
      Option.serializeBreakingChangesPath,
      Option.digesterBreakageAllowlistPath,
      Option.digesterMode
    ]
  }
}
