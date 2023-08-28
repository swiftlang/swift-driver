//===--------------- InterModuleDependencyGraph.swift ---------------------===//
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

import class Foundation.JSONEncoder
import struct Foundation.Data

/// A map from a module identifier to its info
public typealias ModuleInfoMap = [ModuleDependencyId: ModuleInfo]

public enum ModuleDependencyId: Hashable {
  case swift(String)
  case swiftPlaceholder(String)
  case swiftPrebuiltExternal(String)
  case clang(String)

  public var moduleName: String {
    switch self {
    case .swift(let name): return name
    case .swiftPlaceholder(let name): return name
    case .swiftPrebuiltExternal(let name): return name
    case .clang(let name): return name
    }
  }

  internal var moduleNameForDiagnostic: String {
    switch self {
    case .swift(let name): return name
    case .swiftPlaceholder(let name): return name + "(placeholder)"
    case .swiftPrebuiltExternal(let name): return name + "(swiftmodule)"
    case .clang(let name): return name + "(pcm)"
    }
  }
}

extension ModuleDependencyId: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case swiftPlaceholder
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
        let moduleName =  try container.decode(String.self, forKey: .swiftPlaceholder)
        self = .swiftPlaceholder(moduleName)
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
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .swift(let moduleName):
        try container.encode(moduleName, forKey: .swift)
      case .swiftPlaceholder(let moduleName):
        try container.encode(moduleName, forKey: .swiftPlaceholder)
      case .swiftPrebuiltExternal(let moduleName):
        try container.encode(moduleName, forKey: .swiftPrebuiltExternal)
      case .clang(let moduleName):
        try container.encode(moduleName, forKey: .clang)
    }
  }
}

/// Bridging header
public struct BridgingHeader: Codable {
  var path: TextualVirtualPath
  /// The source files referenced by the bridging header.
  var sourceFiles: [TextualVirtualPath]
  /// Modules that the bridging header specifically depends on
  var moduleDependencies: [String]
}

/// Details specific to Swift modules.
public struct SwiftModuleDetails: Codable {
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

  /// Options to the compile command
  public var bridgingPchCommandLine: [String]? = []

  /// The context hash for this module that encodes the producing interface's path,
  /// target triple, etc. This field is optional because it is absent for the ModuleInfo
  /// corresponding to the main module being built.
  public var contextHash: String?

  /// To build a PCM to be used by this Swift module, we need to append these
  /// arguments to the generic PCM build arguments reported from the dependency
  /// graph.
  public var extraPcmArgs: [String]

  /// A flag to indicate whether or not this module is a framework.
  public var isFramework: Bool?

  /// A set of Swift Overlays of Clang Module Dependencies
  var swiftOverlayDependencies: [ModuleDependencyId]?

  /// The module cache key of the output module.
  public var moduleCacheKey: String?
}

/// Details specific to Swift placeholder dependencies.
public struct SwiftPlaceholderModuleDetails: Codable {
  /// The path to the .swiftModuleDoc file.
  var moduleDocPath: TextualVirtualPath?

  /// The path to the .swiftSourceInfo file.
  var moduleSourceInfoPath: TextualVirtualPath?
}

/// Details specific to Swift externally-pre-built modules.
public struct SwiftPrebuiltExternalModuleDetails: Codable {
  /// The path to the already-compiled module that must be used instead of
  /// generating a job to build this module.
  public var compiledModulePath: TextualVirtualPath

  /// The path to the .swiftModuleDoc file.
  public var moduleDocPath: TextualVirtualPath?

  /// The path to the .swiftSourceInfo file.
  public var moduleSourceInfoPath: TextualVirtualPath?

  /// The paths to the binary module's header dependencies
  public var headerDependencyPaths: [TextualVirtualPath]?

  /// A flag to indicate whether or not this module is a framework.
  public var isFramework: Bool?

  /// The module cache key of the pre-built module.
  public var moduleCacheKey: String?

