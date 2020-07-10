//===--- CommandInvocation.swift - A command line invocation --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Represents a command to invoke along with its arguments.
public struct CommandInvocation {
  public enum ArgTemplate: Equatable, Hashable {
    /// Represents a command-line flag that is substitued as-is.
    case flag(String)

    /// Represents a virtual path on disk.
    case path(VirtualPath)
  }

  /// The command to invoke.
  public var command: VirtualPath

  /// The arguments to pass to the command.
  public var args: [ArgTemplate]

  public init(_ command: VirtualPath, args: [ArgTemplate]) {
    self.command = command
    self.args = args
  }
}
