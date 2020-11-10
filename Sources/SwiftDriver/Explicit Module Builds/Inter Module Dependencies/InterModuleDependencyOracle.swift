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


// The oracle is currently implemented as a simple store of ModuleInfo nodes.
// It is the currently responsibility of the swift-driver to populate and update
// the store. It does so by invoking individual -scan-dependencies jobs and
// accumulating resulting dependency graphs.
//
// The design of the oracle's public API is meant to abstract that away,
// allowing us to, in the future, replace the underlying implementation with
// a persistent-across-targets dependency scanning library.
//
/// An abstraction of a cache and query-engine of inter-module dependencies
public class InterModuleDependencyOracle {
  // MARK: Public API
  /// Query the ModuleInfo of a module with a given ID
  public func getModuleInfo(of moduleId: ModuleDependencyId) -> ModuleInfo? {
    return modules[moduleId]
  }

  /// Query the direct dependencies of a module with a given ID
  public func getDependencies(of moduleId: ModuleDependencyId) -> [ModuleDependencyId]? {
    return modules[moduleId]?.directDependencies
  }

  // MARK: Private Implementation

  // TODO: This will require a SwiftDriver entry-point for scanning a module given
  // a command invocation and a set of source-files. As-is, the driver itself is responsible
  // for executing individual module dependency-scanning actions and updating oracle state.

  /// The complete set of modules discovered so far, spanning potentially multiple targets
  internal var modules: ModuleInfoMap = [:]

  /// Override the default initializer's internal access level for test access
  @_spi(Testing) public init() {}
}

