//===--------------- OptionTable.swift - Swift Option Table ---------------===//
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
public struct OptionTable {
  public init() { }

  /// Retrieve the options.
  public var options: [Option] = Option.allOptions + Option.extraOptions
  public lazy var groupMap: [Option.Group: [Option]] = {
    var map = [Option.Group: [Option]]()
    for opt in options {
      guard let group = opt.group else { continue }
      map[group, default: []].append(opt)
    }
    return map
  }()
}

extension OptionTable {
  /// Print help information to the terminal.
  public func printHelp(driverKind: DriverKind, includeHidden: Bool) {
    print("""
      OVERVIEW: \(driverKind.title)

      USAGE: \(driverKind.usage)

      OPTIONS:
      """)

    for option in options {
      if option.isAlias { continue }
      if option.isHelpHidden && !includeHidden { continue }
      guard option.isAccepted(by: driverKind) else { continue }
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
    if let seeAlsoMessage = driverKind.seeAlsoHelpMessage {
      print("\n\(seeAlsoMessage)")
    }
  }
}
