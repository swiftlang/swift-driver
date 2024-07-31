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

import func TSCBasic.topologicalSort
import protocol TSCBasic.FileSystem

@_spi(Testing) public extension InterModuleDependencyGraph {
  /// For targets that are built alongside the driver's current module, the scanning action will report them as
  /// textual targets to be built from source. Because we can rely on these targets to have been built prior
  /// to the driver's current target, we resolve such external targets as prebuilt binary modules, in the graph.
  mutating func resolveExternalDependencies(for externalTargetModuleDetailsMap: ExternalTargetModuleDetailsMap)
  throws {
    for (externalModuleId, externalModuleDetails) in externalTargetModuleDetailsMap {
      let externalModulePath = externalModuleDetails.path
      // Replace the occurrence of a Swift module to-be-built from source-file
      // to an info that describes a pre-built binary module.
      let swiftModuleId: ModuleDependencyId = .swift(externalModuleId.moduleName)
      let prebuiltModuleId: ModuleDependencyId = .swiftPrebuiltExternal(externalModuleId.moduleName)
      if let currentInfo = modules[swiftModuleId],
         externalModuleId.moduleName != mainModuleName {
        let newExternalModuleDetails =
        SwiftPrebuiltExternalModuleDetails(compiledModulePath:
                                            TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                           isFramework: externalModuleDetails.isFramework)
        let newInfo = ModuleInfo(modulePath: TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                 sourceFiles: [],
                                 directDependencies: currentInfo.directDependencies,
                                 linkLibraries: currentInfo.linkLibraries,
                                 details: .swiftPrebuiltExternal(newExternalModuleDetails))
        Self.replaceModule(originalId: swiftModuleId, replacementId: prebuiltModuleId,
                           replacementInfo: newInfo, in: &modules)
      } else if let currentPrebuiltInfo = modules[prebuiltModuleId] {
        // Just update the isFramework bit on this prebuilt module dependency
        let newExternalModuleDetails =
        SwiftPrebuiltExternalModuleDetails(compiledModulePath:
                                            TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                           isFramework: externalModuleDetails.isFramework)
        let newInfo = ModuleInfo(modulePath: TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                 sourceFiles: [],
                                 directDependencies: currentPrebuiltInfo.directDependencies,
                                 linkLibraries: currentPrebuiltInfo.linkLibraries,
                                 details: .swiftPrebuiltExternal(newExternalModuleDetails))
        Self.replaceModule(originalId: prebuiltModuleId, replacementId: prebuiltModuleId,
                           replacementInfo: newInfo, in: &modules)
      }
    }
  }
}

extension InterModuleDependencyGraph {
  var topologicalSorting: [ModuleDependencyId] {
    get throws {
      try topologicalSort(Array(modules.keys),
                          successors: {
        var dependencies: [ModuleDependencyId] = []
        let moduleInfo = try moduleInfo(of: $0)
        dependencies.append(contentsOf: moduleInfo.directDependencies ?? [])
        if case .swift(let swiftModuleDetails) = moduleInfo.details {
          dependencies.append(contentsOf: swiftModuleDetails.swiftOverlayDependencies ?? [])
        }
        return dependencies
      })
    }
  }

