//===--------------- ToolExecutionDelegate.swift - Tool Execution Delegate ===//
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

#if canImport(Darwin)
import Darwin.C
#elseif os(Windows)
import ucrt
import WinSDK
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#else
#error("Missing libc or equivalent")
#endif

import class TSCBasic.DiagnosticsEngine
import struct TSCBasic.Diagnostic
import struct TSCBasic.ProcessResult
import var TSCBasic.stderrStream
import var TSCBasic.stdoutStream

/// Delegate for printing execution information on the command-line.
@_spi(Testing) public final class ToolExecutionDelegate: JobExecutionDelegate {
  /// Quasi-PIDs are _negative_ PID-like unique keys used to
  /// masquerade batch job constituents as (quasi)processes, when writing
  /// parseable output to consumers that don't understand the idea of a batch
  /// job. They are negative in order to avoid possibly colliding with real
  /// PIDs (which are always positive). We start at -1000 here as a crude but
  /// harmless hedge against colliding with an errno value that might slip
  /// into the stream of real PIDs.
  static let QUASI_PID_START = -1000

  public enum Mode {
    case verbose
    case parsableOutput
    case regular
    case silent
  }

  public let mode: Mode
  public let buildRecordInfo: BuildRecordInfo?
  public let showJobLifecycle: Bool
  public let diagnosticEngine: DiagnosticsEngine
  public var anyJobHadAbnormalExit: Bool = false

  private var nextBatchQuasiPID: Int
  private let argsResolver: ArgsResolver
  private var batchJobInputQuasiPIDMap = TwoLevelMap<Job, TypedVirtualPath, Int>()

  @_spi(Testing) public init(mode: ToolExecutionDelegate.Mode,
                             buildRecordInfo: BuildRecordInfo?,
                             showJobLifecycle: Bool,
                             argsResolver: ArgsResolver,
                             diagnosticEngine: DiagnosticsEngine) {
    self.mode = mode
    self.buildRecordInfo = buildRecordInfo
    self.showJobLifecycle = showJobLifecycle
    self.diagnosticEngine = diagnosticEngine
    self.argsResolver = argsResolver
    self.nextBatchQuasiPID = ToolExecutionDelegate.QUASI_PID_START
  }

  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    if showJobLifecycle {
      diagnosticEngine.emit(.remark_job_lifecycle("Starting", job))
    }
    switch mode {
    case .regular, .silent:
      break
    case .verbose:
      stdoutStream.send("\(arguments.map { $0.spm_shellEscaped() }.joined(separator: " "))\n")
      stdoutStream.flush()
    case .parsableOutput:
      let messages = constructJobBeganMessages(job: job, arguments: arguments, pid: pid)
      for beganMessage in messages {
        emit(ParsableMessage(name: job.kind.rawValue, kind: .began(beganMessage)))
      }
    }
  }

  public func jobFinished(job: Job, result: ProcessResult, pid: Int) {
     if showJobLifecycle {
      diagnosticEngine.emit(.remark_job_lifecycle("Finished", job))
    }

    buildRecordInfo?.jobFinished(job: job, result: result)

#if os(Windows)
    if case .abnormal = result.exitStatus {
      anyJobHadAbnormalExit = true
    }
#else
    if case .signalled = result.exitStatus {
      anyJobHadAbnormalExit = true
    }
#endif

    switch mode {
    case .silent:
      break

    case .regular, .verbose:
      let output = (try? result.utf8Output() + result.utf8stderrOutput()) ?? ""
      if !output.isEmpty {
        Driver.stdErrQueue.sync {
          stderrStream.send(output)
          stderrStream.flush()
        }
      }

    case .parsableOutput:
      let output = (try? result.utf8Output() + result.utf8stderrOutput()).flatMap { $0.isEmpty ? nil : $0 }
      let messages: [ParsableMessage]

      switch result.exitStatus {
      case .terminated(let code):
        messages = constructJobFinishedMessages(job: job, exitCode: code, output: output,
                                                pid: pid).map {
          ParsableMessage(name: job.kind.rawValue, kind: .finished($0))
        }
#if os(Windows)
      case .abnormal(let exception):
        messages = constructAbnormalExitMessage(job: job, output: output,
                                                exception: exception, pid: pid).map {
          ParsableMessage(name: job.kind.rawValue, kind: .abnormal($0))
        }
#else
      case .signalled(let signal):
#if canImport(Bionic)
        let errorMessage = String(cString: strsignal(signal))
#else
        let errorMessage = strsignal(signal).map { String(cString: $0) } ?? ""
#endif
        messages = constructJobSignalledMessages(job: job, error: errorMessage, output: output,
                                                 signal: signal, pid: pid).map {
          ParsableMessage(name: job.kind.rawValue, kind: .signalled($0))
        }
#endif
      }

      for message in messages {
        emit(message)
      }
    }
  }

  public func jobSkipped(job: Job) {
    if showJobLifecycle {
      diagnosticEngine.emit(.remark_job_lifecycle("Skipped", job))
    }
    switch mode {
    case .regular, .verbose, .silent:
      break
    case .parsableOutput:
      let skippedMessage = SkippedMessage(inputs: job.displayInputs.map{ $0.file.name })
      let message = ParsableMessage(name: job.kind.rawValue, kind: .skipped(skippedMessage))
      emit(message)
    }
  }

  private func emit(_ message: ParsableMessage) {
    // FIXME: Do we need to do error handling here? Can this even fail?
    guard let json = try? message.toJSON() else { return }
    Driver.stdErrQueue.sync {
      stderrStream.send(
        """
        \(json.count)
        \(String(data: json, encoding: .utf8)!)

        """
      )
      stderrStream.flush()
    }
  }
}

