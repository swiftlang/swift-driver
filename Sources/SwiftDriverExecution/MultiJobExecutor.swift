//===------- MultiJobExecutor.swift - LLBuild-powered job executor --------===//
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
import SwiftDriver

// We either import the llbuildSwift shared library or the llbuild framework.
#if canImport(llbuildSwift)
@_implementationOnly import llbuildSwift
@_implementationOnly import llbuild
#else
@_implementationOnly import llbuild
#endif


public final class MultiJobExecutor {

  /// The context required during job execution.
  /// Must be a class because the producer map can grow as  jobs are added.
  class Context {

    /// This contains mapping from an output to the index(in the jobs array) of the job that produces that output.
    /// Can grow dynamically as  jobs are added.
    var producerMap: [VirtualPath: Int] = [:]

    /// All the jobs being executed.
    var jobs: [Job] = []

    /// The indices into `jobs` for the primary jobs; those that must be run before the full set of
    /// secondaries can be determined. Basically compilations.
    let primaryIndices: Range<Int>

    /// The indices into `jobs` of the jobs that must run *after* all compilations.
    let postCompileIndices: Range<Int>

    /// If non-null, the driver is performing an incremental compilation.
    let incrementalCompilationState: IncrementalCompilationState?

    /// The resolver for argument template.
    let argsResolver: ArgsResolver

    /// The environment variables.
    let env: [String: String]

    /// The file system.
    let fileSystem: TSCBasic.FileSystem

    /// The job executor delegate.
    let executorDelegate: JobExecutionDelegate

    /// Queue for executor delegate.
    let delegateQueue: DispatchQueue = DispatchQueue(label: "org.swift.driver.job-executor-delegate")

    /// Operation queue for executing tasks in parallel.
    let jobQueue: OperationQueue

    /// The process set to use when launching new processes.
    let processSet: ProcessSet?

    /// If true, always use response files to pass command line arguments.
    let forceResponseFiles: Bool

    /// The last time each input file was modified, recorded at the start of the build.
    public let recordedInputModificationDates: [TypedVirtualPath: Date]

    /// The diagnostics engine to use when reporting errors.
    let diagnosticsEngine: DiagnosticsEngine

    /// The type to use when launching new processes. This mostly serves as an override for testing.
    let processType: ProcessProtocol.Type

    /// Records the task build engine for the `ExecuteAllJobs` rule (and task) so that when a
    /// mandatory job finishes, and new jobs are discovered, inputs can be added to that rule for
    /// any newly-required job. Set only once.
    private(set) var executeAllJobsTaskBuildEngine: LLTaskBuildEngine? = nil

    /// If a job fails, the driver needs to stop running jobs.
    private(set) var isBuildCancelled = false

    /// The value of the option
    let continueBuildingAfterErrors: Bool


    init(
      argsResolver: ArgsResolver,
      env: [String: String],
      fileSystem: TSCBasic.FileSystem,
      workload: DriverExecutorWorkload,
      executorDelegate: JobExecutionDelegate,
      jobQueue: OperationQueue,
      processSet: ProcessSet?,
      forceResponseFiles: Bool,
      recordedInputModificationDates: [TypedVirtualPath: Date],
      diagnosticsEngine: DiagnosticsEngine,
      processType: ProcessProtocol.Type = Process.self
    ) {
      (
        jobs: self.jobs,
        producerMap: self.producerMap,
        primaryIndices: self.primaryIndices,
        postCompileIndices: self.postCompileIndices,
        incrementalCompilationState: self.incrementalCompilationState,
        continueBuildingAfterErrors: self.continueBuildingAfterErrors
      ) = Self.fillInJobsAndProducers(workload)

      self.argsResolver = argsResolver
      self.env = env
      self.fileSystem = fileSystem
      self.executorDelegate = executorDelegate
      self.jobQueue = jobQueue
      self.processSet = processSet
      self.forceResponseFiles = forceResponseFiles
      self.recordedInputModificationDates = recordedInputModificationDates
      self.diagnosticsEngine = diagnosticsEngine
      self.processType = processType
    }

    deinit {
      // break a potential cycle
      executeAllJobsTaskBuildEngine = nil
    }

