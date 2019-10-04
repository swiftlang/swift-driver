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

      let beganMessage = BeganMessage(
        pid: pid,
        // FIXME: This needs to be the primary inputs :/
        inputs: job.inputs.map{ $0.name },
        outputs: job.outputs.map{ .init(path: $0.name, type: "object") },
        commandExecutable: arguments[0],
        commandArguments: arguments[1...].map{ String($0) }
      )

      let message = ParsableMessage.beganMessage(name: job.kind.rawValue, msg: beganMessage)
      emit(message)
    }
  }

  func jobHadOutput(job: Job, output: String) {
    // FIXME: Merge with job finished delegate.
    // FIXME: Need to see how current driver handles stdout/stderr.
    stdoutStream <<< output
    stdoutStream.flush()
  }

  func jobFinished(job: Job, success: Bool, pid: Int) {
    switch mode {
    case .regular, .verbose:
      break
    case .parsableOutput:
      // FIXME: Get the actual exit status.
      let finishedMessage = FinishedMessage(exitStatus: success ? 0 : 1, pid: pid, output: nil)
      let message = ParsableMessage.finishedMessage(name: job.kind.rawValue, msg: finishedMessage)
      emit(message)
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
