//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import SwiftOptions
import Testing

@Suite struct SwiftDriverTests {
    @Test func parsing() throws {
      // Form an options table
      let options = OptionTable()
      // Parse each kind of option
      let results = try options.parse([
        "input1", "-color-diagnostics", "-Ifoo", "-I", "bar spaces",
        "-I=wibble", "input2", "-module-name", "main", "-package-name", "mypkg",
        "-sanitize=a,b,c", "--", "-foo", "-bar"], for: .batch)
#if os(Windows)
      #expect(results.description ==
                     #"input1 -color-diagnostics -I foo -I "bar spaces" -I=wibble input2 -module-name main -package-name mypkg -sanitize=a,b,c -- -foo -bar"#)
#else
      #expect(results.description ==
                     "input1 -color-diagnostics -I foo -I 'bar spaces' -I=wibble input2 -module-name main -package-name mypkg -sanitize=a,b,c -- -foo -bar")
#endif
    }

  @Test func parsingRemaining() throws {
    let options = OptionTable()
    let results = try options.parse(["--", "input1", "input2"], for: .batch)
    #expect(results.description == "-- input1 input2")
  }

  @Test func parsingMultiArg() throws {
    var options = OptionTable()
    let two = Option("-two", .multiArg, attributes: [], numArgs: 2)
    let three = Option("-three", .multiArg, attributes: [], numArgs: 3)
    options.addNewOption(two)
    options.addNewOption(three)
    var results = try options.parse(["-two", "1", "2", "-three", "1", "2", "3", "-two", "2", "3"], for: .batch)
    #expect(results.description == "-two 1 2 -three 1 2 3 -two 2 3")
    // test that the arguments are assigned to their corresponding flag correctly
    #expect(results.allInputs.count == 0)
    let twoOpts = results.arguments(for: two)
    #expect(twoOpts.count == 2)
    #expect(twoOpts[0].argument.asMultiple[0] == "1")
    #expect(twoOpts[0].argument.asMultiple[1] == "2")
    #expect(twoOpts[1].argument.asMultiple[0] == "2")
    #expect(twoOpts[1].argument.asMultiple[1] == "3")
    let threeOpts = results.arguments(for: three)
    #expect(threeOpts.count == 1)
    #expect(threeOpts[0].argument.asMultiple[0] == "1")
    #expect(threeOpts[0].argument.asMultiple[1] == "2")
    #expect(threeOpts[0].argument.asMultiple[2] == "3")
    // Check not enough arguments are passed.
    #expect {
      try options.parse(["-two", "1"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .missingArgument(index: 0, argument: "-two")
    }
  }

  @Test func parseErrors() {
    let options = OptionTable()

    #expect {
      try options.parse(["-unrecognized"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .unknownOption(index: 0, argument: "-unrecognized")
    }

    // Ensure we check for an unexpected suffix on flags before checking if they are accepted by the current mode.
    #expect {
      try options.parse(["-c-NOT"], for: .interactive)
    } throws: {
      $0 as? OptionParseError == .unknownOption(index: 0, argument: "-c-NOT")
    }

    #expect {
      try options.parse(["-module-name-NOT", "foo"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .unknownOption(index: 0, argument: "-module-name-NOT")
    }

    #expect {
      try options.parse(["-I"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .missingArgument(index: 0, argument: "-I")
    }

    #expect {
      try options.parse(["-color-diagnostics", "-I"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .missingArgument(index: 1, argument: "-I")
    }

    #expect {
      try options.parse(["-module-name"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .missingArgument(index: 0, argument: "-module-name")
    }

    #expect {
      try options.parse(["-package-name"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .missingArgument(index: 0, argument: "-package-name")
    }

    #expect {
      try options.parse(["-package-name"], for: .interactive)
    } throws: {
      $0 as? OptionParseError == .missingArgument(index: 0, argument: "-package-name")
    }

    #expect {
      try options.parse(["-o"], for: .interactive)
    } throws: {
      $0 as? OptionParseError == .unsupportedOption(index: 0, argument: "-o", option: .o, currentDriverKind: .interactive)
    }

    #expect {
      try options.parse(["-repl"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .unsupportedOption(index: 0, argument: "-repl", option: .repl, currentDriverKind: .batch)
    }

    #expect {
      try options.parse(["--invalid"], for: .batch)
    } throws: {
      $0 as? OptionParseError == .unknownOption(index: 0, argument: "--invalid")
    }
  }
}

extension OptionTable {
    mutating func addNewOption(_ opt: Option) {
        options.append(opt)
    }
}
