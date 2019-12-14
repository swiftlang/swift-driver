//===--------------- OptionParsing.swift - Swift Option Parser ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
public enum OptionParseError : Error, Equatable {
  case unknownOption(index: Int, argument: String)
  case missingArgument(index: Int, argument: String)
}

extension OptionTable {
  /// Parse the given command-line arguments into a set of options.
  ///
  /// Throws an error if the command line contains any errors.
  public func parse(_ arguments: [String],
                    forInteractiveMode isInteractiveMode: Bool = false) throws -> ParsedOptions {
    var trie = PrefixTrie<String.UTF8View, Option>()
    for opt in options {
      trie[opt.spelling.utf8] = opt
    }

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

        // In interactive mode, synthesize a "--" argument for all args after the first input.
        if isInteractiveMode && index < arguments.endIndex {
          parsedOptions.addOption(.DASHDASH, argument: .multiple(Array(arguments[index...])))
          break
        }

        continue
      }

      // Match to an option, identified by key. Note that this is a prefix
      // match -- if the option is a `.flag`, we'll explicitly check to see if
      // there's an unmatched suffix at the end, and pop an error. Otherwise,
      // we'll treat the unmatched suffix as the argument to the option.
      guard let option = trie[argument.utf8] else {
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
    parsedOptions.buildIndex()
    return parsedOptions
  }
}
