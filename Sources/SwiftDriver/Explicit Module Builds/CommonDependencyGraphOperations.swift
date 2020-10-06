//===-------------- CommonDependencyGraphOperations.swift -----------------===//
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

public extension InterModuleDependencyGraph {
  /// An API to allow clients to accumulate InterModuleDependencyGraphs across mutiple main modules/targets
  /// into a single collection of discovered modules.
  static func mergeModules(
    from dependencyGraph: InterModuleDependencyGraph,
    into discoveredModules: inout ModuleInfoMap
  ) throws {
    for (moduleId, moduleInfo) in dependencyGraph.modules {
      try mergeModule(moduleId, moduleInfo, into: &discoveredModules)
    }
  }
}

internal extension InterModuleDependencyGraph {
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
      }
      moduleInfoMap[moduleId] = moduleInfo
    }
  }
}