    private static func fillInJobsAndProducers(_ workload: DriverExecutorWorkload
    ) -> (jobs: [Job],
          producerMap: [VirtualPath: Int],
          primaryIndices: Range<Int>,
          postCompileIndices: Range<Int>,
          incrementalCompilationState: IncrementalCompilationState?,
          continueBuildingAfterErrors: Bool)
    {
      var jobs = [Job]()
      var producerMap = [VirtualPath: Int]()
      let primaryIndices, postCompileIndices: Range<Int>
      let incrementalCompilationState: IncrementalCompilationState?
      switch workload.kind {
      case let .incremental(ics):
        incrementalCompilationState = ics
        primaryIndices = Self.addJobs(
          ics.mandatoryJobsInOrder,
          to: &jobs,
          producing: &producerMap
        )
        postCompileIndices = Self.addJobs(
          ics.jobsAfterCompiles,
          to: &jobs,
          producing: &producerMap)
      case let .all(nonincrementalJobs):
        incrementalCompilationState = nil
        primaryIndices = Self.addJobs(
          nonincrementalJobs,
          to: &jobs,
          producing: &producerMap)
        postCompileIndices = 0 ..< 0
      }
      return ( jobs: jobs,
               producerMap: producerMap,
               primaryIndices: primaryIndices,
               postCompileIndices: postCompileIndices,
               incrementalCompilationState: incrementalCompilationState,
               continueBuildingAfterErrors: workload.continueBuildingAfterErrors)
    }

    /// Allow for dynamically adding jobs, since some compile  jobs are added dynamically.
    /// Return the indices into `jobs` of the added jobs.
    @discardableResult
    fileprivate static func addJobs(
      _ js: [Job],
      to jobs: inout [Job],
      producing producerMap: inout [VirtualPath: Int]
    ) -> Range<Int> {
      let initialCount = jobs.count
      for job in js {
        addProducts(of: job, index: jobs.count, knownJobs: jobs, to: &producerMap)
        jobs.append(job)
      }
      return initialCount ..< jobs.count
    }

    ///  Update the producer map when adding a job.
    private static func addProducts(of job: Job,
                                    index: Int,
                                    knownJobs: [Job],
                                    to producerMap: inout [VirtualPath: Int]
    ) {
      for output in job.outputs {
        if let otherJobIndex = producerMap.updateValue(index, forKey: output.file) {
          fatalError("multiple producers for output \(output.file): \(job) & \(knownJobs[otherJobIndex])")
        }
        producerMap[output.file] = index
      }
    }

    fileprivate func setExecuteAllJobsTaskBuildEngine(_ engine: LLTaskBuildEngine) {
      assert(executeAllJobsTaskBuildEngine == nil)
      executeAllJobsTaskBuildEngine = engine
    }

    /// After a job finishes, an incremental build may discover more jobs are needed, or if all compilations
    /// are done, will need to then add in the post-compilation rules.
    fileprivate func addRuleBeyondMandatoryCompiles(
      finishedJob job: Job,
      result: ProcessResult
    ) throws {
      guard job.kind.isCompile else {
        return
      }
      if let newJobs = try incrementalCompilationState?
          .collectJobsDiscoveredToBeNeededAfterFinishing(job: job, result: result) {
        let newJobIndices = Self.addJobs(newJobs, to: &jobs, producing: &producerMap)
        needInputFor(indices: newJobIndices)
      }
      else {
        needInputFor(indices: postCompileIndices)
      }
    }
    fileprivate func needInputFor<Indices: Collection>(indices: Indices)
    where Indices.Element == Int
    {
      for index in indices {
        let key = ExecuteJobRule.RuleKey(index: index)
        executeAllJobsTaskBuildEngine!.taskNeedsInput(key, inputID: index)
      }
    }

    fileprivate func cancelBuildIfNeeded(_ result: ProcessResult) {
      switch (result.exitStatus, continueBuildingAfterErrors) {
      case (.terminated(let code), false) where code != EXIT_SUCCESS:
         isBuildCancelled = true
       #if !os(Windows)
       case (.signalled, _):
         isBuildCancelled = true
       #endif
      default:
        break
      }
    }

    fileprivate func reportSkippedJobs() {
      for job in incrementalCompilationState?.skippedJobs ?? [] {
        executorDelegate.jobSkipped(job: job)
      }
    }
  }

  /// The work to be done.
  private let workload: DriverExecutorWorkload

  /// The argument resolver.
  private let argsResolver: ArgsResolver

  /// The job executor delegate.
  private let executorDelegate: JobExecutionDelegate

  /// The number of jobs to run in parallel.
  private let numParallelJobs: Int

  /// The process set to use when launching new processes.
  private let processSet: ProcessSet?

