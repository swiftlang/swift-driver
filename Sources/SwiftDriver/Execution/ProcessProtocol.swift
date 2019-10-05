import TSCBasic

/// Abstraction for functionality that allows working with subprocesses.
public protocol ProcessProtocol {
  /// Initialize a new process.
  init(arguments: [String], environment: [String: String])

  /// Launch the process.
  ///
  /// The process should have a valid PID if the launch is successful. This
  /// doesn't wait for the process to finish. It is illegal to call this method
  /// multiple times.
  func launch() throws

  /// Wait for the process to finish execution.
  @discardableResult
  func waitUntilExit() throws -> ProcessResult

  /// The process ID of the process.
  ///
  /// This will be populated once the process has launched.
  var processID: Process.ProcessID { get }
}

extension Process: ProcessProtocol {
  public convenience init(arguments: [String], environment: [String : String]) {
    self.init(
      arguments: arguments,
      environment: environment,
      outputRedirection: .collect,
      verbose: false,
      startNewProcessGroup: true
    )
  }
}
