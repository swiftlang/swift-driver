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
import Foundation


public enum ModuleDependencyId: Hashable {
  case swift(String)
  case swiftPlaceholder(String)
  case clang(String)

  public var moduleName: String {
    switch self {
    case .swift(let name): return name
    case .swiftPlaceholder(let name): return name
    case .clang(let name): return name
    }
  }
}

extension ModuleDependencyId: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case swiftPlaceholder
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
      case .swiftPlaceholder(let moduleName):
        try container.encode(moduleName, forKey: .swift)
      case .clang(let moduleName):
        try container.encode(moduleName, forKey: .clang)
    }
  }
}

/// Bridging header
public struct BridgingHeader: Codable {
  var path: String
  var sourceFiles: [String]
  var moduleDependencies: [String]
}

/// Details specific to Swift modules.
public struct SwiftModuleDetails: Codable {
  /// The module interface from which this module was built, if any.
  @_spi(Testing) public var moduleInterfacePath: String?

  /// The paths of potentially ready-to-use compiled modules for the interface.
  @_spi(Testing) public var compiledModuleCandidates: [String]?

  /// The path to the already-compiled module that must be used instead of
  /// generating a job to build this module. In standard compilation, the dependency scanner
  /// may discover compiled module candidates to be used instead of re-compiling from interface.
  /// In contrast, this explicitCompiledModulePath is only to be used for precompiled modules
  /// external dependencies in Explicit Module Build mode
  @_spi(Testing) public var explicitCompiledModulePath: String?

  /// The bridging header, if any.
  var bridgingHeaderPath: String?

  /// The source files referenced by the bridging header.
  var bridgingSourceFiles: [String]? = []

  /// Options to the compile command
  var commandLine: [String]? = []

  /// To build a PCM to be used by this Swift module, we need to append these
  /// arguments to the generic PCM build arguments reported from the dependency
  /// graph.
  @_spi(Testing) public var extraPcmArgs: [String]?
}

/// Details specific to Swift external modules.
public struct swiftPlaceholderModuleDetails: Codable {
  /// The path to the .swiftModuleDoc file.
  var moduleDocPath: String?

  /// The path to the .swiftSourceInfo file.
  var moduleSourceInfoPath: String?
}

/// Details specific to Clang modules.
public struct ClangModuleDetails: Codable {
  /// The path to the module map used to build this module.
  @_spi(Testing) public var moduleMapPath: String

  /// clang-generated context hash
  var contextHash: String?

  /// Options to the compile command
  var commandLine: [String]? = []
}

public struct ModuleInfo: Codable {
  /// The path for the module.
  public var modulePath: String

  /// The source files used to build this module.
  public var sourceFiles: [String]? = []

  /// The set of direct module dependencies of this module.
  public var directDependencies: [ModuleDependencyId]? = []

  /// Specific details of a particular kind of module.
  public var details: Details

  /// Specific details of a particular kind of module.
  public enum Details {
    /// Swift modules may be built from a module interface, and may have
    /// a bridging header.
    case swift(SwiftModuleDetails)

    /// Swift external modules carry additional details that specify their
    /// module doc path and source info paths.
    case swiftPlaceholder(swiftPlaceholderModuleDetails)

    /// Clang modules are built from a module map file.
    case clang(ClangModuleDetails)
  }
}

extension ModuleInfo.Details: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case swiftPlaceholder
    case clang
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      let details = try container.decode(SwiftModuleDetails.self, forKey: .swift)
      self = .swift(details)
    } catch {
      do {
        let details = try container.decode(swiftPlaceholderModuleDetails.self, forKey: .swiftPlaceholder)
        self = .swiftPlaceholder(details)
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
      case .swiftPlaceholder(let details):
        try container.encode(details, forKey: .swiftPlaceholder)
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
  public var modules: [ModuleDependencyId: ModuleInfo] = [:]

  /// Information about the main module.
  public var mainModule: ModuleInfo { modules[.swift(mainModuleName)]! }
}
