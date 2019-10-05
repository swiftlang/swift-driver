import TSCBasic

/// Abstraction for functionality that allows working with subprocesses.
public protocol ProcessProtocol {
  /// Launch a subprocess.
  static func launchProcess(
    arguments: [String],
    environment: [String: String]
  ) throws -> ProcessProtocol

  /// The PID of the process.
  ///
  /// Clients that don't really launch a process can return
  /// a negative number to represent a "quasi-pid".
  ///
  /// - SeeAlso: https://github.com/apple/swift/blob/master/docs/DriverParseableOutput.rst#quasi-pids
  var processID: Process.ProcessID { get }

  /// Wait for the process to finish execution.
  @discardableResult
  func waitUntilExit() throws -> ProcessResult
}

extension Process: ProcessProtocol {
  public static func launchProcess(
    arguments: [String], environment: [String : String]
  ) throws -> ProcessProtocol {
    let process = Process(arguments: arguments, environment: environment)
    try process.launch()
    return process
  }
}
