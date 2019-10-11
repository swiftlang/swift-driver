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

/// Delegate for printing execution information on the command-line.
public struct ToolExecutionDelegate: JobExecutorDelegate {
  public enum Mode {
    case verbose
    case parsableOutput
    case regular
  }

  public let mode: Mode

  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    switch mode {
    case .regular:
      break
    case .verbose:
      stdoutStream <<< arguments.map { $0.spm_shellEscaped() }.joined(separator: " ") <<< "\n"
      stdoutStream.flush()
    case .parsableOutput:

      // Compute the outputs for the message.
      let outputs: [BeganMessage.Output] = job.outputs.map {
        .init(path: $0.file.name, type: $0.type.rawValue)
      }

      let beganMessage = BeganMessage(
        pid: pid,
        inputs: job.displayInputs.map{ $0.file.name },
        outputs: outputs,
        commandExecutable: arguments[0],
        commandArguments: arguments[1...].map{ String($0) }
      )

      let message = ParsableMessage.beganMessage(name: job.kind.rawValue, msg: beganMessage)
      emit(message)
    }
  }

  public func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    switch mode {
    case .regular, .verbose:
      let output = (try? result.utf8Output() + result.utf8stderrOutput()) ?? ""
      if !output.isEmpty {
        stderrStream <<< output
        stderrStream.flush()
      }

    case .parsableOutput:
      switch result.exitStatus {
      case .terminated(let code):
        let output = (try? result.utf8Output() + result.utf8stderrOutput()) ?? ""
        let finishedMessage = FinishedMessage(exitStatus: Int(code), pid: pid, output: output.isEmpty ? nil : output)
        let message = ParsableMessage.finishedMessage(name: job.kind.rawValue, msg: finishedMessage)
        emit(message)

      case .signalled:
        // FIXME: Implement this.
        break
      }

    }
  }

  private func emit(_ message: ParsableMessage) {
    // FIXME: Do we need to do error handling here? Can this even fail?
    guard let json = try? message.toJSON() else { return }

    stdoutStream <<< json.count <<< "\n"
    stdoutStream <<< String(data: json, encoding: .utf8)! <<< "\n"
    stdoutStream.flush()
  }
}
