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

extension DriverKind: ExpressibleByArgument {}

struct SwiftHelp: ParsableCommand {
  @ArgumentParser.Option(name: .customLong("tool", withSingleDash: true),
                         default: .interactive,
                         help: "The tool to list options of")
  var tool: DriverKind

  @Flag(name: .customLong("show-hidden", withSingleDash: true),
        help: "List hidden (unsupported) options")
  var showHidden: Bool

  func run() throws {
    let driverOptionTable = OptionTable()
    driverOptionTable.printHelp(driverKind: tool, includeHidden: showHidden)
  }
}

SwiftHelp.main()