  /// Compute a set of modules that are "reachable" (form direct or transitive dependency)
  /// from each module in the graph.
  /// This routine relies on the fact that the dependency graph is acyclic. A lack of cycles means
  /// we can apply a simple algorithm:
  /// for each v ∈ V { T(v) = { v } }
  /// for v ∈ V in reverse topological order {
  ///   for each (v, w) ∈ E {
  ///     T(v) = T(v) ∪ T(w)
  ///   }
  /// }
  @_spi(Testing) public func computeTransitiveClosure() throws -> [ModuleDependencyId : Set<ModuleDependencyId>] {
    let topologicalIdList = try self.topologicalSorting
    // This structure will contain the final result
    var transitiveClosureMap =
      topologicalIdList.reduce(into: [ModuleDependencyId : Set<ModuleDependencyId>]()) {
        $0[$1] = [$1]
      }
    // Traverse the set of modules in reverse topological order, assimilating transitive closures
    for moduleId in topologicalIdList.reversed() {
      let moduleInfo = try moduleInfo(of: moduleId)
      for dependencyId in moduleInfo.directDependencies! {
        transitiveClosureMap[moduleId]!.formUnion(transitiveClosureMap[dependencyId]!)
      }
      // For Swift dependencies, their corresponding Swift Overlay dependencies
      // and bridging header dependencies are equivalent to direct dependencies.
      if case .swift(let swiftModuleDetails) = moduleInfo.details {
        let swiftOverlayDependencies = swiftModuleDetails.swiftOverlayDependencies ?? []
        for dependencyId in swiftOverlayDependencies {
          transitiveClosureMap[moduleId]!.formUnion(transitiveClosureMap[dependencyId]!)
        }
        let bridgingHeaderDependencies = swiftModuleDetails.bridgingHeaderDependencies ?? []
        for dependencyId in bridgingHeaderDependencies {
          transitiveClosureMap[moduleId]!.formUnion(transitiveClosureMap[dependencyId]!)
        }
      }
    }
    // For ease of use down-the-line, remove the node's self from its set of reachable nodes
    for (key, _) in transitiveClosureMap {
      transitiveClosureMap[key]!.remove(key)
    }
    return transitiveClosureMap
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
          // If the set of discovered externalModules contains a .swiftPrebuiltExternal or .swift module
          // with the same name, do not replace it.
          break
        } else if moduleInfoMap[placeholderEquivalentId] != nil {
          // Replace the placeholder module with a full .swift ModuleInfo
          // and fixup other externalModules' dependencies
          replaceModule(originalId: placeholderEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else {
          // Insert the new module
          moduleInfoMap[moduleId] = moduleInfo
        }

      case .swiftPrebuiltExternal:
        // If the set of discovered externalModules contains a .swift module with the same name,
        // replace it with the prebuilt version and fixup other externalModules' dependencies
        let swiftModuleEquivalentId = ModuleDependencyId.swift(moduleId.moduleName)
        let swiftPlaceholderEquivalentId = ModuleDependencyId.swiftPlaceholder(moduleId.moduleName)
        if moduleInfoMap[swiftModuleEquivalentId] != nil {
          // If the ModuleInfoMap contains an equivalent .swift module, replace it with the prebuilt
          // version and update all other externalModules' dependencies
          replaceModule(originalId: swiftModuleEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else if moduleInfoMap[swiftPlaceholderEquivalentId] != nil {
          // If the moduleInfoMap contains an equivalent .swiftPlaceholder module, replace it with
          // the prebuilt version and update all other externalModules' dependencies
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

  /// Replace all references to the original module in other externalModules' dependencies with the new module.
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

  /// Given two moduleInfos of clang externalModules, merge them by combining their directDependencies and
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
       firstDetails.capturedPCMArgs == secondDetails.capturedPCMArgs,
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
    let firstLinkLibraries = firstInfo.linkLibraries ?? []
    let secondLinkLibraries = secondInfo.linkLibraries ?? []
    let combinedLinkLibraries = Array(Set(firstLinkLibraries + secondLinkLibraries))

    let firstModuleCapturedPCMArgs = firstDetails.capturedPCMArgs ?? Set<[String]>()
    let secondModuleCapturedPCMArgs = secondDetails.capturedPCMArgs ?? Set<[String]>()
    let combinedCapturedPCMArgs = firstModuleCapturedPCMArgs.union(secondModuleCapturedPCMArgs)

    let combinedModuleDetails =
      ClangModuleDetails(moduleMapPath: firstDetails.moduleMapPath,
                         contextHash: firstDetails.contextHash,
                         commandLine: firstDetails.commandLine,
                         capturedPCMArgs: combinedCapturedPCMArgs)

    return ModuleInfo(modulePath: firstInfo.modulePath,
                      sourceFiles: combinedSourceFiles,
                      directDependencies: combinedDependencies,
                      linkLibraries: combinedLinkLibraries,
                      details: .clang(combinedModuleDetails))
  }
}

/// Incremental Build Machinery
internal extension InterModuleDependencyGraph {
  /// We must determine if any of the module dependencies require re-compilation
  /// Since we know that a prior dependency graph was not completely up-to-date,
  /// there must be at least *some* dependencies that require being re-built.
  ///
  /// If a dependency is deemed as requiring a re-build, then every module
  /// between it and the root (source module being built by this driver
  /// instance) must also be re-built.
  func computeInvalidatedModuleDependencies(fileSystem: FileSystem,
                                            forRebuild: Bool,
                                            reporter: IncrementalCompilationState.Reporter? = nil)
  throws -> Set<ModuleDependencyId> {
    let mainModuleInfo = mainModule
    var modulesRequiringRebuild: Set<ModuleDependencyId> = []
    var visited: Set<ModuleDependencyId> = []
    // Scan from the main module's dependencies to avoid reporting
    // the main module itself in the results.
    for dependencyId in mainModuleInfo.directDependencies ?? [] {
      try outOfDateModuleScan(from: dependencyId, visited: &visited,
                              modulesRequiringRebuild: &modulesRequiringRebuild,
                              fileSystem: fileSystem, forRebuild: forRebuild,
                              reporter: reporter)
    }

    if forRebuild {
      reporter?.reportExplicitDependencyReBuildSet(Array(modulesRequiringRebuild))
    }
    return modulesRequiringRebuild
  }

  /// Perform a postorder DFS to locate modules which are out-of-date with respect
  /// to their inputs. Upon encountering such a module, add it to the set of invalidated
  /// modules, along with the path from the root to this module.
  func outOfDateModuleScan(from sourceModuleId: ModuleDependencyId,
                           visited: inout Set<ModuleDependencyId>,
                           modulesRequiringRebuild: inout Set<ModuleDependencyId>,
                           fileSystem: FileSystem,
                           forRebuild: Bool,
                           reporter: IncrementalCompilationState.Reporter? = nil) throws {
    let reportOutOfDate = { (name: String, reason: String)  in
      if forRebuild {
        reporter?.reportExplicitDependencyWillBeReBuilt(sourceModuleId.moduleNameForDiagnostic, reason: reason)
      } else {
        reporter?.reportPriorExplicitDependencyStale(sourceModuleId.moduleNameForDiagnostic, reason: reason)
      }
    }

    let sourceModuleInfo = try moduleInfo(of: sourceModuleId)
    // Visit the module's dependencies
    var hasOutOfDateModuleDependency = false
    for dependencyId in sourceModuleInfo.directDependencies ?? [] {
      // If we have not already visited this module, recurse.
      if !visited.contains(dependencyId) {
        try outOfDateModuleScan(from: dependencyId, visited: &visited,
                                modulesRequiringRebuild: &modulesRequiringRebuild,
                                fileSystem: fileSystem, forRebuild: forRebuild,
                                reporter: reporter)
      }
      // Even if we're not revisiting a dependency, we must check if it's already known to be out of date.
      hasOutOfDateModuleDependency = hasOutOfDateModuleDependency || modulesRequiringRebuild.contains(dependencyId)
    }

    if hasOutOfDateModuleDependency {
      reportOutOfDate(sourceModuleId.moduleNameForDiagnostic, "Invalidated by downstream dependency")
      modulesRequiringRebuild.insert(sourceModuleId)
    } else if try !verifyModuleDependencyUpToDate(moduleID: sourceModuleId, fileSystem: fileSystem, reporter: reporter) {
      reportOutOfDate(sourceModuleId.moduleNameForDiagnostic, "Out-of-date")
      modulesRequiringRebuild.insert(sourceModuleId)
    }

    // Now that we've determined if this module must be rebuilt, mark it as visited.
    visited.insert(sourceModuleId)
  }

  func verifyModuleDependencyUpToDate(moduleID: ModuleDependencyId,
                                      fileSystem: FileSystem,
                                      reporter: IncrementalCompilationState.Reporter?) throws -> Bool {
    let checkedModuleInfo = try moduleInfo(of: moduleID)
    // Verify that the specified input exists and is older than the specified output
    let verifyInputOlderThanOutputModTime: (String, VirtualPath, TimePoint) -> Bool =
    { moduleName, inputPath, outputModTime in
      guard let inputModTime =
              try? fileSystem.lastModificationTime(for: inputPath) else {
        reporter?.report("Unable to 'stat' \(inputPath.description)")
        return false
      }
      if inputModTime > outputModTime {
        reporter?.reportExplicitDependencyOutOfDate(moduleName,
                                                    inputPath: inputPath.description)
        return false
      }
      return true
    }

    // Check if the output file exists
    guard let outputModTime = try? fileSystem.lastModificationTime(for: VirtualPath.lookup(checkedModuleInfo.modulePath.path)) else {
      reporter?.report("Module output not found: '\(moduleID.moduleNameForDiagnostic)'")
      return false
    }

    // Check if a dependency of this module has a newer output than this module
    for dependencyId in checkedModuleInfo.directDependencies ?? [] {
      let dependencyInfo = try moduleInfo(of: dependencyId)
      if !verifyInputOlderThanOutputModTime(moduleID.moduleName,
                                            VirtualPath.lookup(dependencyInfo.modulePath.path),
                                            outputModTime) {
        return false
      }
    }

    // Check if any of the input sources of this module are newer than this module
    switch checkedModuleInfo.details {
    case .swift(let swiftDetails):
      if let moduleInterfacePath = swiftDetails.moduleInterfacePath {
        if !verifyInputOlderThanOutputModTime(moduleID.moduleName,
                                              VirtualPath.lookup(moduleInterfacePath.path),
                                              outputModTime) {
          return false
        }
      }
      if let bridgingHeaderPath = swiftDetails.bridgingHeaderPath {
        if !verifyInputOlderThanOutputModTime(moduleID.moduleName,
                                              VirtualPath.lookup(bridgingHeaderPath.path),
                                              outputModTime) {
          return false
        }
      }
      for bridgingSourceFile in swiftDetails.bridgingSourceFiles ?? [] {
        if !verifyInputOlderThanOutputModTime(moduleID.moduleName,
                                              VirtualPath.lookup(bridgingSourceFile.path),
                                              outputModTime) {
          return false
        }
      }
    case .clang(_):
      for inputSourceFile in checkedModuleInfo.sourceFiles ?? [] {
        if !verifyInputOlderThanOutputModTime(moduleID.moduleName,
                                              try VirtualPath(path: inputSourceFile),
                                              outputModTime) {
          return false
        }
      }
    case .swiftPrebuiltExternal(_):
      // We do not verify the binary module itself being out-of-date if we do not have a textual
      // interface it was built from, but we can safely treat it as up-to-date, particularly
      // because if it is newer than any of the modules they depend on it, they will
      // still get invalidated in the check above for whether a module has
      // any dependencies newer than it.
      return true;
    case .swiftPlaceholder(_):
      // TODO: This should never ever happen. Hard error?
      return false;
    }

    return true
  }
}

internal extension InterModuleDependencyGraph {
  func explainDependency(dependencyModuleName: String) throws -> [[ModuleDependencyId]]? {
    guard modules.contains(where: { $0.key.moduleName == dependencyModuleName }) else { return nil }
    var results = Set<[ModuleDependencyId]>()
    try findAllPaths(source: .swift(mainModuleName),
                     to: dependencyModuleName,
                     pathSoFar: [.swift(mainModuleName)],
                     results: &results)
    return results.sorted(by: { $0.count < $1.count })
  }


  private func findAllPaths(source: ModuleDependencyId,
                            to moduleName: String,
                            pathSoFar: [ModuleDependencyId],
                            results: inout Set<[ModuleDependencyId]>) throws {
    let sourceInfo = try moduleInfo(of: source)
    // If the source is our target, we are done
    if source.moduleName == moduleName {
      // If the source is a target Swift module, also check if it
      // depends on a corresponding Clang module with the same name.
      // If it does, add it to the path as well.
      var completePath = pathSoFar
      if let dependencies = sourceInfo.directDependencies,
         dependencies.contains(.clang(moduleName)) {
        completePath.append(.clang(moduleName))
      }
      results.insert(completePath)
    }

    var allDependencies = sourceInfo.directDependencies ?? []
    if case .swift(let swiftModuleDetails) = sourceInfo.details,
          let overlayDependencies = swiftModuleDetails.swiftOverlayDependencies {
      allDependencies.append(contentsOf: overlayDependencies)
    }

    for dependency in allDependencies {
      try findAllPaths(source: dependency,
                       to: moduleName,
                       pathSoFar: pathSoFar + [dependency],
                       results: &results)
    }
  }
}
