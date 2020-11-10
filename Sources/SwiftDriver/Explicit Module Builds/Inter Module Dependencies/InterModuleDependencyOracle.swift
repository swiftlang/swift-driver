//===--------------- InterModuleDependencyOracle.swift --------------------===//
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

// An inter-module dependency oracle, responsible for responding to queries about
// dependencies of a given module, caching already-discovered dependencies along the way.
//
// The oracle is currently implemented as a simple store of ModuleInfo nodes.
// It is the responsibility of the Driver to populate and update
// the store. It does so by invoking individual -scan-dependencies jobs and
// accumulating resulting dependency graphs into the oracle's store.
//
// The design of the oracle's public API is meant to abstract that away,
// allowing us to replace the underlying implementation in the future, with
// a persistent-across-targets dependency scanning library.
//
/// An abstraction of a cache and query-engine of inter-module dependencies
public class InterModuleDependencyOracle {
  /// Query the ModuleInfo of a module with a given ID
  @_spi(Testing) public func getModuleInfo(of moduleId: ModuleDependencyId) -> ModuleInfo? {
    return modules[moduleId]
  }

  /// Query the direct dependencies of a module with a given ID
  @_spi(Testing) public func getDependencies(of moduleId: ModuleDependencyId)
  -> [ModuleDependencyId]? {
    return modules[moduleId]?.directDependencies
  }

  // TODO: This will require a SwiftDriver entry-point for scanning a module given
  // a command invocation and a set of source-files. As-is, the driver itself is responsible
  // for executing individual module dependency-scanning actions and updating oracle state.
  // (Implemented with InterModuleDependencyOracle::mergeModules extension)
  //
  // func getFullDependencies(inputs: [TypedVirtualPath],
  //                          commandLine: [Job.ArgTemplate]) -> InterModuleDependencyGraph {}
  //

  /// The complete set of modules discovered so far, spanning potentially multiple targets
  internal var modules: ModuleInfoMap = [:]

  /// Override the default initializer's access level for test access
  @_spi(Testing) public init() {}
}

// This is a shim for backwards-compatibility with existing API used by SwiftPM.
// TODO: After SwiftPM switches to using the oracle, this should be deleted.
extension Driver {
  public var interModuleDependencyGraph: InterModuleDependencyGraph? {
    let mainModuleId : ModuleDependencyId = .swift(moduleOutputInfo.name)
    var mainModuleDependencyGraph =
      InterModuleDependencyGraph(mainModuleName: moduleOutputInfo.name)

    addModule(moduleId: mainModuleId,
              moduleInfo: interModuleDependencyOracle.getModuleInfo(of: mainModuleId)!,
              into: &mainModuleDependencyGraph)
    return mainModuleDependencyGraph
  }

  private func addModule(moduleId: ModuleDependencyId,
                         moduleInfo: ModuleInfo,
                         into dependencyGraph: inout InterModuleDependencyGraph) {
    dependencyGraph.modules[moduleId] = moduleInfo
    moduleInfo.directDependencies?.forEach { dependencyId in
      addModule(moduleId: dependencyId,
                moduleInfo: interModuleDependencyOracle.getModuleInfo(of: dependencyId)!,
                into: &dependencyGraph)
    }
  }
}