  public init(compiledModulePath: TextualVirtualPath,
              moduleDocPath: TextualVirtualPath? = nil,
              moduleSourceInfoPath: TextualVirtualPath? = nil,
              headerDependencies: [TextualVirtualPath]? = nil,
              isFramework: Bool, moduleCacheKey: String? = nil) throws {
    self.compiledModulePath = compiledModulePath
    self.moduleDocPath = moduleDocPath
    self.moduleSourceInfoPath = moduleSourceInfoPath
    self.headerDependencyPaths = headerDependencies
    self.isFramework = isFramework
    self.moduleCacheKey = moduleCacheKey
  }
}

/// Details specific to Clang modules.
public struct ClangModuleDetails: Codable {
  /// The path to the module map used to build this module.
  public var moduleMapPath: TextualVirtualPath

  /// clang-generated context hash
  public var contextHash: String

  /// Options to the compile command
  public var commandLine: [String] = []

  /// Set of PCM Arguments of depending modules which
  /// are covered by the directDependencies info of this module
  public var capturedPCMArgs: Set<[String]>?

  /// The module cache key of the output module.
  public var moduleCacheKey: String?

  public init(moduleMapPath: TextualVirtualPath,
              contextHash: String,
              commandLine: [String],
              capturedPCMArgs: Set<[String]>?,
              moduleCacheKey: String? = nil) {
    self.moduleMapPath = moduleMapPath
    self.contextHash = contextHash
    self.commandLine = commandLine
    self.capturedPCMArgs = capturedPCMArgs
    self.moduleCacheKey = moduleCacheKey
  }
}

public struct ModuleInfo: Codable {
  /// The path for the module.
  public var modulePath: TextualVirtualPath

  /// The source files used to build this module.
  public var sourceFiles: [String]?

  /// The set of direct module dependencies of this module.
  public var directDependencies: [ModuleDependencyId]?

  /// Specific details of a particular kind of module.
  public var details: Details

  /// The set of all dependencies of this module, include direct and overlay dependencies.
  public var allDependencies: [ModuleDependencyId] {
    var directDeps = Set(directDependencies ?? [])
    if case .swift(let swiftModuleDetails) = self.details  {
      let swiftOverlayDependencies = swiftModuleDetails.swiftOverlayDependencies ?? []
      directDeps.formUnion(swiftOverlayDependencies)
    }
    return Array(directDeps)
  }

  /// Specific details of a particular kind of module.
  public enum Details {
    /// Swift modules may be built from a module interface, and may have
    /// a bridging header.
    case swift(SwiftModuleDetails)

    /// Swift placeholder modules carry additional details that specify their
    /// module doc path and source info paths.
    case swiftPlaceholder(SwiftPlaceholderModuleDetails)

    /// Swift externally-prebuilt modules must communicate the path to pre-built binary artifacts
    case swiftPrebuiltExternal(SwiftPrebuiltExternalModuleDetails)

    /// Clang modules are built from a module map file.
    case clang(ClangModuleDetails)
  }

  public init(modulePath: TextualVirtualPath,
              sourceFiles: [String]?,
              directDependencies: [ModuleDependencyId]?,
              details: Details) {
    self.modulePath = modulePath
    self.sourceFiles = sourceFiles
    self.directDependencies = directDependencies
    self.details = details
  }
}

extension ModuleInfo.Details: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case swiftPlaceholder
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
        let details = try container.decode(SwiftPlaceholderModuleDetails.self,
                                           forKey: .swiftPlaceholder)
        self = .swiftPlaceholder(details)
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
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .swift(let details):
        try container.encode(details, forKey: .swift)
      case .swiftPlaceholder(let details):
        try container.encode(details, forKey: .swiftPlaceholder)
      case .swiftPrebuiltExternal(let details):
        try container.encode(details, forKey: .swiftPrebuiltExternal)
      case .clang(let details):
        try container.encode(details, forKey: .clang)
    }
  }
}

/// Describes the complete set of dependencies for a Swift module, including
/// all of the Swift and C modules and source files it depends on.
public struct InterModuleDependencyGraph: Codable {
  /// The name of the main module.
  public var mainModuleName: String

  /// The complete set of modules discovered
  public var modules: ModuleInfoMap = [:]

  /// Information about the main module.
  public var mainModule: ModuleInfo { modules[.swift(mainModuleName)]! }
}

internal extension InterModuleDependencyGraph {
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
