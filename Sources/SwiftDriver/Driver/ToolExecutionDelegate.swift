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
import TSCBasic

#if canImport(Darwin)
import Darwin.C
#elseif os(Windows)
import ucrt
import WinSDK
#elseif canImport(Glibc)
import Glibc
#else
#error("Missing libc or equivalent")
#endif

/// Delegate for printing execution information on the command-line.
final class ToolExecutionDelegate: JobExecutionDelegate {
  public enum Mode {
    case verbose
    case parsableOutput
    case regular
  }

  public let mode: Mode
  public let buildRecordInfo: BuildRecordInfo?
  public let incrementalCompilationState: IncrementalCompilationState?
  public let showJobLifecycle: Bool
  public let diagnosticEngine: DiagnosticsEngine

  public var anyJobHadAbnormalExit: Bool = false

  init(mode: ToolExecutionDelegate.Mode,
       buildRecordInfo: BuildRecordInfo?,
       incrementalCompilationState: IncrementalCompilationState?,
       showJobLifecycle: Bool,
       diagnosticEngine: DiagnosticsEngine) {
    self.mode = mode
    self.buildRecordInfo = buildRecordInfo
    self.incrementalCompilationState = incrementalCompilationState
    self.showJobLifecycle = showJobLifecycle
    self.diagnosticEngine = diagnosticEngine
  }

  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    if showJobLifecycle {
      diagnosticEngine.emit(.remark_job_lifecycle("Starting", job))
    }
    switch mode {
    case .regular:
      break
    case .verbose:
      stdoutStream <<< arguments.map { $0.spm_shellEscaped() }.joined(separator: " ") <<< "\n"
      stdoutStream.flush()
    case .parsableOutput:

      // Compute the outputs for the message.
      let outputs: [BeganMessage.Output] = job.outputs.map {
        .init(path: $0.file.name, type: $0.type.description)
      }

      let beganMessage = BeganMessage(
        pid: pid,
        inputs: job.displayInputs.map{ $0.file.name },
        outputs: outputs,
        commandExecutable: arguments[0],
        commandArguments: arguments[1...].map { String($0) }
      )

      let message = ParsableMessage(name: job.kind.rawValue, kind: .began(beganMessage))
      emit(message)
    }
  }

  public func jobFinished(job: Job, result: ProcessResult, pid: Int) {
     if showJobLifecycle {
      diagnosticEngine.emit(.remark_job_lifecycle("Finished", job))
    }

    buildRecordInfo?.jobFinished(job: job, result: result)

    // FIXME: Currently, TSCBasic.Process uses NSProcess on Windows and discards
    // the bits of the exit code used to differentiate between normal and abnormal
    // termination.
    #if !os(Windows)
    if case .signalled = result.exitStatus {
      anyJobHadAbnormalExit = true
    }
    #endif

    switch mode {
    case .regular, .verbose:
      let output = (try? result.utf8Output() + result.utf8stderrOutput()) ?? ""
      if !output.isEmpty {
        Driver.stdErrQueue.sync {
          stderrStream <<< output
          stderrStream.flush()
        }
      }

    case .parsableOutput:
      let output = (try? result.utf8Output() + result.utf8stderrOutput()).flatMap { $0.isEmpty ? nil : $0 }
      let message: ParsableMessage

      switch result.exitStatus {
      case .terminated(let code):
        let finishedMessage = FinishedMessage(exitStatus: Int(code), pid: pid, output: output)
        message = ParsableMessage(name: job.kind.rawValue, kind: .finished(finishedMessage))

#if !os(Windows)
      case .signalled(let signal):
        let errorMessage = strsignal(signal).map { String(cString: $0) } ?? ""
        let signalledMessage = SignalledMessage(pid: pid, output: output, errorMessage: errorMessage, signal: Int(signal))
        message = ParsableMessage(name: job.kind.rawValue, kind: .signalled(signalledMessage))
#endif
      }
      emit(message)
    }
  }

  public func jobSkipped(job: Job) {
    if showJobLifecycle {
      diagnosticEngine.emit(.remark_job_lifecycle("Skipped", job))
    }
    switch mode {
    case .regular, .verbose:
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
      stderrStream <<< json.count <<< "\n"
      stderrStream <<< String(data: json, encoding: .utf8)! <<< "\n"
      stderrStream.flush()
    }
  }
}

fileprivate extension Diagnostic.Message {
  static func remark_job_lifecycle(_ what: String, _ job: Job
  ) -> Diagnostic.Message {
    .remark("\(what) \(job.descriptionForLifecycle)")
  }
}
