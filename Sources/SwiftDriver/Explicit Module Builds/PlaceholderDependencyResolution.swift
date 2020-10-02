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
  mutating func resolvePlaceholderDependencies(using externalBuildArtifacts: ExternalBuildArtifacts)
  throws {
    let externalTargetModulePathMap = externalBuildArtifacts.0
    let externalModuleInfoMap = externalBuildArtifacts.1
    let placeholderModules = modules.keys.filter {
      if case .swiftPlaceholder(_) = $0 {
        return true
      }
      return false
    }

    // Resolve all target placeholder modules
    let placeholderTargetModules = placeholderModules.filter { externalTargetModulePathMap[$0] != nil }
    for moduleId in placeholderTargetModules {
      guard let placeholderModulePath = externalTargetModulePathMap[moduleId] else {
        throw Driver.Error.missingExternalDependency(moduleId.moduleName)
      }

      try resolveTargetPlaceholder(placeholderModuleId: moduleId,
                                   placeholderModulePath: placeholderModulePath,
                                   externalModuleInfoMap: externalModuleInfoMap)
    }
  }
}

fileprivate extension InterModuleDependencyGraph {
  /// Resolve a placeholder dependency that is an external target.
  mutating func resolveTargetPlaceholder(placeholderModuleId: ModuleDependencyId,
                                         placeholderModulePath: AbsolutePath,
                                         externalModuleInfoMap: ModuleInfoMap)
  throws {
    // For this placeholder dependency, generate a new module info containing only the pre-compiled
    // module path, and insert it into the current module's dependency graph,
    // replacing equivalent placeholder module.
    //
    // For all dependencies of this placeholder (direct and transitive), insert them
    // into this module's graph.
    //   - Swift dependencies are inserted with a specified pre-compiled module path
    //   - Clang dependencies, because PCM modules file names encode the specific pcmArguments
    //     of their dependees, we cannot use pre-built files here because we do not always know
    //     which target they corrspond to, nor do we have a way to map from a certain target to a
    //     specific pcm file. Because of this, all PCM dependencies, direct and transitive, have to
    //     be built for all modules. We merge moduleInfos of such dependencies with ones that are
    //     already in the current graph, in order to obtain a super-set of their dependencies
    //     at all possible PCMArgs variants.
    // FIXME: Implement a stable hash for generated .pcm filenames in order to be able to re-use
    // modules built by external dependencies here.
    let correspondingSwiftModuleId = ModuleDependencyId.swift(placeholderModuleId.moduleName)
    guard let placeholderModuleInfo = externalModuleInfoMap[correspondingSwiftModuleId]
    else {
      throw Driver.Error.missingExternalDependency(placeholderModuleId.moduleName)
    }
    guard case .swift(let placholderSwiftDetails) = placeholderModuleInfo.details else {
      throw Driver.Error.malformedModuleDependency(placeholderModuleId.moduleName,
                                                   "no Swift `details` object")
    }
    let newSwiftDetails =
      SwiftModuleDetails(compiledModulePath: placeholderModulePath.description,
                         extraPcmArgs: placholderSwiftDetails.extraPcmArgs!)
    let newInfo = ModuleInfo(modulePath: placeholderModulePath.description,
                             sourceFiles: nil,
                             directDependencies: placeholderModuleInfo.directDependencies,
                             details: .swift(newSwiftDetails))
    try insertOrReplaceModule(moduleId: correspondingSwiftModuleId, moduleInfo: newInfo)

    // Traverse and add all of this external target's dependencies to the current graph.
    try resolvePlaceholderModuleDependencies(moduleId: correspondingSwiftModuleId,
                                             externalModuleInfoMap: externalModuleInfoMap)
  }

  /// Resolve all dependencies of a placeholder module (direct and transitive), but merging them into the current graph.
  mutating func resolvePlaceholderModuleDependencies(moduleId: ModuleDependencyId,
                                                     externalModuleInfoMap: ModuleInfoMap) throws {
    guard let resolvingModuleInfo = externalModuleInfoMap[moduleId] else {
      throw Driver.Error.missingExternalDependency(moduleId.moduleName)
    }

    // Breadth-first traversal of all the dependencies of this module
    var visited: Set<ModuleDependencyId> = []
    var toVisit: [ModuleDependencyId] = resolvingModuleInfo.directDependencies ?? []
    var currentIndex = 0
    while let currentId = toVisit[currentIndex...].first {
      currentIndex += 1
      visited.insert(currentId)
      guard let currentInfo = externalModuleInfoMap[currentId] else {
        throw Driver.Error.missingExternalDependency(currentId.moduleName)
      }

      try mergeExternalModule(moduleId: currentId, moduleInfo: currentInfo)

      let currentDependencies = currentInfo.directDependencies ?? []
      for childId in currentDependencies where !visited.contains(childId) {
        if !toVisit.contains(childId) {
          toVisit.append(childId)
        }
      }
    }
  }

  /// Merge a module into this graph.
  mutating func mergeExternalModule(moduleId: ModuleDependencyId, moduleInfo: ModuleInfo) throws {
    switch moduleId {
      case .swift(_):
        guard case .swift(let details) = moduleInfo.details else {
          throw Driver.Error.malformedModuleDependency(mainModuleName, "no Swift `details` object")
        }
        let compiledModulePath : String
        if let explicitModulePath = details.explicitCompiledModulePath {
          compiledModulePath = explicitModulePath
        } else {
          compiledModulePath = moduleInfo.modulePath
        }

        // We require the extraPCMArgs of all swift modules in order to
        // re-scan their clang module dependencies.
        guard let pcmArgs = details.extraPcmArgs else {
          throw Driver.Error.missingPCMArguments(moduleId.moduleName)
        }
        let extraPCMArgs : [String] = pcmArgs

        let swiftDetails =
          SwiftModuleDetails(compiledModulePath: compiledModulePath,
                             extraPcmArgs: extraPCMArgs)
        let newInfo = ModuleInfo(modulePath: moduleInfo.modulePath.description,
                                 sourceFiles: nil,
                                 directDependencies: moduleInfo.directDependencies,
                                 details: ModuleInfo.Details.swift(swiftDetails))
        try insertOrReplaceModule(moduleId: moduleId, moduleInfo: newInfo)
      case .clang(_):
        let newModuleInfo: ModuleInfo
        if modules[moduleId] == nil {
          newModuleInfo = moduleInfo
        } else {
          // Merge the info of this Clang
          // module with the corresponding info from the externalModuleInfoMap in order
          // to combine the module dependencies discovered via batched PCMArg-specific re-scans.
          newModuleInfo = Self.mergeClangModuleInfoDependencies(moduleInfo, modules[moduleId]!)
        }
        try insertOrReplaceModule(moduleId: moduleId, moduleInfo: newModuleInfo)
      case .swiftPlaceholder(_):
        try insertOrReplaceModule(moduleId: moduleId, moduleInfo: moduleInfo)
    }
  }

  /// Insert a module into the handler's dependency graph. If a module with this identifier already exists,
  /// replace it's module with a moduleInfo that contains a path to an existing prebuilt .swiftmodule
  mutating func insertOrReplaceModule(moduleId: ModuleDependencyId,
                                      moduleInfo: ModuleInfo) throws {
    // Check for placeholders to be replaced
    if modules[ModuleDependencyId.swiftPlaceholder(moduleId.moduleName)] != nil {
      try replaceModule(originalId: .swiftPlaceholder(moduleId.moduleName), replacementId: moduleId,
                        replacementInfo: moduleInfo)
    }
    // Check for modules with the same Identifier, and replace if found
    else if modules[moduleId] != nil {
      try replaceModule(originalId: moduleId, replacementId: moduleId, replacementInfo: moduleInfo)
    // This module is new to the current dependency graph
    } else {
      modules[moduleId] = moduleInfo
    }
  }

  /// Replace a module with a new one. Replace all references to the original module in other modules' dependencies
  /// with the new module.
  mutating func replaceModule(originalId: ModuleDependencyId,
                                     replacementId: ModuleDependencyId,
                                     replacementInfo: ModuleInfo) throws {
    modules.removeValue(forKey: originalId)
    modules[replacementId] = replacementInfo
    for moduleId in modules.keys {
      var moduleInfo = modules[moduleId]!
      // Skip over other placeholders, they do not have dependencies
      if case .swiftPlaceholder(_) = moduleId {
        continue
      }
      if let originalModuleIndex = moduleInfo.directDependencies?.firstIndex(of: originalId) {
        moduleInfo.directDependencies![originalModuleIndex] = replacementId;
      }
      modules[moduleId] = moduleInfo
    }
  }
}

