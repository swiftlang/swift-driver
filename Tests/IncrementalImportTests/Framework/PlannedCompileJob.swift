//===--------------- PlannedCompileJob.swift - Swift Testing --------------===//
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

struct PlannedCompileJob<Module: ModuleProtocol> {
  typealias Source = Module.Source

  /// The module to be compiled
  let module: Module

  /// The sources to be compiled. May not always be all the sources in the module
  let sources: [Source]

  init(_ module: Module, _ sources: [Source]) {
    self.module = module
    self.sources = sources
  }

  func mutate(_ context: TestContext) {
    sources.forEach {$0.mutate(context)}
  }

  var originals: [Source] {
    sources.map {$0.original}
  }

  func build(_ context: TestContext) -> [Source] {
    writeOFM(context)
    let allArgs = module.arguments(context, compiling: originals)

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

  var fromScratchExpectations: [Source] {
    originals
  }
}
