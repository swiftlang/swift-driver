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

import SwiftDriver

import class Dispatch.DispatchQueue
import class Foundation.OperationQueue
import class Foundation.FileHandle
import var Foundation.EXIT_SUCCESS
import var Foundation.EXIT_FAILURE
import var Foundation.SIGINT

import class TSCBasic.DiagnosticsEngine
import class TSCBasic.Process
import class TSCBasic.ProcessSet
import protocol TSCBasic.DiagnosticData
import protocol TSCBasic.FileSystem
import struct TSCBasic.Diagnostic
import struct TSCBasic.ProcessResult
import enum TSCUtility.Diagnostics

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
    var producerMap: [VirtualPath.Handle: Int] = [:]

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
    public let recordedInputModificationDates: [TypedVirtualPath: TimePoint]

    /// The diagnostics engine to use when reporting errors.
    let diagnosticsEngine: DiagnosticsEngine

    /// The type to use when launching new processes. This mostly serves as an override for testing.
    let processType: ProcessProtocol.Type

    /// The standard input `FileHandle` override for testing.
    let testInputHandle: FileHandle?

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
      recordedInputModificationDates: [TypedVirtualPath: TimePoint],
      diagnosticsEngine: DiagnosticsEngine,
      processType: ProcessProtocol.Type = Process.self,
      inputHandleOverride: FileHandle? = nil
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
      self.testInputHandle = inputHandleOverride
    }

    private static func fillInJobsAndProducers(_ workload: DriverExecutorWorkload
    ) -> (jobs: [Job],
          producerMap: [VirtualPath.Handle: Int],
          primaryIndices: Range<Int>,
          postCompileIndices: Range<Int>,
          incrementalCompilationState: IncrementalCompilationState?,
          continueBuildingAfterErrors: Bool)
    {
      var jobs = [Job]()
      var producerMap = [VirtualPath.Handle: Int]()
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
      producing producerMap: inout [VirtualPath.Handle: Int]
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
                                    to producerMap: inout [VirtualPath.Handle: Int]
    ) {
      for output in job.outputs {
        if output.file != .standardOutput,
           let otherJobIndex = producerMap.updateValue(index, forKey: output.fileHandle) {
          fatalError("multiple producers for output \(output.file): \(job) & \(knownJobs[otherJobIndex])")
        }
        producerMap[output.fileHandle] = index
      }
    }

    fileprivate func getIncrementalJobIndices(finishedJob jobIdx: Int) throws -> Range<Int> {
      if let newJobs = try incrementalCompilationState?
          .collectJobsDiscoveredToBeNeededAfterFinishing(job: jobs[jobIdx]) {
        return Self.addJobs(newJobs, to: &jobs, producing: &producerMap)
      }
      return 0..<0
    }

    fileprivate func cancelBuildIfNeeded(_ result: ProcessResult) {
      switch (result.exitStatus, continueBuildingAfterErrors) {
      case (.terminated(let code), false) where code != EXIT_SUCCESS:
         isBuildCancelled = true
#if os(Windows)
      case (.abnormal, false):
         isBuildCancelled = true
#else
       case (.signalled, _):
         isBuildCancelled = true
#endif
      default:
        break
      }
    }

    fileprivate func reportSkippedJobs() {
      for job in incrementalCompilationState?.blockingConcurrentMutationToProtectedState({ $0.skippedJobs }) ?? [] {
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
  private let recordedInputModificationDates: [TypedVirtualPath: TimePoint]

  /// The diagnostics engine to use when reporting errors.
  private let diagnosticsEngine: DiagnosticsEngine

  /// The type to use when launching new processes. This mostly serves as an override for testing.
  private let processType: ProcessProtocol.Type

  /// The standard input `FileHandle`  override for testing.
  let testInputHandle: FileHandle?

  public init(
    workload: DriverExecutorWorkload,
    resolver: ArgsResolver,
    executorDelegate: JobExecutionDelegate,
    diagnosticsEngine: DiagnosticsEngine,
    numParallelJobs: Int? = nil,
    processSet: ProcessSet? = nil,
    forceResponseFiles: Bool = false,
    recordedInputModificationDates: [TypedVirtualPath: TimePoint] = [:],
    processType: ProcessProtocol.Type = Process.self,
    inputHandleOverride: FileHandle? = nil
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
    self.testInputHandle = inputHandleOverride
  }

  /// Execute all jobs.
  public func execute(env: [String: String], fileSystem: TSCBasic.FileSystem) throws {
    let context = createContext(env: env, fileSystem: fileSystem)

    let delegate = JobExecutorBuildDelegate(context)
    let engine = LLBuildEngine(delegate: delegate)

    let result = try engine.build(key: ExecuteAllJobsRule.RuleKey())

    context.reportSkippedJobs()

    // Check for any inputs that were modified during the build. Report these
    // as errors so we don't e.g. reuse corrupted incremental build state.
    for (input, recordedModTime) in context.recordedInputModificationDates {
      guard try fileSystem.lastModificationTime(for: input.file) == recordedModTime else {
        let err = Job.InputError.inputUnexpectedlyModified(input)
        context.diagnosticsEngine.emit(err)
        throw err
      }
    }

    // Throw the stub error the build didn't finish successfully.
    if !result.success {
      throw Driver.ErrorDiagnostics.emitted
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
      processType: processType,
      inputHandleOverride: testInputHandle
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
    case ExecuteAllCompilationJobsRule.ruleName:
      return ExecuteAllCompilationJobsRule(context: context)
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

/// A rule represents all jobs to finish compiling a module, including mandatory jobs,
/// incremental jobs, and post-compilation jobs.
class ExecuteAllJobsRule: LLBuildRule {
  struct RuleKey: LLBuildKey {
    typealias BuildValue = DriverBuildValue
    typealias BuildRule = ExecuteAllJobsRule
  }
  private let context: MultiJobExecutor.Context

  override class var ruleName: String { "\(ExecuteAllJobsRule.self)" }

  /// True if any of the inputs had any error.
  private var allInputsSucceeded: Bool = true

  /// Input ID for the requested ExecuteAllCompilationJobsRule
  private let allCompilationId = Int.max

  init(context: MultiJobExecutor.Context) {
    self.context = context
    super.init(fileSystem: context.fileSystem)
  }

  override func start(_ engine: LLTaskBuildEngine) {
    // Requests all compilation jobs to be done
    engine.taskNeedsInput(ExecuteAllCompilationJobsRule.RuleKey(), inputID: allCompilationId)
  }

  override func provideValue(_ engine: LLTaskBuildEngine, inputID: Int, value: Value) {
    do {
      let subtaskSuccess = try DriverBuildValue(value).success
      // After all compilation jobs are done, we can schedule post-compilation jobs,
      // including merge module and linking jobs.
      if inputID == allCompilationId && subtaskSuccess {
        schedulePostCompileJobs(engine)
      }
      allInputsSucceeded = allInputsSucceeded && subtaskSuccess
    } catch {
      allInputsSucceeded = false
    }
  }

  /// After all compilation jobs have run, figure which, for instance link, jobs must run
  private func schedulePostCompileJobs(_ engine: LLTaskBuildEngine) {
    func schedule(_ postCompileIndex: Int) {
      engine.taskNeedsInput(ExecuteJobRule.RuleKey(index: postCompileIndex),
                            inputID: postCompileIndex)
    }
    let didAnyCompileJobsRun = !context.primaryIndices.isEmpty
    /// If any compile jobs ran, skip the expensive mod-time checks
    let scheduleEveryPostCompileJob = didAnyCompileJobsRun
    if let incrementalCompilationState = context.incrementalCompilationState,
       !scheduleEveryPostCompileJob {
      for postCompileIndex in context.postCompileIndices
      where !incrementalCompilationState.canSkip(postCompileJob: context.jobs[postCompileIndex]) {
        schedule(postCompileIndex)
      }
    }
    else {
      context.incrementalCompilationState?.reporter?.report(
        "Scheduling all post-compile jobs because something was compiled")
      context.postCompileIndices.forEach(schedule)
    }
 }

  override func inputsAvailable(_ engine: LLTaskBuildEngine) {
    engine.taskIsComplete(DriverBuildValue.jobExecution(success: allInputsSucceeded))
  }
}

/// A rule for evaluating all compilation jobs, including mandatory and Incremental
/// compilations.
class ExecuteAllCompilationJobsRule: LLBuildRule {
  struct RuleKey: LLBuildKey {
    typealias BuildValue = DriverBuildValue
    typealias BuildRule = ExecuteAllCompilationJobsRule
  }

  override class var ruleName: String { "\(ExecuteAllCompilationJobsRule.self)" }

  private let context: MultiJobExecutor.Context

  /// True if any of the inputs had any error.
  private var allInputsSucceeded: Bool = true

  init(context: MultiJobExecutor.Context) {
    self.context = context
    super.init(fileSystem: context.fileSystem)
  }

  override func start(_ engine: LLTaskBuildEngine) {
    // We need to request those mandatory jobs to be done first.
    context.primaryIndices.forEach {
      let key = ExecuteJobRule.RuleKey(index: $0)
      engine.taskNeedsInput(key, inputID: $0)
    }
  }

  override func isResultValid(_ priorValue: Value) -> Bool {
    return false
  }

  override func provideValue(_ engine: LLTaskBuildEngine, inputID: Int, value: Value) {
    do {
      let buildSuccess = try DriverBuildValue(value).success
      // For each finished job, ask the incremental build oracle for additional
      // jobs to be scheduled and request them as the additional inputs for this
      // rule.
      if buildSuccess && !context.isBuildCancelled {
        try context.getIncrementalJobIndices(finishedJob: inputID).forEach {
          engine.taskNeedsInput(ExecuteJobRule.RuleKey(index: $0), inputID: $0)
        }
      }
      allInputsSucceeded = allInputsSucceeded && buildSuccess
    } catch {
      allInputsSucceeded = false
    }
  }

  override func inputsAvailable(_ engine: LLTaskBuildEngine) {
    engine.taskIsComplete(DriverBuildValue.jobExecution(success: allInputsSucceeded))
  }
}
/// A rule for a single compiler invocation.
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
    // Request all compilation jobs whose outputs this rule depends on.
    for (inputIndex, inputFile) in self.myJob.inputs.enumerated() {
      guard let index = self.context.producerMap[inputFile.fileHandle] else {
        continue
      }
      engine.taskNeedsInput(ExecuteJobRule.RuleKey(index: index), inputID: inputIndex)
    }
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
    // We are ready to schedule this job.
    // llbuild relies on the client-side to handle asynchronous runs, so we should
    // execute the job asynchronously without blocking the callback thread.
    // taskIsComplete can be safely called from another thread. The only restriction
    // is we should call it after inputsAvailable is called.
    context.jobQueue.addOperation {
      self.executeJob(engine)
    }
  }

  private var myJob: Job {
    context.jobs[key.index]
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
    var pendingFinish = false
    var pid = 0
    do {
      let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                                 useResponseFiles: context.forceResponseFiles ? .forced : .heuristic)


      let process : ProcessProtocol
      // If the input comes from standard input, forward the driver's input to the compile job.
      if job.inputs.contains(TypedVirtualPath(file: .standardInput, type: .swift)) {
        let inputFileHandle = context.testInputHandle ?? FileHandle.standardInput
        process = try context.processType.launchProcessAndWriteInput(
          arguments: arguments, env: env, inputFileHandle: inputFileHandle
        )
      } else {
        process = try context.processType.launchProcess(
          arguments: arguments, env: env
        )
      }

      pid = Int(process.processID)

      // Add it to the process set if it's a real process.
      if case let realProcess as TSCBasic.Process = process {
        try context.processSet?.add(realProcess)
      }

      // Inform the delegate.
      context.delegateQueue.sync {
        context.executorDelegate.jobStarted(job: job, arguments: arguments, pid: pid)
      }
      pendingFinish = true

      let result = try process.waitUntilExit()
      let success = result.exitStatus == .terminated(code: EXIT_SUCCESS)

      if !success {
        job.removeOutputsOfFailedCompilation(from: context.fileSystem)
        switch result.exitStatus {
        case let .terminated(code):
          if !job.kind.isCompile || code != EXIT_FAILURE {
            context.diagnosticsEngine.emit(.error_command_failed(kind: job.kind, code: code))
          }
#if os(Windows)
        case let .abnormal(exception):
          context.diagnosticsEngine.emit(.error_command_exception(kind: job.kind, exception: exception))
#else
        case let .signalled(signal):
          // An interrupt of an individual compiler job means it was deliberately cancelled,
          // most likely by the driver itself. This does not constitute an error.
          if signal != SIGINT {
            context.diagnosticsEngine.emit(.error_command_signalled(kind: job.kind, signal: signal))
          }
#endif
        }
      }

      // Inform the delegate about job finishing.
      context.delegateQueue.sync {
        context.executorDelegate.jobFinished(job: job, result: result, pid: pid)
      }
      pendingFinish = false
      context.cancelBuildIfNeeded(result)
      value = .jobExecution(success: success)
    } catch {
      if error is DiagnosticData {
        context.diagnosticsEngine.emit(error)
      }
      // Only inform finished job if the job has been started, otherwise the build
      // system may complain about malformed output
      if (pendingFinish) {
        context.delegateQueue.sync {
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

fileprivate extension Job {
  /// Don't leave incorrect compiler outputs lying around, but don't remove diagnostics!
  func removeOutputsOfFailedCompilation(from fileSystem: TSCBasic.FileSystem) {
    guard kind.isCompile else {return}
    for output in outputs where output.type != .diagnostics {
      guard let absolutePath = output.file.absolutePath else { continue }
      try? fileSystem.removeFileTree(absolutePath)
    }
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

  static func error_command_exception(kind: Job.Kind, exception: UInt32) -> TSCBasic.Diagnostic.Message {
    .error("\(kind.rawValue) command failed due to exception \(exception) (use -v to see invocation)")
  }
}
