import TSCBasic

import Foundation
import Dispatch

/// Resolver for a job's argument template.
public struct ArgsResolver {
  /// The toolchain in use.
  public let toolchain: DarwinToolchain

  /// The map of virtual path to the actual path.
  public var pathMapping: [VirtualPath: AbsolutePath]

  /// Path to the directory that will contain the temporary files.
  private let temporaryDirectory: AbsolutePath

  public init(toolchain: DarwinToolchain) throws {
    self.toolchain = toolchain
    self.pathMapping = [:]
    self.temporaryDirectory = try withTemporaryDirectory(removeTreeOnDeinit: false) { path in
      // FIXME: TSC removes empty directories even when removeTreeOnDeinit is false. This seems like a bug.
      try localFileSystem.writeFileContents(path.appending(component: ".keep-directory")) { $0 <<< "" }
      return path
    }
  }

  /// Resolve the given argument.
  public func resolve(_ arg: Job.ArgTemplate) throws -> String {
    switch arg {
    case .flag(let flag):
      return flag

    case .path(let path):
      // Return the path from the temporary directory if this is a temporary file.
      if path.isTemporary {
        let actualPath = temporaryDirectory.appending(component: path.file.name)
        return actualPath.pathString
      }

      // If there was a path mapping, use it.
      if let actualPath = pathMapping[path] {
        return actualPath.pathString
      }

      // Otherwise, return the path.
      return path.file.name

    case .resource(let resource):
      return try resolve(resource).pathString
    }
  }

  /// Remove the temporary directory from disk.
  public func removeTemporaryDirectory() throws {
    _ = try FileManager.default.removeItem(atPath: temporaryDirectory.pathString)
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

public protocol JobExecutorDelegate {
  /// Called when a job starts executing.
  func jobStarted(job: Job)

  /// Called when job had any output.
  func jobHadOutput(job: Job, output: String)

  /// Called when a job finished.
  func jobFinished(job: Job, success: Bool)
}

public final class JobExecutor {

  /// The context required during job execution.
  struct Context {

    /// This contains mapping from an output to the job that produces that output.
    let producerMap: [VirtualPath: Job]

    /// The resolver for argument template.
    let argsResolver: ArgsResolver

    /// The job executor delegate.
    let executorDelegate: JobExecutorDelegate?

    /// Queue for executor delegate.
    let delegateQueue: DispatchQueue = DispatchQueue(label: "org.swift.driver.job-executor-delegate")

    init(argsResolver: ArgsResolver, producerMap: [VirtualPath: Job], executorDelegate: JobExecutorDelegate?) {
      self.producerMap = producerMap
      self.argsResolver = argsResolver
      self.executorDelegate = executorDelegate
    }
  }

  /// The list of jobs that we may need to run.
  let jobs: [Job]

  /// The argument resolver.
  let argsResolver: ArgsResolver

  /// The job executor delegate.
  let executorDelegate: JobExecutorDelegate?

  public init(jobs: [Job], resolver: ArgsResolver, executorDelegate: JobExecutorDelegate? = nil) {
    self.jobs = jobs
    self.argsResolver = resolver
    self.executorDelegate = executorDelegate
  }

  /// Build the given output.
  public func build(_ output: VirtualPath) throws {
    let context = createContext(jobs)

    let delegate = JobExecutorBuildDelegate(context)
    let engine = LLBuildEngine(delegate: delegate)

    let job = context.producerMap[output]!
    _ = try engine.build(key: ExecuteJobRule.RuleKey(job: job))
  }

  /// Create the context required during the execution.
  func createContext(_ jobs: [Job]) -> Context {
    var producerMap: [VirtualPath: Job] = [:]
    for job in jobs {
      for output in job.outputs {
        assert(!producerMap.keys.contains(output), "multiple producers for output \(output): \(job) \(producerMap[output]!)")
        producerMap[output] = job
      }
    }

    return Context(argsResolver: argsResolver, producerMap: producerMap, executorDelegate: executorDelegate)
  }
}

struct JobExecutorBuildDelegate: LLBuildEngineDelegate {

  let context: JobExecutor.Context

  init(_ context: JobExecutor.Context) {
    self.context = context
  }

  func lookupRule(rule: String, key: Key) -> Rule {
    switch rule {
    case ExecuteJobRule.ruleName:
      return ExecuteJobRule(key)
    default:
      fatalError("Unknown rule \(rule)")
    }
  }
}

/// The build value for driver build tasks.
struct DriverBuildValue: LLBuildValue {
  enum Kind: String, Codable {
    case jobExecution
  }

  /// If the build value was a success.
  var success: Bool

  /// The kind of build value.
  var kind: Kind

  static func jobExecution(success: Bool) -> DriverBuildValue {
    return .init(success: success, kind: .jobExecution)
  }
}

class ExecuteJobRule: LLBuildRule {
  struct RuleKey: LLBuildKey {
    typealias BuildValue = DriverBuildValue
    typealias BuildRule = ExecuteJobRule

    let job: Job
  }

  override class var ruleName: String { "\(ExecuteJobRule.self)" }

  private let key: RuleKey

  /// True if any of the inputs had any error.
  private var allInputsSucceeded: Bool = true

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

  override func provideValue(_ engine: LLTaskBuildEngine, inputID: Int, value: Value) {
    do {
      let buildValue = try DriverBuildValue(value)
      allInputsSucceeded = allInputsSucceeded && buildValue.success
    } catch {
      allInputsSucceeded = false
    }
  }

  override func inputsAvailable(_ engine: LLTaskBuildEngine) {
    // Return early any of the input failed.
    guard allInputsSucceeded else {
      return engine.taskIsComplete(DriverBuildValue.jobExecution(success: false))
    }

    let context = engine.jobExecutorContext
    let resolver = context.argsResolver
    let job = key.job

    let value: DriverBuildValue
    do {
      let tool = resolver.resolve(job.tool)
      let commandLine = try job.commandLine.map{ try resolver.resolve($0) }

      let process = Process(arguments: [tool] + commandLine)
      try process.launch()

      // Inform the delegate.
      context.delegateQueue.async {
        context.executorDelegate?.jobStarted(job: job)
      }

      let result = try process.waitUntilExit()
      let success = result.exitStatus == .terminated(code: 0)

      let output = try result.utf8Output() + result.utf8stderrOutput()

      // FIXME: We should stream this.
      context.delegateQueue.async {
        context.executorDelegate?.jobHadOutput(job: job, output: output)
      }

      value = .jobExecution(success: success)
    } catch {
      value = .jobExecution(success: false)
    }

    // Inform the delegate about job finishing.
    context.delegateQueue.async {
      context.executorDelegate?.jobFinished(job: job, success: value.success)
    }

    engine.taskIsComplete(value)
  }
}

extension Job: LLBuildValue { }

extension LLTaskBuildEngine {
  /// Returns the job executor context.
  var jobExecutorContext: JobExecutor.Context {
    return (delegate as! JobExecutorBuildDelegate).context
  }
}