/// Used for creating new module infos during placeholder dependency resolution
/// Modules created this way only contain a path to a pre-built module file.
private extension SwiftModuleDetails {
  init(compiledModulePath: String, extraPcmArgs: [String]) {
    self.moduleInterfacePath = nil
    self.compiledModuleCandidates = nil
    self.explicitCompiledModulePath = compiledModulePath
    self.bridgingHeaderPath = nil
    self.bridgingSourceFiles = nil
    self.commandLine = nil
    self.extraPcmArgs = extraPcmArgs
    self.isFramework = false
  }
}

/// An extension to allow clients to accumulate InterModuleDependencyGraphs across mutiple main modules/targets
/// into a single collection of discovered modules.
public extension InterModuleDependencyGraph {
  static func mergeModules(
    from dependencyGraph: InterModuleDependencyGraph,
    into discoveredModules: inout ModuleInfoMap
  ) throws {
    for (moduleId, moduleInfo) in dependencyGraph.modules {
      switch moduleId {
        case .swift:
          discoveredModules[moduleId] = moduleInfo
        case .clang:
          guard let existingModuleInfo = discoveredModules[moduleId] else {
            discoveredModules[moduleId] = moduleInfo
            break
          }
          // If this module *has* been seen before, merge the module infos to capture
          // the super-set of so-far discovered dependencies of this module at various
          // PCMArg scanning actions.
          let combinedDependenciesInfo =
            Self.mergeClangModuleInfoDependencies(moduleInfo,
                                                  existingModuleInfo)
          discoveredModules[moduleId] = combinedDependenciesInfo
        case .swiftPlaceholder:
          fatalError("Unresolved placeholder dependencies at manifest build stage: \(moduleId)")
      }
    }
  }
}