// MARK: - Message Construction
/// Generation of messages from jobs, including breaking down batch compile jobs into constituent messages.
private extension ToolExecutionDelegate {

  // MARK: - Job Began
  func constructJobBeganMessages(job: Job, arguments: [String], pid: Int) -> [BeganMessage] {
    let result : [BeganMessage]
    if job.kind == .compile,
       job.primaryInputs.count > 1 {
      // Batched compile jobs need to be broken up into multiple messages, one per constituent.
      result = constructBatchCompileBeginMessages(job: job, arguments: arguments, pid: pid,
                                                  quasiPIDBase: nextBatchQuasiPID)
      // Today, parseable-output messages are constructed and emitted synchronously
      // on `MultiJobExecutor`'s `delegateQueue`. This is why the below operation is safe.
      nextBatchQuasiPID -= result.count
    } else {
      result = [constructSingleBeganMessage(inputs: job.displayInputs,
                                            outputs: job.outputs,
                                            arguments: arguments,
                                            pid: pid,
                                            realPid: pid)]
    }

    return result
  }

  func constructBatchCompileBeginMessages(job: Job, arguments: [String], pid: Int,
                                          quasiPIDBase: Int) -> [BeganMessage] {
    precondition(job.kind == .compile && job.primaryInputs.count > 1)
    var quasiPID = quasiPIDBase
    var result : [BeganMessage] = []
    for input in job.primaryInputs {
      let outputs = job.getCompileInputOutputs(for: input) ?? []
      let outputPaths = outputs.map {
        TypedVirtualPath(file: try! VirtualPath.intern(path: argsResolver.resolve(.path($0.file))),
                         type: $0.type)
      }
      result.append(
        constructSingleBeganMessage(inputs: [input],
                                    outputs: outputPaths,
                                    arguments: arguments,
                                    pid: quasiPID,
                                    realPid: pid))
      // Save the quasiPID of this job/input combination in order to generate the correct
      // `finished` message
      batchJobInputQuasiPIDMap[(job, input)] = quasiPID
      quasiPID -= 1
    }
    return result
  }

  func constructSingleBeganMessage(inputs: [TypedVirtualPath], outputs: [TypedVirtualPath],
                                   arguments: [String], pid: Int, realPid: Int) -> BeganMessage {
    let outputs: [BeganMessage.Output] = outputs.map {
      .init(path: $0.file.name, type: $0.type.description)
    }

    return BeganMessage(
      pid: pid,
      realPid: realPid,
      inputs: inputs.map{ $0.file.name },
      outputs: outputs,
      commandExecutable: arguments[0],
      commandArguments: arguments[1...].map { String($0) }
    )
  }

