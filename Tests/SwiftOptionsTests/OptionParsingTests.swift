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
        "-I=wibble", "input2", "-module-name", "main",
        "-sanitize=a,b,c", "--", "-foo", "-bar"], for: .batch)
      XCTAssertEqual(results.description,
                     "input1 -color-diagnostics -I foo -I 'bar spaces' -I=wibble input2 -module-name main -sanitize=a,b,c -- -foo -bar")
    }

  func testParseErrors() {
    let options = OptionTable()

    XCTAssertThrowsError(try options.parse(["-unrecognized"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .unknownOption(index: 0, argument: "-unrecognized"))
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

    XCTAssertThrowsError(try options.parse(["-o"], for: .interactive)) { error in
      XCTAssertEqual(error as? OptionParseError, .unsupportedOption(index: 0, argument: "-o", option: .o, currentDriverKind: .interactive))
    }

    XCTAssertThrowsError(try options.parse(["-repl"], for: .batch)) { error in
      XCTAssertEqual(error as? OptionParseError, .unsupportedOption(index: 0, argument: "-repl", option: .repl, currentDriverKind: .batch))
    }

  }
}
