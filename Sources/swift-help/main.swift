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
import TSCLibc
import TSCUtility

extension DriverKind: StringEnumArgument {
  public static var completion: ShellCompletion { .none }
}

struct Options {
  var driverKind: DriverKind = .interactive
  var showHidden: Bool = false
}

let driverOptionTable = OptionTable()
let parser = ArgumentParser(commandName: "swift help",
                            usage: " ",
                            overview: "Swift help tool",
                            seeAlso: nil)
let binder = ArgumentBinder<Options>()
binder.bind(option: parser.add(option: "-show-hidden",
                               usage: "List hidden (unsupported) options"),
            to: { $0.showHidden = $1 })
binder.bind(option: parser.add(option: "-tool", kind: DriverKind.self,
                               usage: "The tool to list options of"),
            to: { $0.driverKind = $1 })

do {
  let parseResult = try parser.parse(Array(CommandLine.arguments.dropFirst()))
  var options = Options()
  try binder.fill(parseResult: parseResult, into: &options)

  // Print the option table.
  driverOptionTable.printHelp(driverKind: options.driverKind,
                              includeHidden: options.showHidden)
} catch {
  stderrStream <<< "error: " <<< error.localizedDescription
  stderrStream.flush()
  exit(EXIT_FAILURE)
}
