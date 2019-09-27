public enum OptionParseError : Error {
  case unknownOption(index: Int, argument: String)
  case missingArgument(index: Int, argument: String)
}

extension OptionTable {
  private func matchOption(_ argument: String) -> StoredOption? {
    // If this is not a flag, record it as an input.
    if argument.first! != "-" {
      return inputOption
    }

    var bestOption: StoredOption? = nil

    // FIXME: Use a binary search or trie or similar.
    for option in options {
      // If there isn't a prefix match, keep going.
      if !argument.starts(with: option.spelling) { continue }

      // If this is the first option we've seen, or if it's a longer
      // match than the best option so far, then we have a new best
      // option.
      if (bestOption == nil ||
          bestOption!.spelling.count < option.spelling.count) {
        bestOption = option
      }
    }

    return bestOption
  }

  /// Parse the given command-line arguments into a set of options.
  ///
  /// Throws an error if the command line contains any errors.
  public func parse(_ arguments: [String]) throws -> [Option] {
    var options: [Option] = []
    var index = arguments.startIndex
    while index < arguments.endIndex {
      // Capture the next argument.
      let argument = arguments[index]
      index += 1

      // Ignore empty arguments.
      if argument.isEmpty {
        continue
      }

      // Match to a stored option.
      guard let storedOption = matchOption(argument) else {
        throw OptionParseError.unknownOption(
          index: index - 1, argument: argument)
      }

      // Translate the argument into an option.
      switch storedOption.generator {
      case .commaJoined(let generator):
        // Comma-separated list of arguments follows the option spelling.
        let rest = argument.dropFirst(storedOption.spelling.count)
        let args = rest.split(separator: ",").map { String($0) }
        options.append(generator(args))

      case .flag(let generator):
        if argument != storedOption.spelling {
          throw OptionParseError.unknownOption(
            index: index - 1, argument: argument)
        }
        options.append(generator())

      case .input:
        options.append(Option.INPUT(argument))

      case .joined(let generator):
        // Argument text follows the option spelling.
        let arg = argument.dropFirst(storedOption.spelling.count)
        options.append(generator(String(arg)))

      case .joinedOrSeparate(let generator):
        // Argument text follows the option spelling.
        let arg = argument.dropFirst(storedOption.spelling.count)
        if !arg.isEmpty {
          options.append(generator(String(arg)))
          break
        }

        if index == arguments.endIndex {
          throw OptionParseError.missingArgument(
            index: index - 1, argument: argument)
        }

        options.append(generator(arguments[index]))
        index += 1

      case .remaining(let generator):
        let args = arguments[index...].map { String($0) }
        options.append(generator(args))
        index = arguments.endIndex

      case .separate(let generator):
        if index == arguments.endIndex {
          throw OptionParseError.missingArgument(
            index: index - 1, argument: argument)
        }

        options.append(generator(arguments[index]))
        index += 1
      }
    }

    return options
  }
}
