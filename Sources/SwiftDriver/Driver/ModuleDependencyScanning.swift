//===--------------- ModuleDependencyScanning.swift -----------------------===//
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
import Foundation
import TSCBasic

extension Driver {
  /// Produce a Swift job to to compute the full module dependency graph
  /// in advance, allowing the driver to schedule explicit module builds.
  mutating func moduleDependencyGraphJob() throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-emit-imported-modules")

    if parsedOptions.hasArgument(.parseStdlib) {
      commandLine.appendFlag(.disableObjcAttrRequiresFoundationModule)
    }

    try addCommonFrontendOptions(commandLine: &commandLine)
    // FIXME: MSVC runtime flags

    commandLine.append(contentsOf: inputFiles.map { Job.ArgTemplate.path($0.file)})
    return Job(
      kind: .moduleDependencyGraph,
      tool: swiftCompiler,
      commandLine: commandLine,
      displayInputs: inputFiles,
      inputs: inputFiles,
      outputs: []
    )
  }

  private class ModuleDependencyGraphExecutionDelegate : JobExecutorDelegate {
    var moduleDependencyGraph: ModuleDependencyGraph? = nil

    func jobStarted(job: Job, arguments: [String], pid: Int) {
    }

    func jobFinished(job: Job, result: ProcessResult, pid: Int) {
      switch result.exitStatus {
      case .terminated(code: 0):
        guard let outputData = try? Data(result.utf8Output().utf8) else {
          return
        }

        let decoder = JSONDecoder()
        moduleDependencyGraph = try? decoder.decode(
            ModuleDependencyGraph.self, from: outputData)

      default:
        break;
      }
    }
  }

  /// Precompute the dependencies for a given Swift compilation, producing a
  /// complete dependency graph including all Swift and C module files and
  /// source files.
  mutating func computeModuleDependencyGraph() throws
      -> ModuleDependencyGraph? {
    let job = try moduleDependencyGraphJob()
    let resolver = try ArgsResolver()
    let executorDelegate = ModuleDependencyGraphExecutionDelegate()
    let jobExecutor = JobExecutor(
        jobs: [job], resolver: resolver,
        executorDelegate: executorDelegate
    )
    try jobExecutor.execute(env: [:])

    // FIXME: Handle errors properly
    return executorDelegate.moduleDependencyGraph
  }
}
