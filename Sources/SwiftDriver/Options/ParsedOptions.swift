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

  /// The option that was parsed.
  public let option: Option

  /// The argument bound to this option.
  public let argument: Argument
}

extension ParsedOption: CustomStringConvertible {
  public var description: String {
    switch option.kind {
    case .input:
      return argument.asSingle

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

  /// The parsed options, which match up an option with its argument(s).
  private var parsedOptions: [ParsedOption] = []

  /// Indication of which of the parsed options have been "consumed" by the
  /// driver. Any unconsumed options could have been omitted from the command
  /// line.
  private var consumed: [Bool] = []
}

extension ParsedOptions {
  mutating func addOption(_ option: Option, argument: Argument) {
    parsedOptions.append(.init(option: option, argument: argument))
    consumed.append(false)
  }

  mutating func addInput(_ input: String) {
    addOption(.INPUT, argument: .single(input))
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
      switch parsed.option.kind {
      case .input:
        result.append(parsed.argument.asSingle)

      case .commaJoined:
        result.append(parsed.option.spelling + parsed.argument.asMultiple.joined(separator: ","))

      case .flag:
        result.append(parsed.option.spelling)

      case .joined:
        result.append(parsed.option.spelling + parsed.argument.asSingle)

      case .joinedOrSeparate, .separate:
        result.append(parsed.option.spelling)
        result.append(parsed.argument.asSingle)

      case .remaining:
        result.append(parsed.option.spelling)
        result.append(contentsOf: parsed.argument.asMultiple)
      }
    }
    return result
  }
}

/// Access to the various options that have been parsed.
extension ParsedOptions {
  /// Return all options that match the given predicate.
  ///
  /// Any options that match the \c isIncluded predicate will be marked "consumed".
  public mutating func filter(where isIncluded: (ParsedOption) throws -> Bool) rethrows -> [ParsedOption] {
    var result: [ParsedOption] = []
    for index in parsedOptions.indices {
      if try isIncluded(parsedOptions[index]) {
        consumed[index] = true
        result.append(parsedOptions[index])
      }
    }

    return result
  }

  /// Return the last parsed options that matches the given predicate.
  ///
  /// Any options that match the \c isIncluded predicate will be marked "consumed".
  public mutating func last(where isIncluded: (ParsedOption) throws -> Bool) rethrows -> ParsedOption? {
    return try filter(where: isIncluded).last
  }

  /// Does this contain a particular option.
  public mutating func contains(_ option: Option) -> Bool {
    assert(option.alias == nil, "Don't check for aliased options")
    return last { parsed in parsed.option.canonical == option } != nil
  }

  /// Determine whether the parsed options contains an option in the given
  /// group.
  public mutating func contains(in group: Option.Group) -> Bool {
    return getLast(in: group) != nil
  }

  /// Does this contain any inputs?
  ///
  /// This operation does not consume any inputs.
  public var hasAnyInput: Bool {
    return parsedOptions.contains { $0.option == .INPUT }
  }

  /// Walk through all of the parsed options, modifying each one.
  ///
  /// This operation does not consume any options.
  public mutating func forEachModifying(body: (inout ParsedOption) throws -> Void) rethrows {
    for index in parsedOptions.indices {
      try body(&parsedOptions[index])
    }
  }

  /// Find all of the inputs.
  public var allInputs: [String] {
    mutating get {
      filter { $0.option == .INPUT }.map { $0.argument.asSingle }
    }
  }

  /// Determine whether the parsed options contain an argument with one of
  /// the given options
  public mutating func hasArgument(_ options: Option...) -> Bool {
    return last { parsed in
      return options.contains(parsed.option)
    } != nil
  }

  /// Get the last argument matching the given option.
  public mutating func getLastArgument(_ option: Option) -> Argument? {
    assert(option.alias == nil, "Don't check for aliased options")
    return last { parsed in parsed.option.canonical == option }?.argument
  }

  /// Get the last parsed option within the given option group.
  public mutating func getLast(in group: Option.Group) -> ParsedOption? {
    return last { parsed in parsed.option.group == group }
  }
}
