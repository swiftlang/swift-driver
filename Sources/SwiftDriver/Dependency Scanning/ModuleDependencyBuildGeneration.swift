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
  mutating func planExplicitModuleDependenciesCompile(
    dependencyGraph: InterModuleDependencyGraph
  ) throws -> [Job] {
    var jobs: [Job] = []
    for (id, moduleInfo) in dependencyGraph.modules {
      // The generation of the main module file will be handled elsewhere in the driver.
      if (id.moduleName == dependencyGraph.mainModuleName) {
        continue
      }
      switch id {
        case .swift(let moduleName):
          let swiftModuleBuildJob =
            try genSwiftModuleDependencyBuildJob(moduleInfo: moduleInfo,
                                                 moduleName: moduleName,
                                                 dependencyGraph: dependencyGraph)
          jobs.append(swiftModuleBuildJob)
        case .clang(let moduleName):
          let clangModuleBuildJob =
            try genClangModuleDependencyBuildJob(moduleInfo: moduleInfo,
                                                 moduleName: moduleName,
                                                 dependencyGraph: dependencyGraph)
          jobs.append(clangModuleBuildJob)
      }
    }
    return jobs
  }

  /// For a given swift module dependency, generate a build job
  mutating private func genSwiftModuleDependencyBuildJob(moduleInfo: ModuleInfo,
                                                         moduleName: String,
                                                         dependencyGraph: InterModuleDependencyGraph
  ) throws -> Job {
    guard case .swift(let swiftModuleDetails) = moduleInfo.details else {
      throw Error.malformedModuleDependency(moduleName, "no `details` object")
    }

    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: try VirtualPath(path: moduleInfo.modulePath), type: .swiftModule)
    ]
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    // First, take the command line options provided in the dependency information
    swiftModuleDetails.commandLine?.forEach { commandLine.appendFlags($0) }

    if (swiftModuleDetails.commandLine == nil ||
          !swiftModuleDetails.commandLine!.contains("-frontend")) {
      commandLine.appendFlag("-frontend")
    }

    try addModuleDependencies(moduleInfo: moduleInfo,
                              dependencyGraph: dependencyGraph,
                              inputs: &inputs,
                              commandLine: &commandLine)

    // Build the .swiftinterfaces file using a list of command line options specified in the
    // `details` field.
    guard let moduleInterfacePath = swiftModuleDetails.moduleInterfacePath else {
      throw Error.malformedModuleDependency(moduleName, "no `moduleInterfacePath` object")
    }
    inputs.append(TypedVirtualPath(file: try VirtualPath(path: moduleInterfacePath),
                                   type: .swiftInterface))
    try addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs)

    return Job(
      moduleName: moduleName,
      kind: .emitModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }

  /// For a given clang module dependency, generate a build job
  mutating private func genClangModuleDependencyBuildJob(moduleInfo: ModuleInfo,
                                                         moduleName: String,
                                                         dependencyGraph: InterModuleDependencyGraph
  ) throws -> Job {
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

    // First, take the command line options provided in the dependency information
    clangModuleDetails.commandLine?.forEach { commandLine.appendFlags($0) }

    if (clangModuleDetails.commandLine == nil ||
          !clangModuleDetails.commandLine!.contains("-frontend")) {
      commandLine.appendFlag("-frontend")
    }
    commandLine.appendFlags("-emit-pcm", "-module-name", moduleName)

    try addModuleDependencies(moduleInfo: moduleInfo,
                              dependencyGraph: dependencyGraph,
                              inputs: &inputs,
                              commandLine: &commandLine)

    // The only required input is the .modulemap for this module.
    // Command line options in the dependency scanner output will include the required modulemap,
    // so here we must only add it to the list of inputs.
    inputs.append(TypedVirtualPath(file: try VirtualPath(path: clangModuleDetails.moduleMapPath),
                                   type: .clangModuleMap))
    try addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs)

    return Job(
      moduleName: moduleName,
      kind: .generatePCM,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }


  /// For the specified module, update its command line flags and inputs
  /// to use explicitly-built module dependencies.
  private func addModuleDependencies(moduleInfo: ModuleInfo,
                                     dependencyGraph: InterModuleDependencyGraph,
                                     inputs: inout [TypedVirtualPath],
                                     commandLine: inout [Job.ArgTemplate]) throws {
    // Prohibit the frontend from implicitly building textual modules into binary modules.
    commandLine.appendFlags("-disable-implicit-swift-modules", "-Xcc", "-Xclang", "-Xcc",
                            "-fno-implicit-modules")
    for moduleId in moduleInfo.directDependencies {
      guard let dependencyInfo = dependencyGraph.modules[moduleId] else {
        throw Error.missingModuleDependency(moduleId.moduleName)
      }
      try addModuleAsExplicitDependency(moduleInfo: dependencyInfo,
                                        dependencyGraph: dependencyGraph,
                                        commandLine: &commandLine, inputs: &inputs)
    }
  }
}
