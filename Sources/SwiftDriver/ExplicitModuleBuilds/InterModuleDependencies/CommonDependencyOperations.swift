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
      try topologicalSort(Array(modules.keys), successors: { try Array(moduleInfo(of: $0).allDependencies) })
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
      for dependencyId in try moduleInfo(of: moduleId).allDependencies {
        transitiveClosureMap[moduleId]!.formUnion(transitiveClosureMap[dependencyId]!)
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
                                            cas: SwiftScanCAS?,
                                            forRebuild: Bool,
                                            reporter: IncrementalCompilationState.Reporter? = nil)
  throws -> Set<ModuleDependencyId> {
    let mainModuleInfo = mainModule
    var modulesRequiringRebuild: Set<ModuleDependencyId> = []
    var visited: Set<ModuleDependencyId> = []
    // Scan from the main module's dependencies to avoid reporting
    // the main module itself in the results.
    for dependencyId in mainModuleInfo.allDependencies {
      try outOfDateModuleScan(from: dependencyId, visited: &visited,
                              modulesRequiringRebuild: &modulesRequiringRebuild,
                              fileSystem: fileSystem, cas: cas, forRebuild: forRebuild,
                              reporter: reporter)
    }

    if forRebuild && !modulesRequiringRebuild.isEmpty {
      reporter?.reportExplicitDependencyReBuildSet(Array(modulesRequiringRebuild))
    }
    return modulesRequiringRebuild
  }

  /// From a set of provided module dependency pre-compilation jobs,
  /// filter out those with a fully up-to-date output
  func filterMandatoryModuleDependencyCompileJobs(_ allJobs: [Job],
                                                  fileSystem: FileSystem,
                                                  cas: SwiftScanCAS?,
                                                  reporter: IncrementalCompilationState.Reporter? = nil) throws -> [Job] {
    // Determine which module pre-build jobs must be re-run
    let modulesRequiringReBuild =
      try computeInvalidatedModuleDependencies(fileSystem: fileSystem, cas: cas, forRebuild: true, reporter: reporter)

    // Filter the `.generatePCM` and `.compileModuleFromInterface` jobs for
    // modules which do *not* need re-building.
    return allJobs.filter { job in
      switch job.kind {
      case .generatePCM:
        return modulesRequiringReBuild.contains(.clang(job.moduleName))
      case .compileModuleFromInterface:
        return modulesRequiringReBuild.contains(.swift(job.moduleName))
      default:
        return true
      }
    }
  }

  /// Perform a postorder DFS to locate modules which are out-of-date with respect
  /// to their inputs. Upon encountering such a module, add it to the set of invalidated
  /// modules, along with the path from the root to this module.
  func outOfDateModuleScan(from sourceModuleId: ModuleDependencyId,
                           visited: inout Set<ModuleDependencyId>,
                           modulesRequiringRebuild: inout Set<ModuleDependencyId>,
                           fileSystem: FileSystem,
                           cas: SwiftScanCAS?,
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
    for dependencyId in sourceModuleInfo.allDependencies {
      // If we have not already visited this module, recurse.
      if !visited.contains(dependencyId) {
        try outOfDateModuleScan(from: dependencyId, visited: &visited,
                                modulesRequiringRebuild: &modulesRequiringRebuild,
                                fileSystem: fileSystem, cas: cas, forRebuild: forRebuild,
                                reporter: reporter)
      }
      // Even if we're not revisiting a dependency, we must check if it's already known to be out of date.
      hasOutOfDateModuleDependency = hasOutOfDateModuleDependency || modulesRequiringRebuild.contains(dependencyId)
    }

    if hasOutOfDateModuleDependency {
      reportOutOfDate(sourceModuleId.moduleNameForDiagnostic, "Invalidated by downstream dependency")
      modulesRequiringRebuild.insert(sourceModuleId)
    } else if try !verifyModuleDependencyUpToDate(moduleID: sourceModuleId, fileSystem: fileSystem, cas:cas, reporter: reporter) {
      reportOutOfDate(sourceModuleId.moduleNameForDiagnostic, "Out-of-date")
      modulesRequiringRebuild.insert(sourceModuleId)
    }

    // Now that we've determined if this module must be rebuilt, mark it as visited.
    visited.insert(sourceModuleId)
  }

  func outputMissingFromCAS(moduleInfo: ModuleInfo,
                            cas: SwiftScanCAS?) throws -> Bool {
    func casOutputMissing(_ key: String?) throws -> Bool {
      // Caching not enabled.
      guard let id = key, let cas = cas else { return false }
      // Do a local query to see if the output exists.
      let result = try cas.queryCacheKey(id, globally: false)
      // Make sure all outputs are available in local CAS.
      guard let outputs = result else { return true }
      return !outputs.allSatisfy { $0.isMaterialized }
    }

    switch moduleInfo.details {
    case .swift(let swiftDetails):
      return try casOutputMissing(swiftDetails.moduleCacheKey)
    case .clang(let clangDetails):
      return try casOutputMissing(clangDetails.moduleCacheKey)
    case .swiftPrebuiltExternal(_):
      return false;
    case .swiftPlaceholder(_):
      // TODO: This should never ever happen. Hard error?
      return true;
    }
  }

  func verifyModuleDependencyUpToDate(moduleID: ModuleDependencyId,
                                      fileSystem: FileSystem,
                                      cas: SwiftScanCAS?,
                                      reporter: IncrementalCompilationState.Reporter?) throws -> Bool {
    let checkedModuleInfo = try moduleInfo(of: moduleID)
    // Check if there is a module cache key available, then the content that pointed by the cache key must
    // exist for module to be up-to-date. Treat any CAS error as missing.
    let missingFromCAS = (try? outputMissingFromCAS(moduleInfo: checkedModuleInfo, cas: cas)) ?? true
    if missingFromCAS {
      reporter?.reportExplicitDependencyMissingFromCAS(moduleID.moduleName)
      return false
    }

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

    // We do not verify the binary module itself being out-of-date if we do not have a textual
    // interface it was built from, but we can safely treat it as up-to-date, particularly
    // because if it is newer than any of the modules they depend on it, they will
    // still get invalidated in the check below for whether a module has
    // any dependencies newer than it.
    if case .swiftPrebuiltExternal(_) = moduleID {
      return true
    }

    // Check if a dependency of this module has a newer output than this module
    for dependencyId in checkedModuleInfo.allDependencies {
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
      return true;
    case .swiftPlaceholder(_):
      // TODO: This should never ever happen. Hard error?
      return false;
    }

    return true
  }
}

