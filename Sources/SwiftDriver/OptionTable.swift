public struct OptionTable {
  /// Generates an option given an appropriate set of arguments.
  public enum Generator {
    case input
    case flag(() -> Option)
    case joined((String) -> Option)
    case separate((String) -> Option)
    case remaining(([String]) -> Option)
    case commaJoined(([String]) -> Option)
    case joinedOrSeparate((String) -> Option)

    var isInput: Bool {
      switch self {
      case .input:
        return true
      default:
        return false
      }
    }
  }

  struct StoredOption {
    /// The spelling of the option, including its prefix, e.g.,
    /// "-help"
    let spelling: String

    /// The generator that produces the option value given the
    /// appropriate arguments.
    let generator: Generator

    /// Whether this option is an alias, and therefore need not be
    /// printed.
    let isAlias: Bool

    /// Whether this option is hidden.
    let isHidden: Bool
    
    /// The meta-variable name, if there is one.
    let metaVar: String?

    /// The help text, if there is one
    let helpText: String?    
  }

  var inputOption: StoredOption? = nil
  var options: [StoredOption] = []

  public init() { }
}

extension OptionTable {
  public mutating func addOption(
    spelling: String, generator: Generator, isHidden: Bool = false,
    metaVar: String? = nil, helpText: String? = nil
  ) {
    let option = StoredOption(spelling: spelling, generator: generator,
                              isAlias: false, isHidden: isHidden,
                              metaVar: metaVar, helpText: helpText)

    // Allow at most one input option, which won't be entered in the table.
    if generator.isInput {
      assert(inputOption == nil)
      inputOption = option
    } else {
      options.append(option)
    }
  }

  public mutating func addAlias(
    spelling: String, generator: Generator, isHidden: Bool = false
  ) {
    assert(!generator.isInput)
    options.append(
      StoredOption(spelling: spelling, generator: generator, isAlias: true,
        isHidden: isHidden, metaVar: nil, helpText: nil))
  }
}

extension String {
  fileprivate func canonicalizedForArgName() -> String {
    var result = self
    while result.first != nil && result.first! == "-" {
      result = String(result.dropFirst())
    }
    return result.lowercased()
  }
}

extension OptionTable {
  /// Print help information to the terminal.
  public func printHelp(usage: String, title: String, includeHidden: Bool) {
    print("""
      OVERVIEW: \(title)

      USAGE: \(usage)

      OPTIONS:
      """)

    for option in options {
      if option.isAlias { continue }
      if option.isHidden && !includeHidden { continue }
      if option.helpText == nil { continue }
      
      let maxDisplayNameLength = 23

      // Figure out the display name, with metavariable if given
      var displayName = option.spelling
      switch option.generator {
        case .input:
          continue
        
        case .flag:
          break

        case .joined, .commaJoined:
          displayName += option.metaVar ?? "<value>"

        case .separate, .remaining, .joinedOrSeparate:
          displayName += " " + (option.metaVar ?? "<value>")
      }
      if displayName.count <= maxDisplayNameLength {
        let rightPadding = String(
          repeating: " ",
          count: maxDisplayNameLength - displayName.count)
        
        print("  \(displayName)\(rightPadding) \(option.helpText!)")
      } else {
        print("  \(displayName)")
        let leftPadding = String(
          repeating: " ", count: maxDisplayNameLength)
        print("  \(leftPadding) \(option.helpText!)")
      }
    }
  }
}

extension OptionTable {
  public init(driverKind: DriverKind) {
    switch driverKind {
    case .autolinkExtract:
      self = OptionTable.autolinkExtractOptions

    case .batch:
      self = OptionTable.batchOptions

    case .frontend:
      self = OptionTable.frontendOptions

    case .indent:
      self = OptionTable.indentOptions

    case .interactive:
      self = OptionTable.interactiveOptions

    case .moduleWrap:
      self = OptionTable.moduleWrapOptions
    }
  }
}
