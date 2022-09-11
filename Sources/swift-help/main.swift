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
import ArgumentParser

import enum TSCBasic.ProcessEnv
import func TSCBasic.exec
import class TSCBasic.Process
import var TSCBasic.localFileSystem

enum HelpTopic: ExpressibleByArgument, CustomStringConvertible {
  case driver(DriverKind)
  case subcommand(Subcommand)
  case intro

  init?(argument topicName: String) {
    if let kind = DriverKind(rawValue: topicName) {
      self = .driver(kind)
    } else if let subcommand = Subcommand(rawValue: topicName) {
      self = .subcommand(subcommand)
    } else if topicName == "intro" {
      self = .intro
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
    case .intro:
      return "intro"
    }
  }
}

enum Subcommand: String, CaseIterable {
  case build, package, run, test

  var description: String {
    switch self {
    case .build:
      return "Build Swift packages"
    case .package:
      return "Create and work on packages"
    case .run:
      return "Run a program from a package"
    case .test:
      return "Run package tests"
    }
  }
}

struct SwiftHelp: ParsableCommand {
  @Argument(help: "The topic to display help for.")
  var topic: HelpTopic = .driver(.interactive)

  @Argument(help: "The help subtopics, if applicable.")
  var subtopics: [String] = []

  @Flag(name: .customLong("show-hidden", withSingleDash: true),
        help: "List hidden (unsupported) options")
  var showHidden: Bool = false

  enum Color256: CustomStringConvertible {
    case reset
    case color(foreground: UInt8?, background: UInt8?)

    var description: String {
      switch self {
      case .reset:
        return "\u{001B}[0m"
      case let .color(foreground, background):
        let foreground = foreground.map { "\u{001B}[38;5;\($0)m" } ?? ""
        let background = background.map { "\u{001B}[48;5;\($0)m" } ?? ""
        return foreground + background
      }
    }
  }

  func printIntro() {
    let is256Color = ProcessEnv.vars["TERM"] == "xterm-256color"
    let orangeRed = is256Color ? "\u{001b}[1;38;5;196m" : ""
    let plain = is256Color ? "\u{001b}[0m" : ""
    let plainBold = is256Color ? "\u{001b}[1m" : ""

    print("""

    \(orangeRed)Welcome to Swift!\(plain)

    \(plainBold)Subcommands:\(plain)

    """)

    let maxSubcommandNameLength = Subcommand.allCases.map { $0.rawValue.count }.max()!

    for command in Subcommand.allCases {
      let padding = String(repeating: " ", count: maxSubcommandNameLength - command.rawValue.count)
      print("  \(plainBold)swift \(command.rawValue)\(plain)\(padding)    \(command.description)")
    }

    // `repl` not included in `Subcommand`, also print it here.
    do {
      let padding = String(repeating: " ", count: maxSubcommandNameLength - "repl".count)
      print("  \(plainBold)swift repl\(plain)\(padding)    Experiment with Swift code interactively")
    }

    print("\n  Use \(plainBold)`swift --help`\(plain) for descriptions of available options and flags.")
    print("\n  Use \(plainBold)`swift help <subcommand>`\(plain) for more information about a subcommand.")
    print()
  }

  func run() throws {
    let driverOptionTable = OptionTable()
    switch topic {
    case .driver(let kind):
      driverOptionTable.printHelp(driverKind: kind, includeHidden: showHidden)
      if kind == .interactive {
        printIntro()
      }
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
      if subtopics.isEmpty {
        try exec(path: path.pathString, args: [execName, "--help"])
      } else {
        try exec(path: path.pathString, args: [execName, "help"] + subtopics)
      }
    case .intro:
      printIntro()
    }
  }
}

// SwiftPM executables don't support @main.
SwiftHelp.main()
