import TSCBasic

public typealias Diagnostic = TSCBasic.Diagnostic

extension Diagnostic.Message {
  public static var error_static_emit_executable_disallowed: Diagnostic.Message {
    .error("-static may not be used with -emit-executable")
  }

  public static func error_option_missing_required_argument(option: Option, requiredArg: Option) -> Diagnostic.Message {
    .error("option '\(option.spelling)' is missing a required argument (\(requiredArg.spelling))")
  }

  public static func error_invalid_arg_value(arg: Option, value: String) -> Diagnostic.Message {
    .error("invalid value '\(value)' in '\(arg.spelling)'")
  }

  public static func error_argument_not_allowed_with(arg: String, other: String) -> Diagnostic.Message {
    .error("argument '\(arg)' is not allowed with '\(other)'")
  }
}