  /// If true, always use response files to pass command line arguments.
  private let forceResponseFiles: Bool

  /// The last time each input file was modified, recorded at the start of the build.
  private let recordedInputModificationDates: [TypedVirtualPath: Date]

  /// The diagnostics engine to use when reporting errors.
  private let diagnosticsEngine: DiagnosticsEngine

  /// The type to use when launching new processes. This mostly serves as an override for testing.
  private let processType: ProcessProtocol.Type

  public init(
    workload: DriverExecutorWorkload,
    resolver: ArgsResolver,
    executorDelegate: JobExecutionDelegate,
    diagnosticsEngine: DiagnosticsEngine,
    numParallelJobs: Int? = nil,
    processSet: ProcessSet? = nil,
    forceResponseFiles: Bool = false,
    recordedInputModificationDates: [TypedVirtualPath: Date] = [:],
    processType: ProcessProtocol.Type = Process.self
  ) {
    self.workload = workload
    self.argsResolver = resolver
    self.executorDelegate = executorDelegate
    self.diagnosticsEngine = diagnosticsEngine
    self.numParallelJobs = numParallelJobs ?? 1
    self.processSet = processSet
    self.forceResponseFiles = forceResponseFiles
    self.recordedInputModificationDates = recordedInputModificationDates
    self.processType = processType
  }

  /// Execute all jobs.
  public func execute(env: [String: String], fileSystem: TSCBasic.FileSystem) throws {
    let context = createContext(env: env, fileSystem: fileSystem)

    let delegate = JobExecutorBuildDelegate(context)
    let engine = LLBuildEngine(delegate: delegate)

    let result = try engine.build(key: ExecuteAllJobsRule.RuleKey())

    context.reportSkippedJobs()

    // Throw the stub error the build didn't finish successfully.
    if !result.success {
      throw Diagnostics.fatalError
    }
  }

  /// Create the context required during the execution.
  private func createContext(env: [String: String], fileSystem: TSCBasic.FileSystem) -> Context {
    let jobQueue = OperationQueue()
    jobQueue.name = "org.swift.driver.job-execution"
    jobQueue.maxConcurrentOperationCount = numParallelJobs

    return Context(
      argsResolver: argsResolver,
      env: env,
      fileSystem: fileSystem,
      workload: workload,
      executorDelegate: executorDelegate,
      jobQueue: jobQueue,
      processSet: processSet,
      forceResponseFiles: forceResponseFiles,
      recordedInputModificationDates: recordedInputModificationDates,
      diagnosticsEngine: diagnosticsEngine,
      processType: processType
    )
  }
}

struct JobExecutorBuildDelegate: LLBuildEngineDelegate {

  let context: MultiJobExecutor.Context

  init(_ context: MultiJobExecutor.Context) {
    self.context = context
  }

