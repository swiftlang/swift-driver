//===------- IncrementalImportTestFramework.swift - Swift Testing ---------===//
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


// MARK: - CompileJob
struct CompileJob<Module: ModuleProtocol> {
  typealias Source = Module.Source

  let module: Module
  let sources: [Source]

  init(_ module: Module, _ sources: [Source]) {
    self.module = module
    self.sources = sources
  }
  init(_ module: Module) {
    self.init(module, module.sources)
  }

  func substituting(_ subs: [Source]) -> Self {
    return Self(module, sources.substituting(subs))
  }

  func mutate(_ context: TestContext) {
    sources.forEach {$0.mutate(context)}
  }

  var originals: [Source] {
    sources.map {$0.original}
  }

  func build(_ context: TestContext) -> [Source] {
    let allArgs = module.arguments(context, compiling: originals)

    var collector = CompiledSourceCollector<Source>()
    let diagnosticsEngine = DiagnosticsEngine(handlers: [
                                                Driver.stderrDiagnosticsHandler,
                                                {collector.process(diagnostic: $0)}])

    var driver = try! Driver(args: allArgs, diagnosticsEngine: diagnosticsEngine)
    let jobs = try! driver.planBuild()
    try! driver.run(jobs: jobs)

    return collector.compiledSources(context)
  }

  var fromScratchExpectations: [Source] {
    originals
  }
}

extension Array {
  static func building<Module: ModuleProtocol>(_ mods: Module...) -> [CompileJob<Module>]
  {
    mods.map(CompileJob.init)
  }

  func substituting<Module: ModuleProtocol>(_ subs: Module.Source...) -> Self
  where Element == CompileJob<Module>
  {
    map {$0.substituting(subs)}
  }
  // can also have inserting, deleting, etc
}
extension Array where Element: SourceProtocol {
  func substituting(_ subs: Self) -> Self {
    let subMap = subs.spm_createDictionary {sub in (sub.original, sub)}
    return map { subMap[$0.original, default: $0] }
  }
}

