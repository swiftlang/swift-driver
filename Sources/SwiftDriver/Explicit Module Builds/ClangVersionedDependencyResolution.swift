//===-------------- ClangVersionedDependencyResolution.swift --------------===//
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

import Foundation

/// A map from a module identifier to a set of module dependency graphs
/// Used to compute distinct graphs corresponding to different target versions for a given clang module
public typealias ModuleVersionedGraphMap = [ModuleDependencyId: [InterModuleDependencyGraph]]

internal extension Driver {
  // Dependency scanning results may vary depending on the target version specified on the
  // dependency scanning action. If the scanning action is performed at a fixed target, and the
  // scanned module is later compiled with a higher version target, miscomputation may occur
  // due to dependencies present only at the higher version number and thus not detected by
  // the dependency scanner. We must ensure to re-scan Clang modules at all targets at which
  // they will be compiled and record a super-set of the module's dependencies at all targets.
  /// For each clang module, compute its dependencies at all targets at which it will be compiled.
  mutating func resolveVersionedClangDependencies(dependencyGraph: inout InterModuleDependencyGraph)
  throws {
    // Traverse the dependency graph, collecting extraPCMArgs along each path
    // to all Clang modules, and compute a set of distinct PCMArgs across all paths to a
    // given Clang module in the graph.
    let modulePCMArgsSetMap = try dependencyGraph.computePCMArgSetsForClangModules()
    var moduleVersionedGraphMap: [ModuleDependencyId: [InterModuleDependencyGraph]] = [:]
    for (moduleId, pcmArgSet) in modulePCMArgsSetMap {
      for pcmArgs in pcmArgSet {
        let pcmSpecificDepGraph = try scanClangModule(moduleId: moduleId,
                                                      pcmArgs: pcmArgs)
        if moduleVersionedGraphMap[moduleId] != nil {
          moduleVersionedGraphMap[moduleId]!.append(pcmSpecificDepGraph)
        } else {
          moduleVersionedGraphMap[moduleId] = [pcmSpecificDepGraph]
        }
      }
    }

    try dependencyGraph.resolveVersionedClangModules(using: moduleVersionedGraphMap)
  }
}

private extension InterModuleDependencyGraph {
  /// For each module scanned at multiple target versions, combine their dependencies across version-specific graphs.
  mutating func resolveVersionedClangModules(using versionedGraphMap: ModuleVersionedGraphMap)
  throws {
    // Process each re-scanned module and its collection of graphs
    for (moduleId, graphList) in versionedGraphMap {
      for versionedGraph in graphList {
        // We must update dependencies for each module in the versioned graph, not just
        // the top-level re-scanned module itself.
        for rescannedModuleId in versionedGraph.modules.keys {
          guard let versionedModuleInfo = versionedGraph.modules[rescannedModuleId] else {
            throw Driver.Error.missingModuleDependency(moduleId.moduleName)
          }
          // If the main graph already contains this module, update its dependencies
          if var currentModuleInfo = modules[rescannedModuleId] {
            versionedModuleInfo.directDependencies?.forEach { dependencyId in
              // If a not-seen-before dependency has been found, add it to the info
              if !currentModuleInfo.directDependencies!.contains(dependencyId) {
                currentModuleInfo.directDependencies!.append(dependencyId)
              }
            }
            // Update the moduleInfo with the one whose dependencies consist of a super-set
            // of dependencies across all of the versioned dependency graphs
            modules[rescannedModuleId] = currentModuleInfo
          } else {
            // If the main graph does not yet contain this module, add it to the graph
            modules[rescannedModuleId] = versionedModuleInfo
          }
        }
      }
    }
  }

  /// DFS from the main module to all clang modules, accumulating distinct
  /// PCMArgs along all paths to a given Clang module
  func computePCMArgSetsForClangModules() throws -> [ModuleDependencyId : Set<[String]>] {
    let mainModuleId: ModuleDependencyId = .swift(mainModuleName)
    var pcmArgSetMap: [ModuleDependencyId : Set<[String]>] = [:]

    func visit(_ moduleId: ModuleDependencyId,
               pathPCMArtSet: Set<[String]>,
               pcmArgSetMap: inout [ModuleDependencyId : Set<[String]>])
    throws {
      switch moduleId {
        case .swift:
          // Add extraPCMArgs of the visited node to the current path set
          // and proceed to visit all direct dependencies
          let modulePCMArgs = try swiftModulePCMArgs(of: moduleId)
          var newPathPCMArgSet = pathPCMArtSet
          newPathPCMArgSet.insert(modulePCMArgs)
          for dependencyId in try moduleInfo(of: moduleId).directDependencies! {
            try visit(dependencyId,
                      pathPCMArtSet: newPathPCMArgSet,
                      pcmArgSetMap: &pcmArgSetMap)
          }
        case .clang:
          // Add current path's PCMArgs to the SetMap and stop traversal
          if pcmArgSetMap[moduleId] != nil {
            pathPCMArtSet.forEach { pcmArgSetMap[moduleId]!.insert($0) }
          } else {
            pcmArgSetMap[moduleId] = pathPCMArtSet
          }
          return
        case .swiftPlaceholder:
          fatalError("Unresolved placeholder dependencies at planning stage: \(moduleId)")
      }
    }

    try visit(mainModuleId,
              pathPCMArtSet: [],
              pcmArgSetMap: &pcmArgSetMap)
    return pcmArgSetMap
  }
}
