import TSCBasic

/// A job represents an individual subprocess that should be invoked during compilation.
public struct Job: Codable {

  /// A tool that can be invoked during job execution.
  public enum Tool: String, Codable {
    case frontend
    case ld
  }

  /// A resource inside the toolchain.
  public enum ToolchainResource: String, Codable {
    case sdk
    case clangRT
    case compatibility50
    case compatibilityDynamicReplacements
    case resourcesDir
    case sdkStdlib
  }

  /// A virtual path.
  public struct VirtualPath: Codable, Hashable {
    /// The name of the file must be unique. This will be used to map to the actual path.
    var name: String

    /// True if this path represents a temporary file that is cleaned up after job execution.
    var isTemporary: Bool

    init(name: String, isTemporary: Bool) {
      self.name = name
      self.isTemporary = isTemporary
    }

    public static func path(_ name: String) -> VirtualPath {
      return VirtualPath(name: name, isTemporary: false)
    }

    public static func temporaryFile(_ name: String) -> VirtualPath {
      return VirtualPath(name: name, isTemporary: true)
    }
  }

  public enum ArgTemplate {
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

/// Represents the type of work that needs to be done during compilation.
protocol Action {
  var type: ActionType { get }
}

/// The compile action.
struct CompileAction: Action {
  var type: ActionType { .compile }
}

/// The merge module action.
struct MergeModuleAction: Action {
  var type: ActionType { .mergeModule }
}

/// The link action.
struct DynamicLinkAction: Action {
  var type: ActionType { .dynamicLink }
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
      let a1 = try unkeyedValues.decode(Job.VirtualPath.self)
      self = .path(a1)
    case .resource:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(Job.ToolchainResource.self)
      self = .resource(a1)
    }
  }
}
