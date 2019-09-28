import TSCBasic

/// A job represents an individual subprocess that should be invoked during compilation.
public struct Job: Codable {
  /// The tool to invoke.
  public var tool: String

  /// The command-line arguments of the job.
  public var commandLine: [String]

  /// The list of inputs for this job.
  // FIXME: Figure out the exact type that is required here.
  public var inputs: [String]

  /// The outputs produced by the job.
  // FIXME: Figure out the exact type that is required here.
  public var outputs: [String]

  public init(
    tool: String,
    commandLine: [String],
    inputs: [String],
    outputs: [String]
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
