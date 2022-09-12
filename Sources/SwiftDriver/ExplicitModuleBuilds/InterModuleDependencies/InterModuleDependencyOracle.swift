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

import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath

import Dispatch

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
                                             moduleAliases: [String: String]? = nil,
                                             commandLine: [String])
  throws -> InterModuleDependencyGraph {
    precondition(hasScannerInstance)
    return try queue.sync {
      return try swiftScanLibInstance!.scanDependencies(workingDirectory: workingDirectory,
                                                        moduleAliases: moduleAliases,
                                                       invocationCommand: commandLine)
    }
  }

  @_spi(Testing) public func getBatchDependencies(workingDirectory: AbsolutePath,
                                                  moduleAliases: [String: String]? = nil,
                                                  commandLine: [String],
                                                  batchInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    precondition(hasScannerInstance)
    return try queue.sync {
      return try swiftScanLibInstance!.batchScanDependencies(workingDirectory: workingDirectory,
                                                             moduleAliases: moduleAliases,
                                                            invocationCommand: commandLine,
                                                            batchInfos: batchInfos)
    }
  }

  @_spi(Testing) public func getImports(workingDirectory: AbsolutePath,
                                        moduleAliases: [String: String]? = nil,
                                             commandLine: [String])
  throws -> InterModuleDependencyImports {
    precondition(hasScannerInstance)
    return try queue.sync {
      return try swiftScanLibInstance!.preScanImports(workingDirectory: workingDirectory,
                                                      moduleAliases: moduleAliases,
                                                      invocationCommand: commandLine)
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
    if swiftScan.canLoadStoreScannerCache {
      swiftScan.serializeScannerCache(to: path)
    }
  }

  @_spi(Testing) public func loadScannerCache(from path: AbsolutePath) -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to load scanner cache with no scanner instance.")
    }
    if swiftScan.canLoadStoreScannerCache {
      return swiftScan.loadScannerCache(from: path)
    }
    return false
  }

  @_spi(Testing) public func resetScannerCache() {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    if swiftScan.canLoadStoreScannerCache {
      swiftScan.resetScannerCache()
    }
  }
  
  @_spi(Testing) public func supportsScannerDiagnostics() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    return swiftScan.supportsScannerDiagnostics()
  }
  
  @_spi(Testing) public func getScannerDiagnostics() throws -> [ScannerDiagnosticPayload]? {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    guard swiftScan.supportsScannerDiagnostics() else {
      return nil
    }
    let diags = try swiftScan.queryScannerDiagnostics()
    try swiftScan.resetScannerDiagnostics()
    return diags.isEmpty ? nil : diags
  }

  private var hasScannerInstance: Bool { self.swiftScanLibInstance != nil }

  /// Queue to sunchronize accesses to the scanner
  internal let queue = DispatchQueue(label: "org.swift.swift-driver.swift-scan")

  /// A reference to an instance of the compiler's libSwiftScan shared library
  private var swiftScanLibInstance: SwiftScan? = nil
}

