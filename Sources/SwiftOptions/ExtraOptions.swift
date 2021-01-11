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
  public static let driverExplicitModuleBuild: Option = Option("-experimental-explicit-module-build", .flag, attributes: [.helpHidden], helpText: "Prebuild module dependencies to make them explicit")
  public static let driverScanDependenciesNonLib: Option = Option("-nonlib-dependency-scanner", .flag, attributes: [.helpHidden], helpText: "Use calls to `swift-frontend -scan-dependencies` instead of dedicated dependency scanning library")
  public static let driverWarnUnusedOptions: Option = Option("-driver-warn-unused-options", .flag, attributes: [.helpHidden], helpText: "Emit warnings for any provided options which are unused by the driver.")
  public static let emitModuleSeparately: Option = Option("-experimental-emit-module-separately", .flag, attributes: [.helpHidden], helpText: "Emit module files as a distinct job")

  public static var extraOptions: [Option] {
    return [
      Option.driverPrintGraphviz,
      Option.driverExplicitModuleBuild,
      Option.driverScanDependenciesNonLib,
      Option.driverWarnUnusedOptions,
      Option.emitModuleSeparately
    ]
  }
}
