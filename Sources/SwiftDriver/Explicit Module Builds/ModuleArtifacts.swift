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
import Foundation

/// Describes a given Swift module's pre-built module artifacts:
/// - Swift Module (name)
/// - Swift Module Path
/// - Swift Doc Path
/// - Swift Source Info Path
public struct SwiftModuleArtifactInfo: Codable {
  /// The module's name
  public let moduleName: String
  /// The path for the module's .swiftmodule file
  public let modulePath: String
  /// The path for the module's .swiftdoc file
  public let docPath: String?
  /// The path for the module's .swiftsourceinfo file
  public let sourceInfoPath: String?

  init(name: String, modulePath: String, docPath: String? = nil, sourceInfoPath: String? = nil) {
    self.moduleName = name
    self.modulePath = modulePath
    self.docPath = docPath
    self.sourceInfoPath = sourceInfoPath
  }
}

/// Describes a given Clang module's pre-built module artifacts:
/// - Clang Module (name)
/// - Clang Module (PCM) Path
/// - Clang Module Map Path
public struct ClangModuleArtifactInfo {
  /// The module's name
  public let moduleName: String
  /// The path for the module's .pcm file
  public let modulePath: String
  /// The path for this module's .modulemap file
  public let moduleMapPath: String

  init(name: String, modulePath: String, moduleMapPath: String) {
    self.moduleName = name
    self.modulePath = modulePath
    self.moduleMapPath = moduleMapPath
  }
}
