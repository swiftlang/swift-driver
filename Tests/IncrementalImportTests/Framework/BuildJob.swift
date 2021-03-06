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
  typealias Source = Module.Source

  /// The module to be compiled
  let module: Module

  /// The source versions to be compiled. Can vary.
  let sources: [Source]

  init(_ module: Module, _ sources: [Source]) {
    self.module = module
    self.sources = sources
  }

  /// Update the contents of the source files.
  func updateChangedSources(_ context: TestContext) {
    sources.forEach {$0.updateIfChanged(context)}
  }

  /// The original versions of each source version.
  var originals: [Source] {
    sources.map {$0.original}
  }

  func run(_ context: TestContext) -> [Source] {
    writeOFM(context)
    let allArgs = arguments(context)

    var collector = CompiledSourceCollector<Source>()
    let diagnosticsEngine = DiagnosticsEngine(handlers: [
                                                Driver.stderrDiagnosticsHandler,
                                                {collector.handle(diagnostic: $0)}])

    var driver = try! Driver(args: allArgs, diagnosticsEngine: diagnosticsEngine)
    let jobs = try! driver.planBuild()
    try! driver.run(jobs: jobs)

    return collector.compiledSources(context)
  }

  private func writeOFM(_ context: TestContext) {
    OutputFileMapCreator.write(
      module: module.name,
      inputPaths: sources.map {$0.sourcePath(context)},
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
        ? ["-enable-experimental-cross-module-incremental-build"]
        : []
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
      sources.map {$0.sourcePath(context).pathString}
    ].joined())
  }
}
