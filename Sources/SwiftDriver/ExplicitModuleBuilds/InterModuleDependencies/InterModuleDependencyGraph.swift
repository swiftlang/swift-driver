//===--------------- InterModuleDependencyGraph.swift ---------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import class Foundation.JSONEncoder
import struct Foundation.Data

/// A map from a module identifier to its info
public typealias ModuleInfoMap = [ModuleDependencyId: ModuleInfo]

public enum ModuleDependencyId: Hashable {
  case swift(String)
  case swiftPrebuiltExternal(String)
  case clang(String)

  public var moduleName: String {
    switch self {
    case .swift(let name): return name
    case .swiftPrebuiltExternal(let name): return name
    case .clang(let name): return name
    }
  }

  internal var moduleNameForDiagnostic: String {
    switch self {
    case .swift(let name): return name
    case .swiftPrebuiltExternal(let name): return name + "(swiftmodule)"
    case .clang(let name): return name + "(pcm)"
    }
  }
}

extension ModuleDependencyId: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case swiftPrebuiltExternal
    case clang
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      let moduleName =  try container.decode(String.self, forKey: .swift)
      self = .swift(moduleName)
    } catch {
      do {
        let moduleName =  try container.decode(String.self, forKey: .swiftPrebuiltExternal)
        self = .swiftPrebuiltExternal(moduleName)
      } catch {
        let moduleName =  try container.decode(String.self, forKey: .clang)
        self = .clang(moduleName)
      }
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .swift(let moduleName):
        try container.encode(moduleName, forKey: .swift)
      case .swiftPrebuiltExternal(let moduleName):
        try container.encode(moduleName, forKey: .swiftPrebuiltExternal)
      case .clang(let moduleName):
        try container.encode(moduleName, forKey: .clang)
    }
  }
}

/// Bridging header
public struct BridgingHeader: Codable, Hashable {
  var path: TextualVirtualPath
  /// The source files referenced by the bridging header.
  var sourceFiles: [TextualVirtualPath]
  /// Modules that the bridging header specifically depends on
  var moduleDependencies: [String]
}

/// Linked Library
public struct LinkLibraryInfo: Codable, Hashable {
  public var linkName: String
  public var isFramework: Bool
  public var shouldForceLoad: Bool
}

/// Source 'import'
public struct ImportInfo : Codable, Hashable {
  public enum ImportAccessLevel : Codable, Hashable {
    case Private
    case FilePrivate
    case Internal
    case Package
    case Public
  }

  public var importIdentifier: String
  public var accessLevel: ImportAccessLevel
  public var sourceLocations: [ScannerDiagnosticSourceLocation]

  @_spi(Testing) public init(importIdentifier: String,
                             accessLevel: ImportAccessLevel,
                             sourceLocations: [ScannerDiagnosticSourceLocation]) {
    self.importIdentifier = importIdentifier
    self.accessLevel = accessLevel
    self.sourceLocations = sourceLocations
  }
}

/// Details specific to Swift modules.
public struct SwiftModuleDetails: Codable, Hashable {
  /// The module interface from which this module was built, if any.
  public var moduleInterfacePath: TextualVirtualPath?

  /// The paths of potentially ready-to-use compiled modules for the interface.
  public var compiledModuleCandidates: [TextualVirtualPath]?

  /// The bridging header, if any.
  public var bridgingHeader: BridgingHeader?
  public var bridgingHeaderPath: TextualVirtualPath? {
    bridgingHeader?.path
  }
  public var bridgingSourceFiles: [TextualVirtualPath]? {
    bridgingHeader?.sourceFiles
  }
  public var bridgingHeaderDependencies: [ModuleDependencyId]? {
    bridgingHeader?.moduleDependencies.map { .clang($0) }
  }

  /// Options to the compile command
  public var commandLine: [String]? = []

  /// Options to the compile bridging header command
  public var bridgingPchCommandLine: [String]? = []

  /// The context hash for this module that encodes the producing interface's path,
  /// target triple, etc. This field is optional because it is absent for the ModuleInfo
  /// corresponding to the main module being built.
  public var contextHash: String?

  /// A flag to indicate whether or not this module is a framework.
  public var isFramework: Bool?

  /// A set of Swift Overlays of Clang Module Dependencies
  public var swiftOverlayDependencies: [ModuleDependencyId]?

  /// A set of directly-imported in source module dependencies
  public var sourceImportDependencies: [ModuleDependencyId]?

  /// The module cache key of the output module.
  public var moduleCacheKey: String?

  /// Chained bridging header path
  public var chainedBridgingHeaderPath: String?
  /// Chained bridging header content
  public var chainedBridgingHeaderContent: String?
}

/// Details specific to Swift externally-pre-built modules.
public struct SwiftPrebuiltExternalModuleDetails: Codable, Hashable {
  /// The path to the already-compiled module that must be used instead of
  /// generating a job to build this module.
  public var compiledModulePath: TextualVirtualPath

  /// The path to the .swiftModuleDoc file.
  public var moduleDocPath: TextualVirtualPath?

  /// The path to the .swiftSourceInfo file.
  public var moduleSourceInfoPath: TextualVirtualPath?

  /// The paths to the binary module's header dependencies
  public var headerDependencyPaths: [TextualVirtualPath]?

  /// Clang module dependencies of the textual header input
  public var headerDependencyModuleDependencies: [ModuleDependencyId]?

  /// A flag to indicate whether or not this module is a framework.
  public var isFramework: Bool?

  /// The module cache key of the pre-built module.
  public var moduleCacheKey: String?
}

