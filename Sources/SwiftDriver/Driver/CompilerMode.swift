/// The mode of the compiler.
public enum CompilerMode: Equatable {
  /// A standard compilation, using multiple frontend invocations and -primary-file.
  case standardCompile

  /// A batch compilation, using multiple frontend invocations with
  /// multiple -primary-file options per invocation.
  case batchCompile(BatchModeInfo)

  /// A compilation using a single frontend invocation without -primary-file.
  case singleCompile

  /// Invoke the REPL.
  case repl

  /// Compile and execute the inputs immediately.
  case immediate
}

/// Information about batch mode, which is used to determine how to form
/// the batches of jobs.
public struct BatchModeInfo: Equatable {
  let seed: Int
  let count: Int?
  let sizeLimit: Int?
}

extension CompilerMode {
  /// Whether this compilation mode uses -primary-file to specify its inputs.
  public var usesPrimaryFileInputs: Bool {
    switch self {
    case .immediate, .repl, .singleCompile:
      return false

    case .standardCompile, .batchCompile:
      return true
    }
  }
}

extension CompilerMode: CustomStringConvertible {
    public var description: String {
        switch self {

        case .standardCompile:
            return "standard compilation"
        case .batchCompile:
            return "batch compilation"
        case .singleCompile:
            return "whole module optimization"
        case .repl:
            return "read-eval-print-loop compilation"
        case .immediate:
            return "immediate compilation"
        }
  }
}
