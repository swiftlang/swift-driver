public struct OptionTable {
  public init() { }

  /// Retrieve the options.
  public var options: [Option] = Option.allOptions
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
      if option.isHelpHidden && !includeHidden { continue }
      guard let helpText = option.helpText else { continue }

      let maxDisplayNameLength = 23

      // Figure out the display name, with metavariable if given
      var displayName = option.spelling
      switch option.kind {
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
        
        print("  \(displayName)\(rightPadding) \(helpText)")
      } else {
        print("  \(displayName)")
        let leftPadding = String(
          repeating: " ", count: maxDisplayNameLength)
        print("  \(leftPadding) \(helpText)")
      }
    }
  }
}
