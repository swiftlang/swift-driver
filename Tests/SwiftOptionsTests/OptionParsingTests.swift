//===------------- OptionParsingTests.swift - Parsing Tests ------======---===//
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
import XCTest

final class SwiftDriverTests: XCTestCase {
    func testParsing() throws {
      // Form an options table
      let options = OptionTable()
      // Parse each kind of option
      let results = try options.parse([
        "input1", "-color-diagnostics", "-Ifoo", "-I", "bar spaces",
        "-I=wibble", "input2", "-module-name", "main", "-package-name", "mypkg",
        "-sanitize=a,b,c", "--", "-foo", "-bar"], for: .batch)
#if os(Windows)
      XCTAssertEqual(results.description,
                     #"input1 -color-diagnostics -I foo -I "bar spaces" -I=wibble input2 -module-name main -package-name mypkg -sanitize=a,b,c -- -foo -bar"#)
#else
      XCTAssertEqual(results.description,
                     "input1 -color-diagnostics -I foo -I 'bar spaces' -I=wibble input2 -module-name main -package-name mypkg -sanitize=a,b,c -- -foo -bar")
#endif
    }

  func testParsingRemaining() throws {
    let options = OptionTable()
    let results = try options.parse(["--", "input1", "input2"], for: .batch)
    XCTAssertEqual(results.description, "-- input1 input2")
  }

  func testParsingMultiArg() throws {
    var options = OptionTable()
    let two = Option("-two", .multiArg, attributes: [], numArgs: 2)
    let three = Option("-three", .multiArg, attributes: [], numArgs: 3)
    options.addNewOption(two)
    options.addNewOption(three)
    let results = try options.parse(["-two", "1", "2", "-three", "1", "2", "3", "-two", "2", "3"], for: .batch)
    XCTAssertEqual(results.description, "-two 1 2 -three 1 2 3 -two 2 3")
    // Check not enough arguments are passed.
    XCTAssertThrowsError(try options.parse(["-two", "1"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 0, argument: "-two"))
    }
  }

  func testParseErrors() {
    let options = OptionTable()

    XCTAssertThrowsError(try options.parse(["-unrecognized"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .unknownOption(index: 0, argument: "-unrecognized"))
    }

    // Ensure we check for an unexpected suffix on flags before checking if they are accepted by the current mode.
    XCTAssertThrowsError(try options.parse(["-c-NOT"], for: .interactive)) { error in
      XCTAssertEqual(error as? OptionParseError, .unknownOption(index: 0, argument: "-c-NOT"))
    }

    XCTAssertThrowsError(try options.parse(["-module-name-NOT", "foo"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .unknownOption(index: 0, argument: "-module-name-NOT"))
    }

    XCTAssertThrowsError(try options.parse(["-I"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 0, argument: "-I"))
    }

    XCTAssertThrowsError(try options.parse(["-color-diagnostics", "-I"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 1, argument: "-I"))
    }

    XCTAssertThrowsError(try options.parse(["-module-name"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 0, argument: "-module-name"))
    }

    XCTAssertThrowsError(try options.parse(["-package-name"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 0, argument: "-package-name"))
    }

    XCTAssertThrowsError(try options.parse(["-package-name"], for: .interactive)) { error in
      XCTAssertEqual(error as? OptionParseError, .missingArgument(index: 0, argument: "-package-name"))
    }

    XCTAssertThrowsError(try options.parse(["-o"], for: .interactive)) { error in
      XCTAssertEqual(error as? OptionParseError, .unsupportedOption(index: 0, argument: "-o", option: .o, currentDriverKind: .interactive))
    }

    XCTAssertThrowsError(try options.parse(["-repl"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .unsupportedOption(index: 0, argument: "-repl", option: .repl, currentDriverKind: .batch))
    }

    XCTAssertThrowsError(try options.parse(["--invalid"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .unknownOption(index: 0, argument: "--invalid"))
    }
  }
}

extension OptionTable {
    mutating func addNewOption(_ opt: Option) {
        options.append(opt)
    }
}