  func lookupRule(rule: String, key: Key) -> Rule {
    switch rule {
    case ExecuteAllJobsRule.ruleName:
      return ExecuteAllJobsRule(context: context)
    case ExecuteJobRule.ruleName:
      return ExecuteJobRule(key, context: context)
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
  }

  override class var ruleName: String { "\(ExecuteAllJobsRule.self)" }

  private let context: MultiJobExecutor.Context

  /// True if any of the inputs had any error.
  private var allInputsSucceeded: Bool = true


  init(context: MultiJobExecutor.Context) {
    self.context = context
    super.init(fileSystem: context.fileSystem)
  }

  override func start(_ engine: LLTaskBuildEngine) {
    context.setExecuteAllJobsTaskBuildEngine(engine)
    context.needInputFor(indices: context.primaryIndices)
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

    let index: Int
  }

  override class var ruleName: String { "\(ExecuteJobRule.self)" }

  private let key: RuleKey
  private let context: MultiJobExecutor.Context

  /// True if any of the inputs had any error.
  private var allInputsSucceeded: Bool = true

  init(_ key: Key, context: MultiJobExecutor.Context) {
    self.key = RuleKey(key)
    self.context = context
    super.init(fileSystem: context.fileSystem)
  }

  override func start(_ engine: LLTaskBuildEngine) {
    requestInputs(from: engine)
  }

  override func isResultValid(_ priorValue: Value) -> Bool {
    return false
  }

  override func provideValue(_ engine: LLTaskBuildEngine, inputID: Int, value: Value) {
    rememberIfInputSucceeded(engine, value: value)
  }

  /// Called when the build engine thinks all inputs are available in order to run the job.
  override func inputsAvailable(_ engine: LLTaskBuildEngine) {
    guard allInputsSucceeded else {
      return engine.taskIsComplete(DriverBuildValue.jobExecution(success: false))
    }

    context.jobQueue.addOperation {
      self.executeJob(engine)
    }
  }

  private var myJob: Job {
    context.jobs[key.index]
  }

  private var inputKeysAndIDs: [(RuleKey, Int)] {
    myJob.inputs.enumerated().compactMap {
      (inputIndex, inputFile) in
      context.producerMap[inputFile.file] .map  { (ExecuteJobRule.RuleKey(index: $0), inputIndex) }
    }
  }

  private func requestInputs(from engine: LLTaskBuildEngine) {
    for (key, ID) in inputKeysAndIDs {
      engine.taskNeedsInput(key, inputID: ID)
    }
  }

  private func rememberIfInputSucceeded(_ engine: LLTaskBuildEngine, value: Value) {
    do {
      let buildValue = try DriverBuildValue(value)
      allInputsSucceeded = allInputsSucceeded && buildValue.success
    } catch {
      allInputsSucceeded = false
    }
  }

  private func executeJob(_ engine: LLTaskBuildEngine) {
    if context.isBuildCancelled {
      engine.taskIsComplete(DriverBuildValue.jobExecution(success: false))
      return
    }
    let context = self.context
    let resolver = context.argsResolver
    let job = myJob
    let env = context.env.merging(job.extraEnvironment, uniquingKeysWith: { $1 })

    let value: DriverBuildValue
    var knownPId = Set<Int>()
    var pid = 0
    do {
      let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                                 forceResponseFiles: context.forceResponseFiles)

      try job.verifyInputsNotModified(since: context.recordedInputModificationDates, fileSystem: engine.fileSystem)

      let process = try context.processType.launchProcess(
        arguments: arguments, env: env
      )
      pid = Int(process.processID)

      // Add it to the process set if it's a real process.
      if case let realProcess as TSCBasic.Process = process {
        try context.processSet?.add(realProcess)
      }

      // Inform the delegate.
      context.delegateQueue.async {
        context.executorDelegate.jobStarted(job: job, arguments: arguments, pid: pid)
        knownPId.insert(pid)
      }

      let result = try process.waitUntilExit()
      let success = result.exitStatus == .terminated(code: EXIT_SUCCESS)

      if !success {
        switch result.exitStatus {
        case let .terminated(code):
          if !job.kind.isCompile || code != EXIT_FAILURE {
            context.diagnosticsEngine.emit(.error_command_failed(kind: job.kind, code: code))
          }
#if !os(Windows)
        case let .signalled(signal):
          context.diagnosticsEngine.emit(.error_command_signalled(kind: job.kind, signal: signal))
#endif
        }
      }

      // Inform the delegate about job finishing.
      context.delegateQueue.async {
        context.executorDelegate.jobFinished(job: job, result: result, pid: pid)
      }
      context.cancelBuildIfNeeded(result)
      if !context.isBuildCancelled {
        try context.addRuleBeyondMandatoryCompiles(finishedJob: job, result: result)
      }
      value = .jobExecution(success: success)
    } catch {
      if error is DiagnosticData {
        context.diagnosticsEngine.emit(error)
      }
      // Only inform finished job if the job has been started, otherwise the build
      // system may complain about malformed output
      if (knownPId.contains(pid)) {
        context.delegateQueue.async {
          let result = ProcessResult(
            arguments: [],
            environment: env,
            exitStatus: .terminated(code: EXIT_FAILURE),
            output: Result.success([]),
            stderrOutput: Result.success([])
          )
          context.executorDelegate.jobFinished(job: job, result: result, pid: pid)
        }
      }
      value = .jobExecution(success: false)
    }

    engine.taskIsComplete(value)
  }
}

extension Job: LLBuildValue { }

private extension TSCBasic.Diagnostic.Message {
  static func error_command_failed(kind: Job.Kind, code: Int32) -> TSCBasic.Diagnostic.Message {
    .error("\(kind.rawValue) command failed with exit code \(code) (use -v to see invocation)")
  }

  static func error_command_signalled(kind: Job.Kind, signal: Int32) -> TSCBasic.Diagnostic.Message {
    .error("\(kind.rawValue) command failed due to signal \(signal) (use -v to see invocation)")
  }
}
