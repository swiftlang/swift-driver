import TSCBasic

/// A job represents an individual subprocess that should be invoked during compilation.
public struct Job: Codable, Equatable {

  /// A tool that can be invoked during job execution.
  public enum Tool: String, Codable, Equatable {
    case frontend
    case ld
  }

  /// A resource inside the toolchain.
  public enum ToolchainResource: String, Codable, Equatable {
    case sdk
    case clangRT
    case compatibility50
    case compatibilityDynamicReplacements
    case resourcesDir
    case sdkStdlib
  }

  public enum ArgTemplate: Equatable {
    /// Represents a command-line flag that is substitued as-is.
    case flag(String)

    /// Represents a virtual path on disk.
    case path(VirtualPath)

    /// Represents a resource provided by the toolchain.
    case resource(ToolchainResource)
  }

  /// The tool to invoke.
  public var tool: Tool

  /// The command-line arguments of the job.
  public var commandLine: [ArgTemplate]

  /// The list of inputs for this job.
  // FIXME: Figure out the exact type that is required here.
  public var inputs: [VirtualPath]

  /// The outputs produced by the job.
  // FIXME: Figure out the exact type that is required here.
  public var outputs: [VirtualPath]

  public init(
    tool: Tool,
    commandLine: [ArgTemplate],
    inputs: [VirtualPath],
    outputs: [VirtualPath]
  ) {
    self.tool = tool
    self.commandLine = commandLine
    self.inputs = inputs
    self.outputs = outputs
  }
}

/// The type of action.
enum ActionType {
  case compile
  case mergeModule
  case dynamicLink
  case generateDSYM
  case generatePCH
  case verifyDebugInfo
}

// MARK: - Job.ArgTemplate + Codable

extension Job.ArgTemplate: Codable {
  private enum CodingKeys: String, CodingKey {
    case flag, path, resource
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
    case let .resource(a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .resource)
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
    case .resource:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(Job.ToolchainResource.self)
      self = .resource(a1)
    }
  }
}
