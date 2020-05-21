//===--------------- ModuleDependencyBuildGeneration.swift ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic
import TSCUtility
import Foundation

extension Driver {
  /// For the current moduleDependencyGraph, plan the order and generate jobs
  /// for explicitly building all dependency modules.
  mutating func planExplicitModuleDependenciesCompile(dependencyGraph: InterModuleDependencyGraph)
  throws -> [Job] {
    var jobs: [Job] = []
    for (id, moduleInfo) in dependencyGraph.modules {
      // The generation of the main module file will be handled elsewhere in the driver.
      if (id.moduleName == dependencyGraph.mainModuleName) {
        continue
      }
      switch id {
        case .swift(let moduleName):
          let swiftModuleBuildJob = try genSwiftModuleDependencyBuildJob(moduleInfo: moduleInfo,
                                                                         moduleName: moduleName)
          jobs.append(swiftModuleBuildJob)
        case .clang(let moduleName):
          let clangModuleBuildJob = try genClangModuleDependencyBuildJob(moduleInfo: moduleInfo,
                                                                         moduleName: moduleName)
          jobs.append(clangModuleBuildJob)

      }
    }
    return jobs
  }

  /// For a given swift module dependency, generate a build job
  mutating private func genSwiftModuleDependencyBuildJob(moduleInfo: ModuleInfo,
                                                         moduleName: String) throws -> Job {
    // FIXIT: Needs more error handling
    guard case .swift(let swiftModuleDetails) = moduleInfo.details else {
      throw Error.malformedModuleDependency(moduleName, "no `details` object")
    }

    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: try VirtualPath(path: moduleInfo.modulePath), type: .swiftModule)
    ]
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")

    // Build the .swiftinterfaces file using a list of command line options specified in the
    // `details` field.
    guard let moduleInterfacePath = swiftModuleDetails.moduleInterfacePath else {
      throw Error.malformedModuleDependency(moduleName, "no `moduleInterfacePath` object")
    }
    inputs.append(TypedVirtualPath(file: try VirtualPath(path: moduleInterfacePath),
                                   type: .swiftInterface))
    try addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs)
    swiftModuleDetails.commandLine?.forEach { commandLine.appendFlag($0) }

    return Job(
      kind: .emitModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }

  /// For a given clang module dependency, generate a build job
  mutating private func genClangModuleDependencyBuildJob(moduleInfo: ModuleInfo,
                                                         moduleName: String) throws -> Job {
    // For clang modules, the Fast Dependency Scanner emits a list of source
    // files (with a .modulemap among them), and a list of compile command
    // options.
    // FIXIT: Needs more error handling
    guard case .clang(let clangModuleDetails) = moduleInfo.details else {
      throw Error.malformedModuleDependency(moduleName, "no `details` object")
    }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: try VirtualPath(path: moduleInfo.modulePath), type: .pcm)
    ]
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlags("-emit-pcm", "-module-name", moduleName)

    // The only required input is the .modulemap for this module.
    commandLine.append(Job.ArgTemplate.path(try VirtualPath(path: clangModuleDetails.moduleMapPath)))
    inputs.append(TypedVirtualPath(file: try VirtualPath(path: clangModuleDetails.moduleMapPath),
                                   type: .clangModuleMap))
    try addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs)
    clangModuleDetails.commandLine?.forEach { commandLine.appendFlags("-Xcc", $0) }

    return Job(
      kind: .generatePCM,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }
}