  // MARK: - Job Finished
  func constructJobFinishedMessages(job: Job, exitCode: Int32, output: String?, pid: Int)
  -> [FinishedMessage] {
    let result : [FinishedMessage]
    if job.kind == .compile,
       job.primaryInputs.count > 1 {
      result = constructBatchCompileFinishedMessages(job: job, exitCode: exitCode,
                                                     output: output, pid: pid)
    } else {
      result = [constructSingleFinishedMessage(exitCode: exitCode, output: output,
                                               pid: pid, realPid: pid)]
    }
    return result
  }

  func constructBatchCompileFinishedMessages(job: Job, exitCode: Int32, output: String?, pid: Int)
  -> [FinishedMessage] {
    precondition(job.kind == .compile && job.primaryInputs.count > 1)
    var result : [FinishedMessage] = []
    for input in job.primaryInputs {
      guard let quasiPid = batchJobInputQuasiPIDMap[(job, input)] else {
        fatalError("Parsable-Output batch sub-job finished with no matching started message: \(job.description) : \(input.file.description)")
      }
      result.append(
        constructSingleFinishedMessage(exitCode: exitCode, output: output,
                                       pid: quasiPid, realPid: pid))
    }
    return result
  }

  func constructSingleFinishedMessage(exitCode: Int32, output: String?, pid: Int, realPid: Int)
  -> FinishedMessage {
    return FinishedMessage(exitStatus: Int(exitCode), output: output, pid: pid, realPid: realPid)
  }

  // MARK: - Abnormal Exit
  func constructAbnormalExitMessage(job: Job, output: String?, exception: UInt32, pid: Int) -> [AbnormalExitMessage] {
    let result: [AbnormalExitMessage]
    if job.kind == .compile, job.primaryInputs.count > 1 {
      result = job.primaryInputs.map {
        guard let quasiPid = batchJobInputQuasiPIDMap[(job, $0)] else {
          fatalError("Parsable-Output batch sub-job abnormal exit with no matching started message: \(job.description): \($0.file.description)")
        }
        return AbnormalExitMessage(pid: quasiPid, realPid: pid, output: output, exception: exception)
      }
    } else {
      result = [AbnormalExitMessage(pid: pid, realPid: pid, output: output, exception: exception)]
    }
    return result
  }

  // MARK: - Job Signalled
  func constructJobSignalledMessages(job: Job, error: String, output: String?,
                                     signal: Int32, pid: Int) -> [SignalledMessage] {
    let result : [SignalledMessage]
    if job.kind == .compile,
       job.primaryInputs.count > 1 {
      result = constructBatchCompileSignalledMessages(job: job, error: error, output: output,
                                                      signal: signal, pid: pid)
    } else {
      result = [constructSingleSignalledMessage(error: error, output: output, signal: signal,
                                                pid: pid, realPid: pid)]
    }
    return result
  }

  func constructBatchCompileSignalledMessages(job: Job, error: String, output: String?,
                                              signal: Int32, pid: Int)
  -> [SignalledMessage] {
    precondition(job.kind == .compile && job.primaryInputs.count > 1)
    var result : [SignalledMessage] = []
    for input in job.primaryInputs {
      guard let quasiPid = batchJobInputQuasiPIDMap[(job, input)] else {
        fatalError("Parsable-Output batch sub-job signalled with no matching started message: \(job.description) : \(input.file.description)")
      }
      result.append(
        constructSingleSignalledMessage(error: error, output: output, signal: signal,
                                        pid: quasiPid, realPid: pid))
    }
    return result
  }

  func constructSingleSignalledMessage(error: String, output: String?, signal: Int32,
                                       pid: Int, realPid: Int)
  -> SignalledMessage {
    return SignalledMessage(pid: pid, realPid: realPid, output: output,
                            errorMessage: error, signal: Int(signal))
  }
}

fileprivate extension Diagnostic.Message {
  static func remark_job_lifecycle(_ what: String, _ job: Job
  ) -> Diagnostic.Message {
    .remark("\(what) \(job.descriptionForLifecycle)")
  }
}
