//===--------------- SwiftModuleArtifacts.swift ---------------------------===//
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

/// Describes a given Swift module's pre-built module artifacts:
/// - Swift Module (name)
/// - Swift Module Path
/// - Swift Doc Path
/// - Swift Source Info Path
@_spi(Testing) public struct SwiftModuleArtifactInfo: Codable, Hashable {
  /// The module's name
  public let moduleName: String
  /// The path for the module's .swiftmodule file
  public let modulePath: TextualVirtualPath
  /// The path for the module's .swiftdoc file
  public let docPath: TextualVirtualPath?
  /// The path for the module's .swiftsourceinfo file
  public let sourceInfoPath: TextualVirtualPath?
  /// Header dependencies of this module
  public let prebuiltHeaderDependencyPaths: [TextualVirtualPath]?
  /// A flag to indicate whether this module is a framework
  public let isFramework: Bool
  /// The cache key for the module.
  public let moduleCacheKey: String?

  init(name: String, modulePath: TextualVirtualPath, docPath: TextualVirtualPath? = nil,
       sourceInfoPath: TextualVirtualPath? = nil, headerDependencies: [TextualVirtualPath]? = nil,
       isFramework: Bool = false, moduleCacheKey: String? = nil) {
    self.moduleName = name
    self.modulePath = modulePath
    self.docPath = docPath
    self.sourceInfoPath = sourceInfoPath
    self.prebuiltHeaderDependencyPaths = headerDependencies
    self.isFramework = isFramework
    self.moduleCacheKey = moduleCacheKey
  }
}

/// Describes a given Clang module's pre-built module artifacts:
/// - Clang Module (name)
/// - Clang Module (PCM) Path
/// - Clang Module Map Path
@_spi(Testing) public struct ClangModuleArtifactInfo: Codable, Hashable {
  /// The module's name
  public let moduleName: String
  /// The path for the module's .pcm file
  public let clangModulePath: TextualVirtualPath
  /// The path for this module's .modulemap file
  public let clangModuleMapPath: TextualVirtualPath
  /// A flag to indicate whether this module is a framework
  public let isFramework: Bool
  /// A flag to indicate whether this module is a dependency
  /// of the main module's bridging header
  public let isBridgingHeaderDependency: Bool
  /// The cache key for the module.
  public let clangModuleCacheKey: String?

  init(name: String, modulePath: TextualVirtualPath, moduleMapPath: TextualVirtualPath,
       moduleCacheKey: String? = nil, isBridgingHeaderDependency: Bool = true) {
    self.moduleName = name
    self.clangModulePath = modulePath
    self.clangModuleMapPath = moduleMapPath
    self.isFramework = false
    self.isBridgingHeaderDependency = isBridgingHeaderDependency
    self.clangModuleCacheKey = moduleCacheKey
  }
}

@_spi(Testing) public enum ModuleDependencyArtifactInfo: Codable {
  case clang(ClangModuleArtifactInfo)
  case swift(SwiftModuleArtifactInfo)

  @_spi(Testing) public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
      case .swift(let swiftInfo):
        try container.encode(swiftInfo)
      case .clang(let clangInfo):
        try container.encode(clangInfo)
    }
  }

  @_spi(Testing) public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    do {
      let thing = try container.decode(SwiftModuleArtifactInfo.self)
      self = .swift(thing)
    } catch {
      let thing =  try container.decode(ClangModuleArtifactInfo.self)
      self = .clang(thing)
    }
  }
}

extension SwiftModuleArtifactInfo: Comparable {
  public static func < (lhs: SwiftModuleArtifactInfo, rhs: SwiftModuleArtifactInfo) -> Bool {
    return lhs.moduleName < rhs.moduleName
  }
}

extension ClangModuleArtifactInfo: Comparable {
  public static func < (lhs: ClangModuleArtifactInfo, rhs: ClangModuleArtifactInfo) -> Bool {
    return lhs.moduleName < rhs.moduleName
  }
}
