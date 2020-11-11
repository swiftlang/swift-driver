//===----------------- CommonDependencyOperations.swift -------------------===//
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

@_spi(Testing) public extension InterModuleDependencyOracle {
  /// An API to allow clients to accumulate InterModuleDependencyGraphs across mutiple main modules/targets
  /// into a single collection of discovered modules.
  func mergeModules(from dependencyGraph: InterModuleDependencyGraph) throws {
    for (moduleId, moduleInfo) in dependencyGraph.modules {
      try InterModuleDependencyGraph.mergeModule(moduleId, moduleInfo, into: &modules)
    }
  }

  // This is a backwards-compatibility shim to handle existing ModuleInfoMap-based API
  // used by SwiftPM
  func mergeModules(from moduleInfoMap: ModuleInfoMap) throws {
    for (moduleId, moduleInfo) in moduleInfoMap {
      try InterModuleDependencyGraph.mergeModule(moduleId, moduleInfo, into: &modules)
    }
  }
}

public extension InterModuleDependencyGraph {
  // This is a shim for backwards-compatibility with existing API used by SwiftPM.
  // TODO: After SwiftPM switches to using the oracle, this should be deleted.
  static func mergeModules(
    from dependencyGraph: InterModuleDependencyGraph,
    into discoveredModules: inout ModuleInfoMap
  ) throws {
    for (moduleId, moduleInfo) in dependencyGraph.modules {
      try mergeModule(moduleId, moduleInfo, into: &discoveredModules)
    }
  }
}


