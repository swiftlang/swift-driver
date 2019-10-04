import TSCBasic

/// A job represents an individual subprocess that should be invoked during compilation.
public struct Job: Codable, Equatable {
  public enum Kind: String, Codable {
    case compile
    case mergeModule = "merge-module"
    case link
    case generateDSYM = "generate-dsym"
  }

  public enum ArgTemplate: Equatable {
    /// Represents a command-line flag that is substitued as-is.
    case flag(String)

    /// Represents a virtual path on disk.
    case path(VirtualPath)
  }

  /// The tool to invoke.
  public var tool: VirtualPath

  /// The command-line arguments of the job.
  public var commandLine: [ArgTemplate]

  /// The list of inputs to use for displaying purposes.
  public var displayInputs: [TypedVirtualPath]

  /// The list of inputs for this job.
  public var inputs: [TypedVirtualPath]

  /// The outputs produced by the job.
  public var outputs: [TypedVirtualPath]

  /// The kind of job.
  public var kind: Kind

  public init(
    kind: Kind,
    tool: VirtualPath,
    commandLine: [ArgTemplate],
    displayInputs: [TypedVirtualPath]? = nil,
    inputs: [TypedVirtualPath],
    outputs: [TypedVirtualPath]
  ) {
    self.kind = kind
    self.tool = tool
    self.commandLine = commandLine
    self.displayInputs = displayInputs ?? []
    self.inputs = inputs
    self.outputs = outputs
  }
}

extension Job: CustomStringConvertible {
  public var description: String {
    var result: String = tool.name

    for arg in commandLine {
      result += " "
      switch arg {
      case .flag(let string):
        result += string.spm_shellEscaped()
      case .path(let path):
        result += path.name.spm_shellEscaped()
      }
    }

    return result
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