/// Details specific to Clang modules.
public struct ClangModuleDetails: Codable, Hashable {
  /// The path to the module map used to build this module.
  public var moduleMapPath: TextualVirtualPath

  /// clang-generated context hash
  public var contextHash: String

  /// Options to the compile command
  public var commandLine: [String] = []

  /// The module cache key of the output module.
  public var moduleCacheKey: String?
}

public struct ModuleInfo: Codable, Hashable {
  /// The path for the module.
  public var modulePath: TextualVirtualPath

  /// The source files used to build this module.
  public var sourceFiles: [String]?

  /// The set of directly-imported module dependencies of this module.
  /// For the complete set of all module dependencies of this module,
  /// including Swift overlay dependencies and bridging header dependenceis,
  /// use the `allDependencies` computed property.
  public var directDependencies: [ModuleDependencyId]?

  /// The set of libraries that need to be linked
  public var linkLibraries: [LinkLibraryInfo]?

  /// The set of import details of this module
  public var importInfos: [ImportInfo]?

  /// Specific details of a particular kind of module.
  public var details: Details

  /// Specific details of a particular kind of module.
  public enum Details: Hashable {
    /// Swift modules may be built from a module interface, and may have
    /// a bridging header.
    case swift(SwiftModuleDetails)

    /// Swift externally-prebuilt modules must communicate the path to pre-built binary artifacts
    case swiftPrebuiltExternal(SwiftPrebuiltExternalModuleDetails)

    /// Clang modules are built from a module map file.
    case clang(ClangModuleDetails)
  }

  public init(modulePath: TextualVirtualPath,
              sourceFiles: [String]?,
              directDependencies: [ModuleDependencyId]?,
              linkLibraries: [LinkLibraryInfo]?,
              importInfos: [ImportInfo]?,
              details: Details) {
    self.modulePath = modulePath
    self.sourceFiles = sourceFiles
    self.directDependencies = directDependencies
    self.linkLibraries = linkLibraries
    self.importInfos = importInfos
    self.details = details
  }
}

extension ModuleInfo.Details: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case swiftPrebuiltExternal
    case clang
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      let details = try container.decode(SwiftModuleDetails.self, forKey: .swift)
      self = .swift(details)
    } catch {
      do {
        let details = try container.decode(SwiftPrebuiltExternalModuleDetails.self,
                                           forKey: .swiftPrebuiltExternal)
        self = .swiftPrebuiltExternal(details)
      } catch {
        let details = try container.decode(ClangModuleDetails.self, forKey: .clang)
        self = .clang(details)
      }
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .swift(let details):
        try container.encode(details, forKey: .swift)
      case .swiftPrebuiltExternal(let details):
        try container.encode(details, forKey: .swiftPrebuiltExternal)
      case .clang(let details):
        try container.encode(details, forKey: .clang)
    }
  }
}

extension ModuleInfo {
  var bridgingHeaderModuleDependencies: [ModuleDependencyId]? {
    switch details {
    case .swift(let swiftDetails):
      return swiftDetails.bridgingHeaderDependencies
    case .swiftPrebuiltExternal(let swiftPrebuiltDetails):
      return swiftPrebuiltDetails.headerDependencyModuleDependencies
    default:
      return nil
    }
  }
}

public extension ModuleInfo {
  // Directly-imported dependencies plus additional dependency
  // kinds for Swift modules:
  // - Swift overlay dependencies
  // - Bridging Header dependencies
  var allDependencies: [ModuleDependencyId] {
    var result: [ModuleDependencyId] = directDependencies ?? []
    if case .swift(let swiftModuleDetails) = details {
      // Ensure the dependnecies emitted are unique and follow a predictable ordering:
      // 1. directDependencies in the order reported by the scanner
      // 2. swift overlay dependencies
      // 3. briding header dependencies
      var addedSoFar: Set<ModuleDependencyId> = []
      addedSoFar.formUnion(directDependencies ?? [])
      for depId in swiftModuleDetails.swiftOverlayDependencies ?? [] {
        if addedSoFar.insert(depId).inserted {
          result.append(depId)
        }
      }
      for depId in swiftModuleDetails.bridgingHeaderDependencies ?? [] {
        if addedSoFar.insert(depId).inserted {
          result.append(depId)
        }
      }
    }
    return result
  }
}

/// Describes the complete set of dependencies for a Swift module, including
/// all of the Swift and C modules and source files it depends on.
public struct InterModuleDependencyGraph: Codable {
  /// The name of the main module.
  public let mainModuleName: String

  /// The complete set of modules discovered
  public let modules: ModuleInfoMap

  /// Information about the main module.
  public var mainModule: ModuleInfo { modules[.swift(mainModuleName)]! }
}

@_spi(Testing) public  extension InterModuleDependencyGraph {
  func toJSONData() throws -> Data {
    let encoder = JSONEncoder()
#if os(Linux) || os(Android)
    encoder.outputFormatting = [.prettyPrinted]
#else
    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
      encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    }
#endif
    return try encoder.encode(self)
  }

  func toJSONString() throws -> String {
    return try String(data: toJSONData(), encoding: .utf8)!
  }
}

public struct InterModuleDependencyImports: Codable {
  public var imports: [String]

  public init(imports: [String], moduleAliases: [String: String]? = nil) {
    var realImports = [String]()
    if let aliases = moduleAliases {
      for elem in imports {
        if let realName = aliases[elem] {
          realImports.append(realName)
        } else {
          realImports.append(elem)
        }
      }
    }

    if !realImports.isEmpty {
      self.imports = realImports
    } else {
      self.imports = imports
    }
  }
}