@_spi(Testing) public extension InterModuleDependencyGraph {
  /// Merge a module with a given ID and Info into a ModuleInfoMap
  static func mergeModule(_ moduleId: ModuleDependencyId,
                          _ moduleInfo: ModuleInfo,
                          into moduleInfoMap: inout ModuleInfoMap) throws {
    switch moduleId {
      case .swift:
        let prebuiltExternalModuleEquivalentId =
          ModuleDependencyId.swiftPrebuiltExternal(moduleId.moduleName)
        let placeholderEquivalentId =
          ModuleDependencyId.swiftPlaceholder(moduleId.moduleName)
        if moduleInfoMap[prebuiltExternalModuleEquivalentId] != nil ||
            moduleInfoMap[moduleId] != nil {
          // If the set of discovered modules contains a .swiftPrebuiltExternal or .swift module
          // with the same name, do not replace it.
          break
        } else if moduleInfoMap[placeholderEquivalentId] != nil {
          // Replace the placeholder module with a full .swift ModuleInfo
          // and fixup other modules' dependencies
          replaceModule(originalId: placeholderEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else {
          // Insert the new module
          moduleInfoMap[moduleId] = moduleInfo
        }

      case .swiftPrebuiltExternal:
        // If the set of discovered modules contains a .swift module with the same name,
        // replace it with the prebuilt version and fixup other modules' dependencies
        let swiftModuleEquivalentId = ModuleDependencyId.swift(moduleId.moduleName)
        let swiftPlaceholderEquivalentId = ModuleDependencyId.swiftPlaceholder(moduleId.moduleName)
        if moduleInfoMap[swiftModuleEquivalentId] != nil {
          // If the ModuleInfoMap contains an equivalent .swift module, replace it with the prebuilt
          // version and update all other modules' dependencies
          replaceModule(originalId: swiftModuleEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else if moduleInfoMap[swiftPlaceholderEquivalentId] != nil {
          // If the moduleInfoMap contains an equivalent .swiftPlaceholder module, replace it with
          // the prebuilt version and update all other modules' dependencies
          replaceModule(originalId: swiftPlaceholderEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else {
          // Insert the new module
          moduleInfoMap[moduleId] = moduleInfo
        }

      case .clang:
        guard let existingModuleInfo = moduleInfoMap[moduleId] else {
          moduleInfoMap[moduleId] = moduleInfo
          break
        }
        // If this module *has* been seen before, merge the module infos to capture
        // the super-set of so-far discovered dependencies of this module at various
        // PCMArg scanning actions.
        let combinedDependenciesInfo = mergeClangModuleInfoDependencies(moduleInfo,
                                                                        existingModuleInfo)
        replaceModule(originalId: moduleId, replacementId: moduleId,
                      replacementInfo: combinedDependenciesInfo, in: &moduleInfoMap)
      case .swiftPlaceholder:
        fatalError("Unresolved placeholder dependency at graph merge operation: \(moduleId)")
    }
  }

  /// Replace an existing module in the moduleInfoMap
  static func replaceModule(originalId: ModuleDependencyId, replacementId: ModuleDependencyId,
                            replacementInfo: ModuleInfo,
                            in moduleInfoMap: inout ModuleInfoMap) {
    precondition(moduleInfoMap[originalId] != nil)
    moduleInfoMap.removeValue(forKey: originalId)
    moduleInfoMap[replacementId] = replacementInfo
    if originalId != replacementId {
      updateDependencies(from: originalId, to: replacementId, in: &moduleInfoMap)
    }
  }

  /// Replace all references to the original module in other modules' dependencies with the new module.
  static func updateDependencies(from originalId: ModuleDependencyId,
                                 to replacementId: ModuleDependencyId,
                                 in moduleInfoMap: inout ModuleInfoMap) {
    for moduleId in moduleInfoMap.keys {
      var moduleInfo = moduleInfoMap[moduleId]!
      // Skip over placeholders, they do not have dependencies
      if case .swiftPlaceholder(_) = moduleId {
        continue
      }
      if let originalModuleIndex = moduleInfo.directDependencies?.firstIndex(of: originalId) {
        moduleInfo.directDependencies![originalModuleIndex] = replacementId;
        moduleInfoMap[moduleId] = moduleInfo
      }
    }
  }

  /// Given two moduleInfos of clang modules, merge them by combining their directDependencies and
  /// dependenciesCapturedPCMArgs and sourceFiles fields. These fields may differ across the same module
  /// scanned at different PCMArgs (e.g. -target option).
  static func mergeClangModuleInfoDependencies(_ firstInfo: ModuleInfo, _ secondInfo:ModuleInfo
  ) -> ModuleInfo {
    guard case .clang(let firstDetails) = firstInfo.details,
          case .clang(let secondDetails) = secondInfo.details
    else {
      fatalError("mergeClangModules expected two valid ClangModuleDetails objects.")
    }

    // As far as their dependencies go, these module infos are identical
    if firstInfo.directDependencies == secondInfo.directDependencies,
       firstDetails.dependenciesCapturedPCMArgs == secondDetails.dependenciesCapturedPCMArgs,
       firstInfo.sourceFiles == secondInfo.sourceFiles {
      return firstInfo
    }

    // Create a new moduleInfo that represents this module with combined dependency information
    let firstModuleSources = firstInfo.sourceFiles ?? []
    let secondModuleSources = secondInfo.sourceFiles ?? []
    let combinedSourceFiles = Array(Set(firstModuleSources + secondModuleSources))

    let firstModuleDependencies = firstInfo.directDependencies ?? []
    let secondModuleDependencies = secondInfo.directDependencies ?? []
    let combinedDependencies = Array(Set(firstModuleDependencies + secondModuleDependencies))

    let firstModuleCapturedPCMArgs = firstDetails.dependenciesCapturedPCMArgs ?? Set<[String]>()
    let secondModuleCapturedPCMArgs = secondDetails.dependenciesCapturedPCMArgs ?? Set<[String]>()
    let combinedCapturedPCMArgs = firstModuleCapturedPCMArgs.union(secondModuleCapturedPCMArgs)

    let combinedModuleDetails =
      ClangModuleDetails(moduleMapPath: firstDetails.moduleMapPath,
                         dependenciesCapturedPCMArgs: combinedCapturedPCMArgs,
                         contextHash: firstDetails.contextHash,
                         commandLine: firstDetails.commandLine)

    return ModuleInfo(modulePath: firstInfo.modulePath,
                      sourceFiles: combinedSourceFiles,
                      directDependencies: combinedDependencies,
                      details: .clang(combinedModuleDetails))
  }
}
