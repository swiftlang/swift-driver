/// The mode of the compiler.
public enum CompilerMode {
  /// A standard compilation, using multiple frontend invocations and -primary-file.
  case standardCompile

  /// A compilation using a single frontend invocation without -primary-file.
  case singleCompile

  /// Invoke the REPL.
  case repl

  /// Compile and execute the inputs immediately.
  case immediate
}

extension CompilerMode {
  /// Whether this compilation mode uses -primary-file to specify its inputs.
  public var usesPrimaryFileInputs: Bool {
    switch self {
    case .immediate, .repl, .singleCompile:
      return false

    case .standardCompile:
      return true
    }
  }
}
