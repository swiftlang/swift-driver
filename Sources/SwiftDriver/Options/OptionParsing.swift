public enum OptionParseError : Error {
  case unknownOption(index: Int, argument: String)
  case missingArgument(index: Int, argument: String)
}

extension OptionTable {
  private func matchOption(_ argument: String) -> Option? {
    var bestOption: Option? = nil

    // FIXME: Use a binary search or trie or similar.
    for option in options {
      // If there isn't a prefix match, keep going.
      if !argument.starts(with: option.spelling) { continue }

      // If this is the first option we've seen, or if it's a longer
      // match than the best option so far, then we have a new best
      // option.
      if let bestOption = bestOption,
        bestOption.spelling.count >= option.spelling.count {
        continue
      }

      bestOption = option
    }

    return bestOption
  }

  /// Parse the given command-line arguments into a set of options.
  ///
  /// Throws an error if the command line contains any errors.
  public func parse(_ arguments: [String]) throws -> ParsedOptions {
    var parsedOptions = ParsedOptions()
    var index = arguments.startIndex
    while index < arguments.endIndex {
      // Capture the next argument.
      let argument = arguments[index]
      index += 1

      // Ignore empty arguments.
      if argument.isEmpty {
        continue
      }

      // If this is not a flag, record it as an input.
      if argument == "-" || argument.first! != "-" {
        parsedOptions.addInput(argument)
        continue
      }

      // Match to an option, identified by key.
      guard let option = matchOption(argument) else {
        throw OptionParseError.unknownOption(
          index: index - 1, argument: argument)
      }

      // Translate the argument
      switch option.kind {
      case .input:
        parsedOptions.addOption(option, argument: .single(argument))

      case .commaJoined:
        // Comma-separated list of arguments follows the option spelling.
        let rest = argument.dropFirst(option.spelling.count)
        parsedOptions.addOption(
          option,
          argument: .multiple(rest.split(separator: ",").map { String($0) }))

      case .flag:
        // Make sure there was no extra text.
        if argument != option.spelling {
          throw OptionParseError.unknownOption(
            index: index - 1, argument: argument)
        }
        parsedOptions.addOption(option, argument: .none)

      case .joined:
        // Argument text follows the option spelling.
        parsedOptions.addOption(
          option,
          argument: .single(String(argument.dropFirst(option.spelling.count))))

      case .joinedOrSeparate:
        // Argument text follows the option spelling.
        let arg = argument.dropFirst(option.spelling.count)
        if !arg.isEmpty {
          parsedOptions.addOption(option, argument: .single(String(arg)))
          break
        }

        if index == arguments.endIndex {
          throw OptionParseError.missingArgument(
            index: index - 1, argument: argument)
        }

        parsedOptions.addOption(option, argument: .single(arguments[index]))
        index += 1

      case .remaining:
        parsedOptions.addOption(
          option,
          argument: .multiple(arguments[index...].map { String($0) }))
        index = arguments.endIndex

      case .separate:
        if index == arguments.endIndex {
          throw OptionParseError.missingArgument(
            index: index - 1, argument: argument)
        }

        parsedOptions.addOption(option, argument: .single(arguments[index]))
        index += 1
      }
    }

    return parsedOptions
  }
}
