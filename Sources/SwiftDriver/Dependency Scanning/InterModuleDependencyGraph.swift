//===--------------- ModuleDependencyGraph.swift --------------------------===//
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


enum ModuleDependencyId: Hashable {
  case swift(String)
  case clang(String)

  var moduleName: String {
    switch self {
      case .swift(let name): return name
      case .clang(let name): return name
    }
  }
}

extension ModuleDependencyId: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case clang
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      let moduleName =  try container.decode(String.self, forKey: .swift)
      self = .swift(moduleName)
    } catch {
      let moduleName =  try container.decode(String.self, forKey: .clang)
      self = .clang(moduleName)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .swift(let moduleName):
        try container.encode(moduleName, forKey: .swift)
      case .clang(let moduleName):
        try container.encode(moduleName, forKey: .clang)
    }
  }
}

/// Details specific to Swift modules.
struct SwiftModuleDetails: Codable {
  /// The module interface from which this module was built, if any.
  var moduleInterfacePath: String?

  /// The bridging header, if any.
  var bridgingHeaderPath: String?

  /// The source files referenced by the bridging header.
  var bridgingSourceFiles: [String]? = []

  /// Options to the compile command
  var commandLine: [String]? = []
}

/// Details specific to Clang modules.
struct ClangModuleDetails: Codable {
  /// The path to the module map used to build this module.
  var moduleMapPath: String

  /// clang-generated context hash
  var contextHash: String?

  /// Options to the compile command
  var commandLine: [String]? = []
}

struct ModuleInfo: Codable {
  /// The path for the module.
  var modulePath: String

  /// The source files used to build this module.
  var sourceFiles: [String] = []

  /// The set of direct module dependencies of this module.
  var directDependencies: [ModuleDependencyId] = []

  /// Specific details of a particular kind of module.
  var details: Details

  /// Specific details of a particular kind of module.
  enum Details {
    /// Swift modules may be built from a module interface, and may have
    /// a bridging header.
    case swift(SwiftModuleDetails)

    /// Clang modules are built from a module map file.
    case clang(ClangModuleDetails)
  }
}

extension ModuleInfo.Details: Codable {
  enum CodingKeys: CodingKey {
    case swift
    case clang
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      let details = try container.decode(SwiftModuleDetails.self, forKey: .swift)
      self = .swift(details)
    } catch {
      let details = try container.decode(ClangModuleDetails.self, forKey: .clang)
      self = .clang(details)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .swift(let details):
        try container.encode(details, forKey: .swift)
      case .clang(let details):
        try container.encode(details, forKey: .clang)
    }
  }
}

/// Describes the complete set of dependencies for a Swift module, including
/// all of the Swift and C modules and source files it depends on.
struct InterModuleDependencyGraph: Codable {
  /// The name of the main module.
  var mainModuleName: String

  /// The complete set of modules discovered
  var modules: [ModuleDependencyId: ModuleInfo] = [:]

  /// Information about the main module.
  var mainModule: ModuleInfo { modules[.swift(mainModuleName)]! }
}
