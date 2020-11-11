//===--------------- PlaceholderDependencyResolution.swift ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic
import TSCUtility
import Foundation

@_spi(Testing) public extension InterModuleDependencyGraph {
  // Building a Swift module in Explicit Module Build mode requires passing all of its module
  // dependencies as explicit arguments to the build command.
  //
  // When the driver's clients (build systems) are planning a build that involves multiple
  // Swift modules, planning for each individual module may take place before its dependencies
  // have been built. This means that the dependency scanning action will not be able to
  // discover such modules. In such cases, the clients must provide the driver with information
  // about such external dependencies, including the path to where their compiled .swiftmodule
  // will be located, once built, and a full inter-module dependency graph for each such dependence.
  //
  // The driver will pass down the information about such external dependencies to the scanning
  // action, which will generate `placeholder` swift modules for them in the resulting dependency
  // graph. The driver will then use the complete dependency graph provided by
  // the client for each external dependency and use it to "resolve" the dependency's "placeholder"
  // module.
  //
  // Consider an example SwiftPM package with two targets: target B, and target A, where A
  // depends on B:
  // SwiftPM will process targets in a topological order and “bubble-up” each target’s
  // inter-module dependency graph to its dependees. First, SwiftPM will process B, and be
  // able to plan its full build because it does not have any target dependencies. Then the
  // driver is tasked with planning a build for A. SwiftPM will pass as input to the driver
  // the module dependency graph of its target’s dependencies, in this case, just the
  // dependency graph of B. The scanning action for module A will contain a placeholder module B,
  // which the driver will then resolve using B's full dependency graph provided by the client.

  /// Resolve all placeholder dependencies using external dependency information provided by the client
  mutating func resolvePlaceholderDependencies(for externalBuildArtifacts: ExternalBuildArtifacts,
                                               using dependencyOracle: InterModuleDependencyOracle)
  throws {
    let externalTargetModulePathMap = externalBuildArtifacts.0
    //let externalModuleInfoMap = externalBuildArtifacts.1
    let placeholderFilter : (ModuleDependencyId) -> Bool = {
      if case .swiftPlaceholder(_) = $0 {
        return true
      }
      return false
    }
    var placeholderModules = modules.keys.filter(placeholderFilter)

    // Resolve all target placeholder modules
    let placeholderTargetModules = placeholderModules.filter { externalTargetModulePathMap[$0] != nil }
    for moduleId in placeholderTargetModules {
      guard let placeholderModulePath = externalTargetModulePathMap[moduleId] else {
        throw Driver.Error.missingExternalDependency(moduleId.moduleName)
      }
      try resolveTargetPlaceholder(placeholderId: moduleId,
                                   placeholderPath: placeholderModulePath,
                                   dependencyOracle: dependencyOracle)
    }

    // Process remaining placeholders until there are none left
    placeholderModules = modules.keys.filter(placeholderFilter)
    while !placeholderModules.isEmpty {
      let moduleId = placeholderModules.first!
      let swiftModuleId = ModuleDependencyId.swift(moduleId.moduleName)

      guard dependencyOracle.getModuleInfo(of: swiftModuleId) != nil else {
        throw Driver.Error.missingExternalDependency(moduleId.moduleName)
      }
      let moduleInfo = dependencyOracle.getModuleInfo(of: swiftModuleId)!

      // Insert the resolved module, replacing the placeholder.
      try Self.mergeModule(swiftModuleId, moduleInfo, into: &modules)

      // Traverse and add all of this external module's dependencies to the current graph.
      try resolvePlaceholderModuleDependencies(moduleId: swiftModuleId,
                                               dependencyOracle: dependencyOracle)

      // Update the set of remaining placeholders to resolve
      placeholderModules = modules.keys.filter(placeholderFilter)
    }
  }
}

fileprivate extension InterModuleDependencyGraph {
  /// Resolve a placeholder dependency that is an external target.
  mutating func resolveTargetPlaceholder(placeholderId: ModuleDependencyId,
                                         placeholderPath: AbsolutePath,
                                         dependencyOracle: InterModuleDependencyOracle)
  throws {
    // For this placeholder dependency, generate a new module info containing only the pre-compiled
    // module path, and insert it into the current module's dependency graph,
    // replacing equivalent placeholder module.
    //
    // For all dependencies of this placeholder (direct and transitive), insert them
    // into this module's graph.
    //   - Swift dependencies are inserted as-is
    //   - Clang dependencies are inserted as-is, if a matching Clang module is already found
    //     in this module's graph, we merge moduleInfos of the two modules, in order to obtain
    //     a super-set of their dependencies at all possible PCMArgs variants.
    //
    // The placeholder is resolved into a .swiftPrebuiltExternal module in the dependency graph.
    // The placeholder's corresponding module may appear in the externalModuleInfoMap as either
    // a .swift module or a .swiftPrebuiltExternal module if it had been resolved earlier
    // in the multi-module build planning context.
    let swiftModuleId = ModuleDependencyId.swift(placeholderId.moduleName)
    let swiftPrebuiltModuleId = ModuleDependencyId.swiftPrebuiltExternal(placeholderId.moduleName)

    let externalModuleId: ModuleDependencyId
    if dependencyOracle.getModuleInfo(of: swiftModuleId) != nil {
      externalModuleId = swiftModuleId
    } else if dependencyOracle.getModuleInfo(of: swiftPrebuiltModuleId) != nil {
      externalModuleId = swiftPrebuiltModuleId
    } else {
      throw Driver.Error.missingExternalDependency(placeholderId.moduleName)
    }

    let externalModuleInfo = dependencyOracle.getModuleInfo(of: externalModuleId)!
    let newExternalModuleDetails =
      SwiftPrebuiltExternalModuleDetails(compiledModulePath: placeholderPath.description)
    let newInfo = ModuleInfo(modulePath: placeholderPath.description,
                             sourceFiles: [],
                             directDependencies: externalModuleInfo.directDependencies,
                             details: .swiftPrebuiltExternal(newExternalModuleDetails))

    // Insert the resolved module, replacing the placeholder.
    try Self.mergeModule(swiftPrebuiltModuleId, newInfo, into: &modules)

    // Traverse and add all of this external target's dependencies to the current graph.
    try resolvePlaceholderModuleDependencies(moduleId: externalModuleId,
                                             dependencyOracle: dependencyOracle)
  }

  /// Resolve all dependencies of a placeholder module (direct and transitive), but merging them into the current graph.
  mutating func resolvePlaceholderModuleDependencies(moduleId: ModuleDependencyId,
                                                     dependencyOracle: InterModuleDependencyOracle)
  throws {
    guard let resolvingModuleInfo = dependencyOracle.getModuleInfo(of: moduleId) else {
      throw Driver.Error.missingExternalDependency(moduleId.moduleName)
    }

    // Breadth-first traversal of all the dependencies of this module
    var visited: Set<ModuleDependencyId> = []
    var toVisit: [ModuleDependencyId] = resolvingModuleInfo.directDependencies ?? []
    var currentIndex = 0
    while let currentId = toVisit[currentIndex...].first {
      currentIndex += 1
      visited.insert(currentId)
      guard let currentInfo = dependencyOracle.getModuleInfo(of: currentId) else {
        throw Driver.Error.missingExternalDependency(currentId.moduleName)
      }

      try Self.mergeModule(currentId, currentInfo, into: &modules)

      let currentDependencies = currentInfo.directDependencies ?? []
      for childId in currentDependencies where !visited.contains(childId) {
        if !toVisit.contains(childId) {
          toVisit.append(childId)
        }
      }
    }
  }
}
