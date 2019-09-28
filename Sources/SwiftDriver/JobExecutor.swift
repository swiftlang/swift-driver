import TSCBasic

public final class JobExecutor {

  /// The list of jobs that we may need to run.
  let jobs: [Job]

  public init(jobs: [Job]) {
    self.jobs = jobs
  }

  /// Build the given output.
  public func build(_ output: String) throws {

    // Compute the producers.
    var producerMap: [String: Job] = [:]
    for job in jobs {
      for output in job.outputs {
        assert(!producerMap.keys.contains(output), "multiple producers for output \(output): \(job) \(producerMap[output]!)")
        producerMap[output] = job
      }
    }

    let delegate = JobExecutorBuildDelegate(producerMap)
    let engine = LLBuildEngine(delegate: delegate)

    let job = producerMap[output]!
    let result = try engine.build(key: ExecuteJobRule.RuleKey(job: job))
    print(result)
  }
}

struct JobExecutorBuildDelegate: LLBuildEngineDelegate {

  let producerMap: [String: Job]

  init(_ producerMap: [String: Job]) {
    self.producerMap = producerMap
  }

  func lookupRule(rule: String, key: Key) -> Rule {
    switch rule {
    case FileInfoRule.ruleName:
      return FileInfoRule(key)
    case ExecuteJobRule.ruleName:
      return ExecuteJobRule(key, producersMap: producerMap)
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

  let producersMap: [String: Job]

  init(_ key: Key, producersMap: [String: Job]) {
    self.key = RuleKey(key)
    self.producersMap = producersMap
    super.init()
  }

  override func start(_ engine: LLTaskBuildEngine) {
    for (idx, input) in key.job.inputs.enumerated() {
      if let producingJob = producersMap[input] {
        let key = ExecuteJobRule.RuleKey(job: producingJob)
        engine.taskNeedsInput(key, inputID: idx)
      } else {
        let key = FileInfoRule.RuleKey(path: AbsolutePath(input))
        engine.taskNeedsInput(key, inputID: idx)
      }
    }
  }

  override func isResultValid(_ priorValue: Value) -> Bool {
    return false
  }

  override func inputsAvailable(_ engine: LLTaskBuildEngine) {
    let value: RuleValue
    do {
      let process = Process(arguments: [key.job.tool] + key.job.commandLine)
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
