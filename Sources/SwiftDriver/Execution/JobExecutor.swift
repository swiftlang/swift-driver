//===--------------- JobExecutor.swift - Swift Job Execution --------------===//
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
import enum TSCUtility.Diagnostics

import Foundation
import Dispatch

/// Resolver for a job's argument template.
public struct ArgsResolver {
  /// The map of virtual path to the actual path.
  public var pathMapping: [VirtualPath: AbsolutePath]

  /// Path to the directory that will contain the temporary files.
  private let temporaryDirectory: AbsolutePath

  public init() throws {
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
        let actualPath = temporaryDirectory.appending(component: path.name)
        return actualPath.pathString
      }

      // If there was a path mapping, use it.
      if let actualPath = pathMapping[path] {
        return actualPath.pathString
      }

      // Otherwise, return the path.
      return path.name
    }
  }

  /// Remove the temporary directory from disk.
  public func removeTemporaryDirectory() throws {
    _ = try FileManager.default.removeItem(atPath: temporaryDirectory.pathString)
  }
}

public protocol JobExecutorDelegate {
  /// Called when a job starts executing.
  func jobStarted(job: Job, arguments: [String], pid: Int)

  /// Called when a job finished.
  func jobFinished(job: Job, result: ProcessResult, pid: Int)

  /// Launch the process for given command line.
  ///
  /// This will be called on the execution queue.
  func launchProcess(for job: Job, arguments: [String], env: [String: String]) throws -> ProcessProtocol
}

extension JobExecutorDelegate {
  public func launchProcess(for job: Job, arguments: [String], env: [String: String]) throws -> ProcessProtocol {
    return try Process.launchProcess(arguments: arguments, env: env)
  }
}

public final class JobExecutor {

  /// The context required during job execution.
  struct Context {

    /// This contains mapping from an output to the job that produces that output.
    let producerMap: [VirtualPath: Job]

    /// The resolver for argument template.
    let argsResolver: ArgsResolver
    
    /// The environment variables.
    let env: [String: String]

    /// The job executor delegate.
    let executorDelegate: JobExecutorDelegate

    /// Queue for executor delegate.
    let delegateQueue: DispatchQueue = DispatchQueue(label: "org.swift.driver.job-executor-delegate")

    /// Operation queue for executing tasks in parallel.
    let jobQueue: OperationQueue

    /// The process set to use when launching new processes.
    let processSet: ProcessSet?

    init(
      argsResolver: ArgsResolver,
      env: [String: String],
      producerMap: [VirtualPath: Job],
      executorDelegate: JobExecutorDelegate,
      jobQueue: OperationQueue,
      processSet: ProcessSet?
    ) {
      self.producerMap = producerMap
      self.argsResolver = argsResolver
      self.env = env
      self.executorDelegate = executorDelegate
      self.jobQueue = jobQueue
      self.processSet = processSet
    }
  }

  /// The list of jobs that we may need to run.
  let jobs: [Job]

  /// The argument resolver.
  let argsResolver: ArgsResolver

  /// The job executor delegate.
  let executorDelegate: JobExecutorDelegate

  /// The number of jobs to run in parallel.
  let numParallelJobs: Int

  /// The process set to use when launching new processes.
  let processSet: ProcessSet?

  public init(
    jobs: [Job],
    resolver: ArgsResolver,
    executorDelegate: JobExecutorDelegate,
    numParallelJobs: Int? = nil,
    processSet: ProcessSet? = nil
  ) {
    self.jobs = jobs
    self.argsResolver = resolver
    self.executorDelegate = executorDelegate
    self.numParallelJobs = numParallelJobs ?? 1
    self.processSet = processSet
  }

  /// Execute all jobs.
  public func execute(env: [String: String]) throws {
    let context = createContext(jobs, env: env)

    let delegate = JobExecutorBuildDelegate(context)
    let engine = LLBuildEngine(delegate: delegate)

    let result = try engine.build(key: ExecuteAllJobsRule.RuleKey(jobs: jobs))

    // Throw the stub error the build didn't finish successfully.
    if !result.success {
      throw Diagnostics.fatalError
    }
  }

