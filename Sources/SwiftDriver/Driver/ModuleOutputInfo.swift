//===--------------- ModuleOutputInfo.swift - Module output information ---===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The information about module output produced by the driver.
@_spi(Testing) public struct ModuleOutputInfo {

  /// How should the Swift module output be handled?
  public enum ModuleOutput: Equatable {
    /// The Swift module is a top-level output.
    case topLevel(VirtualPath.Handle)

    /// The Swift module is an auxiliary output.
    case auxiliary(VirtualPath.Handle)

    public var outputPath: VirtualPath.Handle {
      switch self {
      case .topLevel(let path):
        return path

      case .auxiliary(let path):
        return path
      }
    }

    public var isTopLevel: Bool {
      switch self {
      case .topLevel: return true
      default: return false
      }
    }
  }

  /// The form that the module output will take, e.g., top-level vs. auxiliary,
  /// and the path at which the module should be emitted. `nil` if no module should be emitted.
  public let output: ModuleOutput?

  /// The name of the Swift module being built.
  public let name: String

  /// Whether `name` was picked by the driver instead of the user.
  public let nameIsFallback: Bool

  /// Map of aliases and real names of modules referenced by source files in the current module
  public let aliases: [String: String]?
}
