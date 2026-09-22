//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
public struct OptionTable {
  public init() { }

  /// Retrieve the options.
  public var options: [Option] = Option.allOptions
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
      OVERVIEW: Swift compiler

      USAGE: \(driverKind.usage)

      """)

    let remainingOptions: [Option]
    // In non-interactive mode, output all possible uses of the driver
    if driverKind == DriverKind.batch {
      print("""
      MODES:
      """)
      let modeOptions = options.filter { $0.group == Option.Group.modes }
      remainingOptions = options.filter { $0.group != Option.Group.modes }
      OptionTable.printOptions(modeOptions, driverKind: driverKind, includeHidden: includeHidden)
      // A newline space before printing remaining options
      print("")
    } else {
      remainingOptions = options
    }

    print("""
    OPTIONS:
    """)
    let ungroupedOptions = remainingOptions.filter {
      $0.group == nil || (driverKind == DriverKind.interactive && $0.group == Option.Group.modes)
    }
    OptionTable.printOptions(ungroupedOptions, driverKind: driverKind, includeHidden: includeHidden)

    var printedGroups = Set<Option.Group>()
    for option in remainingOptions {
      guard let group = option.group,
            group != Option.Group.modes,
            printedGroups.insert(group).inserted else {
        continue
      }

      let groupOptions = remainingOptions.filter { $0.group == group }
      guard !OptionTable.visibleOptions(
        groupOptions,
        driverKind: driverKind,
        includeHidden: includeHidden
      ).isEmpty else {
        continue
      }

      print("\n\(group.helpText ?? group.name):")
      OptionTable.printOptions(groupOptions, driverKind: driverKind, includeHidden: includeHidden)
    }
  }

  private static func visibleOptions(
    _ options: [Option], driverKind: DriverKind, includeHidden: Bool
  ) -> [Option] {
    options.filter {
      !$0.isAlias &&
        (!$0.isHelpHidden || includeHidden) &&
        $0.isAccepted(by: driverKind) &&
        $0.kind != .input &&
        $0.helpText != nil
    }
  }

  static func printOptions(_ options: [Option], driverKind: DriverKind, includeHidden: Bool) {
    for option in visibleOptions(options, driverKind: driverKind, includeHidden: includeHidden) {
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

        case .separate, .remaining, .joinedOrSeparate, .multiArg:
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
