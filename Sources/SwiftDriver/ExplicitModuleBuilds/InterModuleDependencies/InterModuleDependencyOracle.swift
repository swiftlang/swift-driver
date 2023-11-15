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
import struct Foundation.Data

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
  /// - Parameter scannerRequiresPlaceholderModules: Configures this driver's/oracle's scanner invocations to
  /// specify external module dependencies to be treated as placeholders. This is required in contexts
  /// where the dependency scanning action is invoked for a module which depends on another module
  /// that is part of the same build but has not yet been built. Treating it as a placeholder
  /// will allow the scanning action to not fail when it fails to detect this dependency on
  /// the filesystem. For example, SwiftPM plans all targets belonging to a package before *any* of them
  /// are built. So this setting is meant to be used there. In contexts where planning a module
  /// necessarily means all of its dependencies have already been built this is not necessary.
  public init(scannerRequiresPlaceholderModules: Bool = false) {
    self.scannerRequiresPlaceholderModules = scannerRequiresPlaceholderModules
  }

  @_spi(Testing) public func getDependencies(workingDirectory: AbsolutePath,
                                             moduleAliases: [String: String]? = nil,
                                             commandLine: [String])
  throws -> InterModuleDependencyGraph {
    precondition(hasScannerInstance)
    return try swiftScanLibInstance!.scanDependencies(workingDirectory: workingDirectory,
                                                      moduleAliases: moduleAliases,
                                                      invocationCommand: commandLine)
  }

  @_spi(Testing) public func getBatchDependencies(workingDirectory: AbsolutePath,
                                                  moduleAliases: [String: String]? = nil,
                                                  commandLine: [String],
                                                  batchInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    precondition(hasScannerInstance)
    return try swiftScanLibInstance!.batchScanDependencies(workingDirectory: workingDirectory,
                                                           moduleAliases: moduleAliases,
                                                           invocationCommand: commandLine,
                                                           batchInfos: batchInfos)
  }

  @_spi(Testing) public func getImports(workingDirectory: AbsolutePath,
                                        moduleAliases: [String: String]? = nil,
                                             commandLine: [String])
  throws -> InterModuleDependencyImports {
    precondition(hasScannerInstance)
    return try swiftScanLibInstance!.preScanImports(workingDirectory: workingDirectory,
                                                    moduleAliases: moduleAliases,
                                                    invocationCommand: commandLine)
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

  @_spi(Testing) public func supportsBinaryFrameworkDependencies() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.hasBinarySwiftModuleIsFramework
  }

  @_spi(Testing) public func supportsScannerDiagnostics() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.supportsScannerDiagnostics
  }

  @_spi(Testing) public func supportsBinaryModuleHeaderDependencies() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.supportsBinaryModuleHeaderDependencies
  }

  @_spi(Testing) public func supportsCaching() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.supportsCaching
  }

  @_spi(Testing) public func supportsBridgingHeaderPCHCommand() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.supportsBridgingHeaderPCHCommand
  }

  @_spi(Testing) public func getScannerDiagnostics() throws -> [ScannerDiagnosticPayload]? {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    guard swiftScan.supportsScannerDiagnostics else {
      return nil
    }
    let diags = try swiftScan.queryScannerDiagnostics()
    try swiftScan.resetScannerDiagnostics()
    return diags.isEmpty ? nil : diags
  }

  public func createCAS(pluginPath: AbsolutePath?, onDiskPath: AbsolutePath?, pluginOptions: [(String, String)]) throws {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    try swiftScan.createCAS(pluginPath: pluginPath?.pathString, onDiskPath: onDiskPath?.pathString, pluginOptions: pluginOptions)
  }

  public func store(data: Data) throws -> String {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    return try swiftScan.store(data:data)
  }

  public func computeCacheKeyForOutput(kind: FileType, commandLine: [Job.ArgTemplate], input: VirtualPath.Handle?) throws -> String {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    let inputPath = input?.description ?? ""
    return try swiftScan.computeCacheKeyForOutput(kind: kind, commandLine: commandLine.stringArray, input: inputPath)
  }

  private var hasScannerInstance: Bool { self.swiftScanLibInstance != nil }

  /// Queue to sunchronize accesses to the scanner
  internal let queue = DispatchQueue(label: "org.swift.swift-driver.swift-scan")

  /// A reference to an instance of the compiler's libSwiftScan shared library
  private var swiftScanLibInstance: SwiftScan? = nil

  internal let scannerRequiresPlaceholderModules: Bool
}

