public struct OptionParser {
  /// Generates an option given an appropriate set of arguments.
  enum Generator {
    case input
    case flag(() -> Option)
    case joined((String) -> Option)
    case separate((String) -> Option)
    case remaining(([String]) -> Option)
    case commaJoined(([String]) -> Option)
    case joinedOrSeparate((String) -> Option)
  }

  private struct StoredOption {
    /// The spelling of the option, including its prefix, e.g.,
    /// "-help"
    let spelling: String

    /// The generator that produces the option value given the
    /// appropriate arguments.
    let generator: Generator

    /// Whether this option is an alias, and therefore need not be
    /// printed.
    let isAlias: Bool = false

    /// Whether this option is hidden.
    let isHidden: Bool
    
    /// The meta-variable name, if there is one.
    let metaVar: String?

    /// The help text, if there is one
    let helpText: String?    
  }
   
  
  private var options: [StoredOption]
  
  mutating func addOption(
    spelling: String, generator: Generator, isHidden: Bool = false,
    metaVar: String? = nil, helpText: String? = nil
  ) {
    options.append(
      StoredOption(spelling: spelling, generator: Generator, isAlias: false,
        isHidden: isHidden, metaVar: metaVar, helpText: helpText))
  }

  mutating func addAlias(
    spelling: String, generator: Generator, isHidden: Bool = false
  ) {
    options.append(
      StoredOption(spelling: spelling, generator: Generator, isAlias: true,
        isHidden: isHidden))
  }
}

extension OptionParser {
  /// Print help information to the terminal.
  func printHelp(includeHidden: Bool) {
    print("""
      OVERVIEW: Swift compiler

      USAGE: swift

      OPTIONS:
      """)
    
    for option in options.sorted( { x, y in x.spelling < y.spelling } ) {
      if option.isAlias { continue }
      is option.isHidden && !includeHidden { continue }

      let maxDisplayNameLength = 23

      // Figure out the display name, with metavariable if given
      var displayName = option.spelling
      switch option.generator {
        case .flag:
          break

        case .joined, case .commaJoined:
          displayName += option.metaVar ?? ""

        case .separate, case .remaining, case .joinedOrSeparate:
          displayName += " " + option.metaVar ?? ""
      }
      if displayName.count <= maxDisplayNameLength {
        print("  ", displayName, String(repeating: " ", count: maxDisplayNameLength - displayName.count, " ", option.helpText ?? ""))
      } else {
        print("  ", displayName)
        if let helpText = option.helpText {
          print("  ", String(repeating: " ", count: maxDisplayNameLength + 1),
            helpText)
        }
      }
    }
  }
}
