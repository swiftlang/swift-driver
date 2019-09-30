import TSCBasic

/// Resolver for a job's argument template.
public struct ArgsResolver {
  enum Error: Swift.Error {
    case unknownVirtualPath(String)
  }

  /// The toolchain in use.
  public let toolchain: DarwinToolchain

  /// The map of virtual path to the actual path.
  public var pathMapping: [Job.VirtualPath: AbsolutePath]

  public init(toolchain: DarwinToolchain) {
    self.toolchain = toolchain
    self.pathMapping = [:]
  }

  /// Resolve the given argument.
  public func resolve(_ arg: Job.ArgTemplate) throws -> String {
    switch arg {
    case .flag(let flag):
      return flag

    case .path(let path):
      assert(!path.isTemporary, "Temporary path support is not yet implemented")

      guard let actualPath = pathMapping[path] else {
        throw Error.unknownVirtualPath(path.name)
      }
      return actualPath.pathString

    case .resource(let resource):
      return try resolve(resource).pathString
    }
  }

  /// Resolve the given resourse.
  public func resolve(_ resource: Job.ToolchainResource) throws -> AbsolutePath {
    // FIXME: There's probably a better way to model this so we don't end up with a giant switch case.
    // Maybe we can allow expressing paths relative to the resources directory or something.

    switch resource {
    case .sdk:
      return try toolchain.sdk.get()
    case .clangRT:
      return try toolchain.clangRT.get()
    case .compatibility50:
      return try toolchain.compatibility50.get()
    case .compatibilityDynamicReplacements:
      return try toolchain.compatibilityDynamicReplacements.get()
    case .resourcesDir:
      return try toolchain.resourcesDirectory.get()
    case .sdkStdlib:
      return try toolchain.sdkStdlib(sdk: toolchain.sdk.get())
    }
  }

  /// Resolve the given tool.
  public func resolve(_ tool: Job.Tool) -> String {
    switch tool {
    case .frontend:
      return "swift"
    case .ld:
      return "ld"
    }
  }
}

public final class JobExecutor {

  /// The context required during job execution.
  struct Context {

    /// This contains mapping from an output to the job that produces that output.
    let producerMap: [Job.VirtualPath: Job]

    /// The resolver for argument template.
    let argsResolver: ArgsResolver

    init(argsResolver: ArgsResolver, producerMap: [Job.VirtualPath: Job]) {
      self.producerMap = producerMap
      self.argsResolver = argsResolver
    }
  }

  /// The list of jobs that we may need to run.
  let jobs: [Job]

  let argsResolver: ArgsResolver

  public init(jobs: [Job], resolver: ArgsResolver) {
    self.jobs = jobs
    self.argsResolver = resolver
  }

  /// Build the given output.
  public func build(_ output: Job.VirtualPath) throws {
    let context = createContext(jobs)

    let delegate = JobExecutorBuildDelegate(context)
    let engine = LLBuildEngine(delegate: delegate)

    let job = context.producerMap[output]!
    let result = try engine.build(key: ExecuteJobRule.RuleKey(job: job))
    print(result)
  }

  /// Create the context required during the execution.
  func createContext(_ jobs: [Job]) -> Context {
    var producerMap: [Job.VirtualPath: Job] = [:]
    for job in jobs {
      for output in job.outputs {
        assert(!producerMap.keys.contains(output), "multiple producers for output \(output): \(job) \(producerMap[output]!)")
        producerMap[output] = job
      }
    }

    return Context(argsResolver: argsResolver, producerMap: producerMap)
  }
}

struct JobExecutorBuildDelegate: LLBuildEngineDelegate {

  let context: JobExecutor.Context

  init(_ context: JobExecutor.Context) {
    self.context = context
  }

  func lookupRule(rule: String, key: Key) -> Rule {
    switch rule {
    case FileInfoRule.ruleName:
      return FileInfoRule(key)
    case ExecuteJobRule.ruleName:
      return ExecuteJobRule(key)
    default:
      fatalError("Unknown rule \(rule)")
    }
  }
}

class ExecuteJobRule: LLBuildRule {
  struct RuleKey: LLBuildKey {
    typealias BuildValue = RuleValue
    typealias BuildRule = ExecuteJobRule

    let job: Job
  }

  struct RuleValue: LLBuildValue {
    let output: String
    let success: Bool
  }

  override class var ruleName: String { "\(ExecuteJobRule.self)" }

  private let key: RuleKey

  init(_ key: Key) {
    self.key = RuleKey(key)
    super.init()
  }

  override func start(_ engine: LLTaskBuildEngine) {
    let context = engine.jobExecutorContext

    for (idx, input) in key.job.inputs.enumerated() {
      if let producingJob = context.producerMap[input] {
        let key = ExecuteJobRule.RuleKey(job: producingJob)
        engine.taskNeedsInput(key, inputID: idx)
      }
    }
  }

  override func isResultValid(_ priorValue: Value) -> Bool {
    return false
  }

  override func inputsAvailable(_ engine: LLTaskBuildEngine) {
    let context = engine.jobExecutorContext
    let resolver = context.argsResolver
    let job = key.job

    let value: RuleValue
    do {
      let tool = resolver.resolve(job.tool)
      let commandLine = try job.commandLine.map{ try resolver.resolve($0) }

      let process = Process(arguments: [tool] + commandLine)
      try process.launch()
      let result = try process.waitUntilExit()

      let output = try result.utf8Output() + result.utf8stderrOutput()
      value = RuleValue(output: output, success: result.exitStatus == .terminated(code: 0))
    } catch {
      value = RuleValue(output: "\(error)", success: false)
    }
    engine.taskIsComplete(value)
  }
}

/// A rule to get file info of a file on disk.
// FIXME: This is lifted from SwiftPM.
final class FileInfoRule: LLBuildRule {

  struct RuleKey: LLBuildKey {
    typealias BuildValue = RuleValue
    typealias BuildRule = FileInfoRule

    let path: AbsolutePath
  }

  typealias RuleValue = CodableResult<TSCBasic.FileInfo, StringError>

  override class var ruleName: String { "\(FileInfoRule.self)" }

  private let key: RuleKey

  init(_ key: Key) {
    self.key = RuleKey(key)
    super.init()
  }

  override func isResultValid(_ priorValue: Value) -> Bool {
    let priorValue = RuleValue(priorValue)

    // Always rebuild if we had a failure.
    if case .failure = priorValue.result {
      return false
    }
    return getFileInfo(key.path).result == priorValue.result
  }

  override func inputsAvailable(_ engine: LLTaskBuildEngine) {
    engine.taskIsComplete(getFileInfo(key.path))
  }

  private func getFileInfo(_ path: AbsolutePath) -> RuleValue {
    return RuleValue {
      try localFileSystem.getFileInfo(key.path)
    }
  }
}

extension CodableResult: LLBuildValue { }
extension Job: LLBuildValue { }

extension LLTaskBuildEngine {
  /// Returns the job executor context.
  var jobExecutorContext: JobExecutor.Context {
    return (delegate as! JobExecutorBuildDelegate).context
  }
}
