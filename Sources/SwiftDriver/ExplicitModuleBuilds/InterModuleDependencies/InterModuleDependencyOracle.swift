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
import var TSCBasic.localFileSystem

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
                                             commandLine: [String],
                                             diagnostics: inout [ScannerDiagnosticPayload])
  throws -> InterModuleDependencyGraph {
    precondition(hasScannerInstance)
    return try swiftScanLibInstance!.scanDependencies(workingDirectory: workingDirectory,
                                                      moduleAliases: moduleAliases,
                                                      invocationCommand: commandLine,
                                                      diagnostics: &diagnostics)
  }

  @_spi(Testing) public func getImports(workingDirectory: AbsolutePath,
                                        moduleAliases: [String: String]? = nil,
                                        commandLine: [String],
                                        diagnostics: inout [ScannerDiagnosticPayload])
  throws -> InterModuleDependencyImports {
    precondition(hasScannerInstance)
    return try swiftScanLibInstance!.preScanImports(workingDirectory: workingDirectory,
                                                    moduleAliases: moduleAliases,
                                                    invocationCommand: commandLine,
                                                    diagnostics: &diagnostics)
  }

  @available(*, deprecated, message: "use verifyOrCreateScannerInstance(swiftScanLibPath:)")
  public func verifyOrCreateScannerInstance(fileSystem: FileSystem,
                                            swiftScanLibPath: AbsolutePath) throws {
    return try verifyOrCreateScannerInstance(swiftScanLibPath: swiftScanLibPath)
  }

  /// Given a specified toolchain path, locate and instantiate an instance of the SwiftScan library
  public func verifyOrCreateScannerInstance(swiftScanLibPath: AbsolutePath?) throws {
    return try queue.sync {
      guard let scanInstance = swiftScanLibInstance else {
        swiftScanLibInstance = try SwiftScan(dylib: swiftScanLibPath)
        return
      }

      guard scanInstance.path?.description == swiftScanLibPath?.description else {
        throw DependencyScanningError
          .scanningLibraryInvocationMismatch(scanInstance.path?.description ?? "built-in",
                                             swiftScanLibPath?.description ?? "built-in")
      }
    }
  }

  @_spi(Testing) public func supportsBinaryFrameworkDependencies() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.hasBinarySwiftModuleIsFramework
  }

  @_spi(Testing) public func supportsBinaryModuleHeaderModuleDependencies() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.hasBinarySwiftModuleHeaderModuleDependencies
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
    return swiftScan.supportsBinaryModuleHeaderDependencies || swiftScan.supportsBinaryModuleHeaderDependency
  }

  @_spi(Testing) public var supportsBridgingHeaderPCHCommand: Bool {
    guard let swiftScan = swiftScanLibInstance else {
      // If no scanner, feature is not supported.
      return false
    }
    return swiftScan.supportsBridgingHeaderPCHCommand
  }

  @_spi(Testing) public func supportsPerScanDiagnostics() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.canQueryPerScanDiagnostics
  }

  @_spi(Testing) public func supportsDiagnosticSourceLocations() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.supportsDiagnosticSourceLocations
  }

  @_spi(Testing) public func supportsLinkLibraries() throws -> Bool {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to query supported scanner API with no scanner instance.")
    }
    return swiftScan.supportsLinkLibraries
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

  public func getOrCreateCAS(pluginPath: AbsolutePath?, onDiskPath: AbsolutePath?, pluginOptions: [(String, String)]) throws -> SwiftScanCAS {
    guard let swiftScan = swiftScanLibInstance else {
      fatalError("Attempting to reset scanner cache with no scanner instance.")
    }
    // Use synchronized queue to avoid creating multiple OnDisk CAS at the same location as that will leave to synchronization issues.
    return try queue.sync {
      let casOpt = CASConfig(onDiskPath: onDiskPath, pluginPath: pluginPath, pluginOptions: pluginOptions)
      if let cas = createdCASMap[casOpt] {
        return cas
      }
      let cas = try swiftScan.createCAS(pluginPath: pluginPath?.pathString, onDiskPath: onDiskPath?.pathString, pluginOptions: pluginOptions)
      createdCASMap[casOpt] = cas
      return cas
    }
  }

  // Note: this is `true` even in the `compilerIntegratedTooling` mode
  // where the `SwiftScan` instance refers to the own image the driver is
  // running in, since there is still technically a `SwiftScan` handle
  // capable of handling API requests expected of it.
  private var hasScannerInstance: Bool { self.swiftScanLibInstance != nil }
  func getScannerInstance() -> SwiftScan? {
    self.swiftScanLibInstance
  }
  func setScannerInstance(_ instance: SwiftScan?) {
    self.swiftScanLibInstance = instance
  }

  /// Queue to sunchronize accesses to the scanner
  let queue = DispatchQueue(label: "org.swift.swift-driver.swift-scan")

  /// A reference to an instance of the compiler's libSwiftScan shared library
  private var swiftScanLibInstance: SwiftScan? = nil

  internal let scannerRequiresPlaceholderModules: Bool

  internal struct CASConfig: Hashable, Equatable {
    static func == (lhs: InterModuleDependencyOracle.CASConfig, rhs: InterModuleDependencyOracle.CASConfig) -> Bool {
      return lhs.onDiskPath == rhs.onDiskPath &&
             lhs.pluginPath == rhs.pluginPath &&
             lhs.pluginOptions.elementsEqual(rhs.pluginOptions, by: ==)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(onDiskPath)
      hasher.combine(pluginPath)
      for opt in pluginOptions {
        hasher.combine(opt.0)
        hasher.combine(opt.1)
      }
    }

    let onDiskPath: AbsolutePath?
    let pluginPath: AbsolutePath?
    let pluginOptions: [(String, String)]
  }

  /// Storing the CAS created via CASConfig.
  internal var createdCASMap: [CASConfig: SwiftScanCAS] = [:]
}

