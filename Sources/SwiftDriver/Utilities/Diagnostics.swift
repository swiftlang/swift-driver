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

  public static var error_mode_cannot_emit_module: Diagnostic.Message {
    .error("this mode does not support emitting modules")
  }

  public static func error_bad_module_name(
    moduleName: String,
    explicitModuleName: Bool
  ) -> Diagnostic.Message {
    let suffix: String
    if explicitModuleName {
      suffix = ""
    } else {
      suffix = "; use -module-name flag to specify an alternate name"
    }

    return .error("module name \"\(moduleName)\" is not a valid identifier\(suffix)")
  }

  public static func error_stdlib_module_name(
    moduleName: String,
    explicitModuleName: Bool
  ) -> Diagnostic.Message {
    let suffix: String
    if explicitModuleName {
      suffix = ""
    } else {
      suffix = "; use -module-name flag to specify an alternate name"
    }

    return .error("module name \"\(moduleName)\" is reserved for the standard library\(suffix)")
  }

  public static func warning_no_such_sdk(_ path: String) -> Diagnostic.Message {
    .warning("no such SDK: \(path)")
  }
}
