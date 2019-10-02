import TSCBasic

/// Delegate for printing execution information on the command-line.
struct ToolExecutionDelegate: JobExecutorDelegate {

  /// True if execution should be verbose.
  let isVerbose: Bool

  func jobStarted(job: Job, arguments: [String]) {
    guard isVerbose else { return }

    // FIXME: Do we need to escape the arguments?
    stdoutStream <<< arguments.joined(separator: " ") <<< "\n"
    stdoutStream.flush()
  }

  func jobHadOutput(job: Job, output: String) {
    // FIXME: Need to see how current driver handles stdout/stderr.
    stdoutStream <<< output
    stdoutStream.flush()
  }

  func jobFinished(job: Job, success: Bool) {
  }
}
