//===---------------- BuildJob.swift - Swift Testing -------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

/// Everything needed to invoke the driver and build a module.
/// (See `TestProtocol`.)
struct BuildJob<Module: ModuleProtocol> {
  typealias SourceVersion = Module.SourceVersion

  /// The module to be compiled
  let module: Module

  /// The source versions to be compiled. Can vary.
  let sourceVersions: [SourceVersion]

  init(_ module: Module, _ sourceVersions: [SourceVersion]) {
    self.module = module
    self.sourceVersions = sourceVersions
  }

  /// Update the contents of the source files.
  func updateChangedSources(_ context: TestContext) {
    sourceVersions.forEach {$0.updateIfChanged(context)}
  }

  /// Returns the basenames without extension of the compiled source files.
  func run(_ context: TestContext) -> [String] {
    writeOFM(context)
    let allArgs = arguments(context)

    var collector = CompiledSourceCollector()
    let handlers = [
        {collector.handle(diagnostic: $0)},
        context.verbose ? Driver.stderrDiagnosticsHandler : nil
      ]
      .compactMap {$0}
    let diagnosticsEngine = DiagnosticsEngine(handlers: handlers)

    var driver = try! Driver(args: allArgs, diagnosticsEngine: diagnosticsEngine)
    let jobs = try! driver.planBuild()
    try! driver.run(jobs: jobs)

    return collector.compiledSources(context)
  }

  private func writeOFM(_ context: TestContext) {
    OutputFileMapCreator.write(
      module: module.name,
      inputPaths: sourceVersions.map {$0.path(context)},
      derivedData: module.derivedDataPath(context),
      to: module.outputFileMapPath(context))
  }

  func arguments(_ context: TestContext) -> [String] {
    var libraryArgs: [String] {
      ["-parse-as-library",
       "-emit-module-path", module.swiftmodulePath(context).pathString]
    }
    var appArgs: [String] {
      let swiftModules = module.imports .map {
        $0.swiftmodulePath(context).parentDirectory.pathString
      }
      return swiftModules.flatMap { ["-I", $0, "-F", $0] }
    }
    var incrementalImportsArgs: [String] {
      // ["-\(withIncrementalImports ? "en" : "dis")able-incremental-imports"]
      context.withIncrementalImports
        ? [ "-enable-incremental-imports"]
        : ["-disable-incremental-imports"]
    }
    return Array(
    [
      [
        "swiftc",
        "-no-color-diagnostics",
        "-incremental",
        "-driver-show-incremental",
        "-driver-show-job-lifecycle",
        "-c",
        "-module-name", module.nameToImport,
        "-output-file-map", module.outputFileMapPath(context).pathString,
      ],
      incrementalImportsArgs,
      module.isLibrary ? libraryArgs : appArgs,
      sourceVersions.map {$0.path(context).pathString}
    ].joined())
  }
}
