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
@_spi(Testing) public struct SwiftModuleArtifactInfo: Codable {
  /// The module's name
  public let moduleName: String
  /// The path for the module's .swiftmodule file
  public let modulePath: TextualVirtualPath
  /// The path for the module's .swiftdoc file
  public let docPath: TextualVirtualPath?
  /// The path for the module's .swiftsourceinfo file
  public let sourceInfoPath: TextualVirtualPath?
  /// A flag to indicate whether this module is a framework
  public let isFramework: Bool

  init(name: String, modulePath: TextualVirtualPath, docPath: TextualVirtualPath? = nil,
       sourceInfoPath: TextualVirtualPath? = nil, isFramework: Bool = false) {
    self.moduleName = name
    self.modulePath = modulePath
    self.docPath = docPath
    self.sourceInfoPath = sourceInfoPath
    self.isFramework = isFramework
  }
}

/// Describes a given Clang module's pre-built module artifacts:
/// - Clang Module (name)
/// - Clang Module (PCM) Path
/// - Clang Module Map Path
@_spi(Testing) public struct ClangModuleArtifactInfo: Codable {
  /// The module's name
  public let moduleName: String
  /// The path for the module's .pcm file
  public let modulePath: TextualVirtualPath
  /// The path for this module's .modulemap file
  public let moduleMapPath: TextualVirtualPath

  init(name: String, modulePath: TextualVirtualPath, moduleMapPath: TextualVirtualPath) {
    self.moduleName = name
    self.modulePath = modulePath
    self.moduleMapPath = moduleMapPath
  }
}

/// Describes a given module's batch dependency scanning input info
/// - Module Name
/// - Extra PCM build arguments (for Clang modules only)
/// - Dependency graph output path
public enum BatchScanModuleInfo: Encodable {
  case swift(BatchScanSwiftModuleInfo)
  case clang(BatchScanClangModuleInfo)
}

public struct BatchScanSwiftModuleInfo: Encodable {
  var swiftModuleName: String
  var output: String

  init(moduleName: String, outputPath: String) {
    self.swiftModuleName = moduleName
    self.output = outputPath
  }
}

public struct BatchScanClangModuleInfo: Encodable {
  var clangModuleName: String
  var arguments: String
  var output: String

  init(moduleName: String, pcmArgs: String, outputPath: String) {
    self.clangModuleName = moduleName
    self.arguments = pcmArgs
    self.output = outputPath
  }
}

public extension BatchScanModuleInfo {
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
      case .swift(let swiftInfo):
        try container.encode(swiftInfo)
      case .clang(let clangInfo):
        try container.encode(clangInfo)
    }
  }
}
