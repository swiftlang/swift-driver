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
    case backend
    case mergeModule = "merge-module"
    case link
    case generateDSYM = "generate-dsym"
    case autolinkExtract = "autolink-extract"
    case emitModule = "emit-module"
    case generatePCH = "generate-pch"
    case moduleWrap = "module-wrap"

    /// Generate a compiled Clang module.
    case generatePCM = "generate-pcm"
    case interpret
    case repl
    case verifyDebugInfo = "verify-debug-info"
    case printTargetInfo = "print-target-info"
    case versionRequest = "version-request"
    case scanDependencies = "scan-dependencies"
    case scanClangDependencies = "scan-clang-dependencies"
    case help
  }

  public enum ArgTemplate: Equatable, Hashable {
    /// Represents a command-line flag that is substitued as-is.
    case flag(String)

    /// Represents a virtual path on disk.
    case path(VirtualPath)

    /// Represents a response file path prefixed by '@'.
    case responseFilePath(VirtualPath)

    /// Represents a joined option+path combo.
    case joinedOptionAndPath(String, VirtualPath)
  }

  /// The Swift module this job involves.
  public var moduleName: String

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
    moduleName: String,
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
    self.moduleName = moduleName
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

extension Job : CustomStringConvertible {
  public var description: String {
    switch kind {
    case .compile:
        return "Compiling \(moduleName) \(displayInputs.first?.file.basename ?? "")"

    case .mergeModule:
        return "Merging module \(moduleName)"

    case .link:
        return "Linking \(moduleName)"

    case .generateDSYM:
        return "Generating dSYM for module \(moduleName)"

    case .autolinkExtract:
        return "Extracting autolink information for module \(moduleName)"

    case .emitModule:
        return "Emitting module for \(moduleName)"

    case .generatePCH:
        return "Compiling bridging header \(displayInputs.first?.file.basename ?? "")"

    case .moduleWrap:
      return "Wrapping Swift module \(moduleName)"

    case .generatePCM:
        return "Compiling Clang module \(moduleName)"

    case .interpret:
        return "Interpreting \(displayInputs.first?.file.name ?? "")"

    case .repl:
        return "Executing Swift REPL"

    case .verifyDebugInfo:
        return "Verifying debug information for module \(moduleName)"

    case .printTargetInfo:
        return "Gathering target information for module \(moduleName)"

    case .versionRequest:
        return "Getting Swift version information"

    case .help:
        return "Swift help"

    case .backend:
      return "Embedding bitcode for \(moduleName) \(displayInputs.first?.file.basename ?? "")"

    case .scanDependencies:
      return "Scanning dependencies for module \(moduleName)"

    case .scanClangDependencies:
      return "Scanning dependencies for Clang module \(moduleName)"
    }
  }
}

extension Job.Kind {
  /// Whether this job kind uses the Swift frontend.
  public var isSwiftFrontend: Bool {
    switch self {
    case .backend, .compile, .mergeModule, .emitModule, .generatePCH,
        .generatePCM, .interpret, .repl, .printTargetInfo,
        .versionRequest, .scanDependencies, .scanClangDependencies:
        return true

    case .autolinkExtract, .generateDSYM, .help, .link, .verifyDebugInfo, .moduleWrap:
        return false
    }
  }

  /// Whether this job kind is a compile job.
  public var isCompile: Bool {
    switch self {
    case .compile:
      return true
    case .backend, .mergeModule, .emitModule, .generatePCH,
         .generatePCM, .interpret, .repl, .printTargetInfo,
         .versionRequest, .autolinkExtract, .generateDSYM,
         .help, .link, .verifyDebugInfo, .scanDependencies,
         .moduleWrap, .scanClangDependencies:
      return false
    }
  }
}
// MARK: - Job.ArgTemplate + Codable

extension Job.ArgTemplate: Codable {
  private enum CodingKeys: String, CodingKey {
    case flag, path, responseFilePath, joinedOptionAndPath

    enum JoinedOptionAndPathCodingKeys: String, CodingKey {
      case option, path
    }
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
    case let .responseFilePath(a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .responseFilePath)
      try unkeyedContainer.encode(a1)
    case let .joinedOptionAndPath(option, path):
      var keyedContainer = container.nestedContainer(
        keyedBy: CodingKeys.JoinedOptionAndPathCodingKeys.self,
        forKey: .joinedOptionAndPath)
      try keyedContainer.encode(option, forKey: .option)
      try keyedContainer.encode(path, forKey: .path)
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
    case .responseFilePath:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(VirtualPath.self)
      self = .responseFilePath(a1)
    case .joinedOptionAndPath:
      let keyedValues = try values.nestedContainer(
        keyedBy: CodingKeys.JoinedOptionAndPathCodingKeys.self,
        forKey: .joinedOptionAndPath)
      self = .joinedOptionAndPath(try keyedValues.decode(String.self, forKey: .option),
                                  try keyedValues.decode(VirtualPath.self, forKey: .path))
    }
  }
}
