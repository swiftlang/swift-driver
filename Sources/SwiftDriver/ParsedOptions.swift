/// Describes a single parsed option with its argument (if any).
public struct ParsedOption {
  public enum Argument {
    case none
    case single(String)
    case multiple([String])

    /// Retrieve the single-string argument.
    var asSingle: String {
      switch self {
      case .single(let result):
        return result

      default:
        assert(false, "not a singular argument")
      }
    }

    /// Retrieve multiple string arguments.
    var asMultiple: [String] {
      switch self {
      case .multiple(let result):
        return result

      default:
        assert(false, "not a multiple argument")
      }
    }
  }

  /// The option that was parsed, which may be nil to indicate that this is
  /// an input (that isn't associated with an option).
  public let option: Option?

  /// The argument bound to this option.
  public let argument: Argument

  /// Whether this is an input.
  public var isInput: Bool { option == nil }
}

extension ParsedOption: CustomStringConvertible {
  public var description: String {
    guard let option = option else {
      return argument.asSingle
    }

    switch option.kind {
    case .commaJoined:
      // FIXME: Escape spaces.
      return option.spelling + argument.asMultiple.joined(separator: ",")

    case .flag:
      return option.spelling

    case .joined:
      // FIXME: Escape spaces.
      return option.spelling + argument.asSingle

    case .joinedOrSeparate, .separate:
      // FIXME: Escape spaces.
      return option.spelling + " " + argument.asSingle

    case .remaining:
      let args = argument.asMultiple
      if args.isEmpty {
        return option.spelling
      }

      // FIXME: Escape spaces.
      return option.spelling + " " + argument.asMultiple.joined(separator: " ")
    }
  }
}

/// Capture a list of command-line arguments that have been parsed
/// into a list of options with their arguments.
public struct ParsedOptions {
  public typealias Argument = ParsedOption.Argument

  private var parsedOptions: [ParsedOption] = []
}

extension ParsedOptions {
  mutating func addOption(_ option: Option, argument: Argument) {
    parsedOptions.append(.init(option: option, argument: argument))
  }

  mutating func addInput(_ input: String) {
    parsedOptions.append(.init(option: nil, argument: .single(input)));
  }
}

extension ParsedOptions: CustomStringConvertible {
  /// Pretty-printed version of all of the parsed options.
  public var description: String {
    // FIXME: Escape spaces?
    return parsedOptions.map { $0.description }.joined(separator: " ")
  }
}

extension ParsedOptions {
  /// Produce "raw" command-line arguments from the parsed options.
  public var commandLine: [String] {
    var result: [String] = []
    for parsed in parsedOptions {
      guard let option = parsed.option else {
        result.append(parsed.argument.asSingle)
        continue
      }

      switch option.kind {
      case .commaJoined:
        result.append(option.spelling + parsed.argument.asMultiple.joined(separator: ","))

      case .flag:
        result.append(option.spelling)

      case .joined:
        result.append(option.spelling + parsed.argument.asSingle)

      case .joinedOrSeparate, .separate:
        result.append(option.spelling)
        result.append(parsed.argument.asSingle)

      case .remaining:
        result.append(option.spelling)
        result.append(contentsOf: parsed.argument.asMultiple)
      }
    }
    return result
  }
}

/// Access to the various options that have been parsed.
extension ParsedOptions {
  /// Does this contain a particular option.
  public func contains(_ option: Option) -> Bool {
    return parsedOptions.contains { $0.option == option }
  }

  /// Does this contain any inputs?
  public var hasAnyInput: Bool {
    return parsedOptions.contains { $0.isInput }
  }

  /// Walk through all of the parsed options, modifying each one.
  public mutating func forEachModifying(body: (inout ParsedOption) throws -> Void) rethrows {
    for index in parsedOptions.indices {
      try body(&parsedOptions[index])
    }
  }

  /// Find all of the inputs.
  public var allInputs: [String] {
    parsedOptions.filter { $0.option == nil }.map { $0.argument.asSingle }
  }

  /// Get the last argument matching the given option.
  public func getLastArgument(_ option: Option) -> Argument? {
    return parsedOptions.last { parsed in parsed.option == option }?.argument
  }
}
