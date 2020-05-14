//===--------------- Job.swift - Swift Job Abstraction --------------------===//
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
import TSCBasic
import Foundation

/// A job represents an individual subprocess that should be invoked during compilation.
public struct Job: Codable, Equatable, Hashable {
  public enum Kind: String, Codable {
    case compile
    case mergeModule = "merge-module"
    case link
    case generateDSYM = "generate-dsym"
    case autolinkExtract = "autolink-extract"
    case emitModule = "emit-module"
    case generatePCH = "generate-pch"

    /// Generate a compiled Clang module.
    case generatePCM = "generate-pcm"
    case interpret
    case repl
    case verifyDebugInfo = "verify-debug-info"
    case printTargetInfo = "print-target-info"
    case versionRequest = "version-request"
    case help
  }

  public enum ArgTemplate: Equatable, Hashable {
    /// Represents a command-line flag that is substitued as-is.
    case flag(String)

    /// Represents a virtual path on disk.
    case path(VirtualPath)
  }

  /// The tool to invoke.
  public var tool: VirtualPath

  /// The command-line arguments of the job.
  public var commandLine: [ArgTemplate]

  /// Whether or not the job supports using response files to pass command line arguments.
  public var supportsResponseFiles: Bool

  /// The list of inputs to use for displaying purposes.
  public var displayInputs: [TypedVirtualPath]

  /// The list of inputs for this job.
  public var inputs: [TypedVirtualPath]

  /// The outputs produced by the job.
  public var outputs: [TypedVirtualPath]

  /// Any extra environment variables which should be set while running the job.
  public var extraEnvironment: [String: String]

  /// Whether or not the job must be executed in place, replacing the current driver process.
  public var requiresInPlaceExecution: Bool

  /// The kind of job.
  public var kind: Kind

  public init(
    kind: Kind,
    tool: VirtualPath,
    commandLine: [ArgTemplate],
    displayInputs: [TypedVirtualPath]? = nil,
    inputs: [TypedVirtualPath],
    outputs: [TypedVirtualPath],
    extraEnvironment: [String: String] = [:],
    requiresInPlaceExecution: Bool = false,
    supportsResponseFiles: Bool = false
  ) {
    self.kind = kind
    self.tool = tool
    self.commandLine = commandLine
    self.displayInputs = displayInputs ?? []
    self.inputs = inputs
    self.outputs = outputs
    self.extraEnvironment = extraEnvironment
    self.requiresInPlaceExecution = requiresInPlaceExecution
    self.supportsResponseFiles = supportsResponseFiles
  }
}

extension Job {
  public enum InputError: Error, Equatable, DiagnosticData {
    case inputUnexpectedlyModified(TypedVirtualPath)

    public var description: String {
      switch self {
      case .inputUnexpectedlyModified(let input):
        return "input file '\(input.file.name)' was modified during the build"
      }
    }
  }

  public func verifyInputsNotModified(since recordedInputModificationDates: [TypedVirtualPath: Date], fileSystem: FileSystem) throws {
    for input in inputs {
      if case .absolute(let absolutePath) = input.file,
        let recordedModificationTime = recordedInputModificationDates[input],
        try fileSystem.getFileInfo(absolutePath).modTime != recordedModificationTime {
        throw InputError.inputUnexpectedlyModified(input)
      }
    }
  }
}

// MARK: - Job.ArgTemplate + Codable

extension Job.ArgTemplate: Codable {
  private enum CodingKeys: String, CodingKey {
    case flag, path
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .flag(a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .flag)
      try unkeyedContainer.encode(a1)
    case let .path(a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .path)
      try unkeyedContainer.encode(a1)
    }
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard let key = values.allKeys.first(where: values.contains) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
    }
    switch key {
    case .flag:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(String.self)
      self = .flag(a1)
    case .path:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(VirtualPath.self)
      self = .path(a1)
    }
  }
}
