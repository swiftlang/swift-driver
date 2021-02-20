//===--------------- main.swift - Swift Help Main Entrypoint --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import SwiftOptions
import TSCBasic
import ArgumentParser

enum HelpTopic: ExpressibleByArgument, CustomStringConvertible {
  case driver(DriverKind)
  case subcommand(Subcommand)

  init?(argument topicName: String) {
    if let kind = DriverKind(rawValue: topicName) {
      self = .driver(kind)
    } else if let subcommand = Subcommand(rawValue: topicName) {
      self = .subcommand(subcommand)
    } else {
      return nil
    }
  }

  var description: String {
    switch self {
    case .driver(let kind):
      return kind.rawValue
    case .subcommand(let command):
      return command.rawValue
    }
  }
}

enum Subcommand: String, CaseIterable {
  case build, package, run, test

  var description: String {
    switch self {
    case .build:
      return "SwiftPM - Build sources into binary products"
    case .package:
      return "SwiftPM - Perform operations on Swift packages"
    case .run:
      return "SwiftPM - Build and run an executable product"
    case .test:
      return "SwiftPM - Build and run tests"
    }
  }
}

struct SwiftHelp: ParsableCommand {
  @Argument var topic: HelpTopic = .driver(.interactive)

  @Flag(name: .customLong("show-hidden", withSingleDash: true),
        help: "List hidden (unsupported) options")
  var showHidden: Bool = false

  func run() throws {
    let driverOptionTable = OptionTable()
    switch topic {
    case .driver(let kind):
      driverOptionTable.printHelp(driverKind: kind, includeHidden: showHidden)
      print("\nSUBCOMMANDS (swift <subcommand> [arguments]):")
      let maxSubcommandNameLength = Subcommand.allCases.map(\.rawValue.count).max()!
      for subcommand in Subcommand.allCases {
        let padding = String(repeating: " ", count: maxSubcommandNameLength - subcommand.rawValue.count)
        print("  \(subcommand.rawValue):\(padding) \(subcommand.description)")
      }
      print("\n  Use \"swift help <subcommand>\" for more information about a subcommand")

    case .subcommand(let subcommand):
      // Try to find the subcommand adjacent to the help tool.
      // If we didn't find the tool there, let the OS search for it.
      let execName = "swift-\(subcommand)"
      let subcommandPath = Process.findExecutable(
        CommandLine.arguments[0])?
        .parentDirectory
        .appending(component: execName)
        ?? Process.findExecutable(execName)

      guard let path = subcommandPath, localFileSystem.isExecutableFile(subcommandPath!) else {
        fatalError("cannot find subcommand executable '\(execName)'")
      }

      // Execute the subcommand with --help.
      try exec(path: path.pathString, args: [execName, "--help"])
    }
  }
}

// SwiftPM executables don't support @main.
SwiftHelp.main()
