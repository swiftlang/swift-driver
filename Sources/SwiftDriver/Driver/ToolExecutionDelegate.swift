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
import MSVCRT
import WinSDK
#elseif canImport(Glibc)
import Glibc
#else
#error("Missing libc or equivalent")
#endif

/// Delegate for printing execution information on the command-line.
public struct ToolExecutionDelegate: JobExecutionDelegate {
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
    switch mode {
    case .regular, .verbose:
      let output = (try? result.utf8Output() + result.utf8stderrOutput()) ?? ""
      if !output.isEmpty {
        stderrStream <<< output
        stderrStream.flush()
      }

    case .parsableOutput:
      let output = (try? result.utf8Output() + result.utf8stderrOutput()).flatMap { $0.isEmpty ? nil : $0 }
      let message: ParsableMessage

      switch result.exitStatus {
      case .terminated(let code):
        let finishedMessage = FinishedMessage(exitStatus: Int(code), pid: pid, output: output)
        message = ParsableMessage(name: job.kind.rawValue, kind: .finished(finishedMessage))

      case .signalled(let signal):
        let errorMessage = strsignal(signal).map { String(cString: $0) } ?? ""
        let signalledMessage = SignalledMessage(pid: pid, output: output, errorMessage: errorMessage, signal: Int(signal))
        message = ParsableMessage(name: job.kind.rawValue, kind: .signalled(signalledMessage))
      }
      emit(message)
    }
  }

  private func emit(_ message: ParsableMessage) {
    // FIXME: Do we need to do error handling here? Can this even fail?
    guard let json = try? message.toJSON() else { return }

    stderrStream <<< json.count <<< "\n"
    stderrStream <<< String(data: json, encoding: .utf8)! <<< "\n"
    stderrStream.flush()
  }
}