internal extension InterModuleDependencyGraph {
  func explainDependency(dependencyModuleName: String, allPaths: Bool) throws -> [[ModuleDependencyId]]? {
    guard modules.contains(where: { $0.key.moduleName == dependencyModuleName }) else { return nil }
    var result: Set<[ModuleDependencyId]> = []
    if allPaths {
      try findAllPaths(source: .swift(mainModuleName),
                       pathSoFar: [.swift(mainModuleName)],
                       results: &result,
                       destinationMatch: { $0.moduleName == dependencyModuleName })
    } else {
      var visited: Set<ModuleDependencyId> = []
      var singlePathResult: [ModuleDependencyId]? = nil
      if try findAPath(source: .swift(mainModuleName),
                       pathSoFar: [.swift(mainModuleName)],
                       visited: &visited,
                       result: &singlePathResult,
                       destinationMatch: { $0.moduleName == dependencyModuleName }),
         let resultingPath = singlePathResult {
        result = [resultingPath]
      }
    }
    return Array(result)
  }

  @discardableResult
  func findAPath(source: ModuleDependencyId,
                 pathSoFar: [ModuleDependencyId],
                 visited: inout Set<ModuleDependencyId>,
                 result: inout [ModuleDependencyId]?,
                 destinationMatch: (ModuleDependencyId) -> Bool) throws -> Bool {
    // Mark this node as visited
    visited.insert(source)
    let sourceInfo = try moduleInfo(of: source)
    if destinationMatch(source) {
      // If the source is a target Swift module, also check if it
      // depends on a corresponding Clang module with the same name.
      // If it does, add it to the path as well.
      var completePath = pathSoFar
      if sourceInfo.allDependencies.contains(.clang(source.moduleName)) {
        completePath.append(.clang(source.moduleName))
      }
      result = completePath
      return true
    }

    for dependency in sourceInfo.allDependencies {
      if !visited.contains(dependency),
         try findAPath(source: dependency,
                       pathSoFar: pathSoFar + [dependency],
                       visited: &visited,
                       result: &result,
                       destinationMatch: destinationMatch) {
        return true
      }
    }
    return false
  }

  private func findAllPaths(source: ModuleDependencyId,
                            pathSoFar: [ModuleDependencyId],
                            results: inout Set<[ModuleDependencyId]>,
                            destinationMatch: (ModuleDependencyId) -> Bool) throws {
    let sourceInfo = try moduleInfo(of: source)
    if destinationMatch(source) {
      // If the source is a target Swift module, also check if it
      // depends on a corresponding Clang module with the same name.
      // If it does, add it to the path as well.
      var completePath = pathSoFar
      if sourceInfo.allDependencies.contains(.clang(source.moduleName)) {
        completePath.append(.clang(source.moduleName))
      }
      results.insert(completePath)
      return
    }

    for dependency in sourceInfo.allDependencies {
      try findAllPaths(source: dependency,
                       pathSoFar: pathSoFar + [dependency],
                       results: &results,
                       destinationMatch: destinationMatch)
    }
  }
}
