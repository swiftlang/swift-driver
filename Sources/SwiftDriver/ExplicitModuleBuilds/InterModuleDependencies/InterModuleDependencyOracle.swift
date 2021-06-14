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

import TSCBasic
import Foundation

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
  /// Allow external clients to instantiate the oracle
  public init() {}

  @_spi(Testing) public func getDependencies(workingDirectory: AbsolutePath,
                                             commandLine: [String])
  throws -> InterModuleDependencyGraph {
    precondition(hasScannerInstance)
    return try queue.sync {
      return try swiftScanLibInstance!.scanDependencies(workingDirectory: workingDirectory,
                                                       invocationCommand: commandLine)
    }
  }

  @_spi(Testing) public func getBatchDependencies(workingDirectory: AbsolutePath,
                                                  commandLine: [String],
                                                  batchInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    precondition(hasScannerInstance)
    return try queue.sync {
      return try swiftScanLibInstance!.batchScanDependencies(workingDirectory: workingDirectory,
                                                            invocationCommand: commandLine,
                                                            batchInfos: batchInfos)
    }
  }

  /// Given a specified toolchain path, locate and instantiate an instance of the SwiftScan library
  /// Returns True if a library instance exists (either verified or newly-created).
  @_spi(Testing) public func verifyOrCreateScannerInstance(fileSystem: FileSystem,
                                                           swiftScanLibPath: AbsolutePath)
  throws -> Bool {
    return try queue.sync {
      if swiftScanLibInstance == nil {
        guard fileSystem.exists(swiftScanLibPath) else {
          return false
        }
        swiftScanLibInstance = try SwiftScan(dylib: swiftScanLibPath)
      } else {
        guard swiftScanLibInstance!.path == swiftScanLibPath else {
          throw DependencyScanningError
          .scanningLibraryInvocationMismatch(swiftScanLibInstance!.path, swiftScanLibPath)
        }
      }
      return true
    }
  }

  @_spi(Testing) public func serializeScannerCache(to path: AbsolutePath) {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to serialize scanner cache with no scanner instance.")
    }
    if swiftScan.canLoadStoreScannerCache() {
      swiftScan.serializeScannerCache(to: path)
    }
  }

  @_spi(Testing) public func loadScannerCache(from path: AbsolutePath) -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to load scanner cache with no scanner instance.")
    }
    if swiftScan.canLoadStoreScannerCache() {
      return swiftScan.loadScannerCache(from: path)
    }
    return false
  }

  @_spi(Testing) public func resetScannerCache() {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    if swiftScan.canLoadStoreScannerCache() {
      swiftScan.resetScannerCache()
    }
  }

  private var hasScannerInstance: Bool { self.swiftScanLibInstance != nil }

  /// Queue to sunchronize accesses to the scanner
  internal let queue = DispatchQueue(label: "org.swift.swift-driver.swift-scan")

  /// A reference to an instance of the compiler's libSwiftScan shared library
  private var swiftScanLibInstance: SwiftScan? = nil

  // The below API is a legacy implementation of the oracle that is in-place to allow clients to
  // transition to the new API. It is to be removed once that transition is complete.
  /// The complete set of modules discovered so far, spanning potentially multiple targets,
  /// accumulated across builds of multiple targets.
  /// TODO: This is currently only used for placeholder resolution. libSwiftScan should allow us to move away
  /// from the concept of a placeholder module so we should be able to get rid of this in the future.
  internal var externalModules: ModuleInfoMap = [:]
  /// Query the ModuleInfo of a module with a given ID
  @_spi(Testing) public func getExternalModuleInfo(of moduleId: ModuleDependencyId) -> ModuleInfo? {
    queue.sync {
      return externalModules[moduleId]
    }
  }
}

// This is a shim for backwards-compatibility with existing API used by SwiftPM.
// TODO: After SwiftPM switches to using the oracle, this should be deleted.
extension Driver {
  public var interModuleDependencyGraph: InterModuleDependencyGraph? {
    let mainModuleId : ModuleDependencyId = .swift(moduleOutputInfo.name)
    var mainModuleDependencyGraph =
      InterModuleDependencyGraph(mainModuleName: moduleOutputInfo.name)

    addModule(moduleId: mainModuleId,
              moduleInfo: interModuleDependencyOracle.getExternalModuleInfo(of: mainModuleId)!,
              into: &mainModuleDependencyGraph)
    return mainModuleDependencyGraph
  }

  private func addModule(moduleId: ModuleDependencyId,
                         moduleInfo: ModuleInfo,
                         into dependencyGraph: inout InterModuleDependencyGraph) {
    dependencyGraph.modules[moduleId] = moduleInfo
    moduleInfo.directDependencies?.forEach { dependencyId in
      addModule(moduleId: dependencyId,
                moduleInfo: interModuleDependencyOracle.getExternalModuleInfo(of: dependencyId)!,
                into: &dependencyGraph)
    }
  }
}