  /// Create the context required during the execution.
  func createContext(_ jobs: [Job], env: [String: String]) -> Context {
    var producerMap: [VirtualPath: Job] = [:]
    for job in jobs {
      for output in job.outputs {
        assert(!producerMap.keys.contains(output.file), "multiple producers for output \(output): \(job) \(producerMap[output.file]!)")
        producerMap[output.file] = job
      }
    }

    let jobQueue = OperationQueue()
    jobQueue.name = "org.swift.driver.job-execution"
    jobQueue.maxConcurrentOperationCount = numParallelJobs

    return Context(
      argsResolver: argsResolver,
      env: env,
      producerMap: producerMap,
      executorDelegate: executorDelegate,
      jobQueue: jobQueue,
      processSet: processSet
    )
  }
}

struct JobExecutorBuildDelegate: LLBuildEngineDelegate {

  let context: JobExecutor.Context

  init(_ context: JobExecutor.Context) {
    self.context = context
  }

  func lookupRule(rule: String, key: Key) -> Rule {
    switch rule {
    case ExecuteAllJobsRule.ruleName:
      return ExecuteAllJobsRule(key)
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

class ExecuteAllJobsRule: LLBuildRule {
  struct RuleKey: LLBuildKey {
    typealias BuildValue = DriverBuildValue
    typealias BuildRule = ExecuteAllJobsRule

    let jobs: [Job]
  }

  override class var ruleName: String { "\(ExecuteAllJobsRule.self)" }

  private let key: RuleKey

  /// True if any of the inputs had any error.
  private var allInputsSucceeded: Bool = true

  init(_ key: Key) {
    self.key = RuleKey(key)
    super.init()
  }

  override func start(_ engine: LLTaskBuildEngine) {
    for (idx, job) in key.jobs.enumerated() {
        let key = ExecuteJobRule.RuleKey(job: job)
        engine.taskNeedsInput(key, inputID: idx)
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
    engine.taskIsComplete(DriverBuildValue.jobExecution(success: allInputsSucceeded))
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
      if let producingJob = context.producerMap[input.file] {
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
    context.jobQueue.addOperation {
      self.executeJob(engine)
    }
  }

  private func executeJob(_ engine: LLTaskBuildEngine) {
    let context = engine.jobExecutorContext
    let resolver = context.argsResolver
    let job = key.job
    let env = context.env.merging(job.extraEnvironment, uniquingKeysWith: { $1 })

    let value: DriverBuildValue
    var pid = 0
    do {
      let tool = try resolver.resolve(.path(job.tool))
      let commandLine = try job.commandLine.map{ try resolver.resolve($0) }
      let arguments = [tool] + commandLine

      let process = try context.executorDelegate.launchProcess(
        for: job, arguments: arguments, env: env
      )
      pid = Int(process.processID)

      // Add it to the process set if it's a real process.
      if case let realProcess as TSCBasic.Process = process {
        try context.processSet?.add(realProcess)
      }

      // Inform the delegate.
      context.delegateQueue.async {
        context.executorDelegate.jobStarted(job: job, arguments: arguments, pid: pid)
      }

      let result = try process.waitUntilExit()
      let success = result.exitStatus == .terminated(code: 0)

      // Inform the delegate about job finishing.
      context.delegateQueue.async {
        context.executorDelegate.jobFinished(job: job, result: result, pid: pid)
      }

      value = .jobExecution(success: success)
    } catch {
      context.delegateQueue.async {
        let result = ProcessResult(
          arguments: [],
          exitStatus: .terminated(code: 1),
          output: Result.success([]),
          stderrOutput: Result.success([])
        )
        context.executorDelegate.jobFinished(job: job, result: result, pid: 0)
      }
      value = .jobExecution(success: false)
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
