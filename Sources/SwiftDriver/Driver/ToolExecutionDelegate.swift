import TSCBasic

/// Delegate for printing execution information on the command-line.
struct ToolExecutionDelegate: JobExecutorDelegate {
  enum Mode {
    case verbose
    case parsableOutput
    case regular
  }

  let mode: Mode

  func jobStarted(job: Job, arguments: [String], pid: Int) {
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

  func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    switch mode {
    case .regular, .verbose:
      break
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
