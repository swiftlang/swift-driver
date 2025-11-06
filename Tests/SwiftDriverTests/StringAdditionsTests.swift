//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import SwiftDriver

final class StringAdditionsTests: XCTestCase {

    func testBasicIdentifiers() {
        XCTAssertTrue("contains_Underscore".sd_isSwiftIdentifier)
        XCTAssertTrue("_startsWithUnderscore".sd_isSwiftIdentifier)
        XCTAssertTrue("contains_Number5".sd_isSwiftIdentifier)
        XCTAssertTrue("_1".sd_isSwiftIdentifier)
        XCTAssertFalse("5startsWithNumber".sd_isSwiftIdentifier)
        XCTAssertFalse("contains space".sd_isSwiftIdentifier)
        XCTAssertFalse("contains\nnewline".sd_isSwiftIdentifier)
        XCTAssertFalse("contains\ttab".sd_isSwiftIdentifier)
        XCTAssertFalse("contains_punctuation,.!?#".sd_isSwiftIdentifier)
        XCTAssertTrue("contains$dollar".sd_isSwiftIdentifier)
        XCTAssertFalse("$startsWithDollar".sd_isSwiftIdentifier)
        XCTAssertFalse("operators+-=*/^".sd_isSwiftIdentifier)
        XCTAssertFalse("braces{}".sd_isSwiftIdentifier)
        XCTAssertFalse("angleBrackets<>".sd_isSwiftIdentifier)
        XCTAssertFalse("parens()".sd_isSwiftIdentifier)
        XCTAssertFalse("squareBrackets[]".sd_isSwiftIdentifier)

        XCTAssertFalse("<#some name#>".sd_isSwiftIdentifier,
                       "Placeholders are not valid identifiers")

        XCTAssertFalse("".sd_isSwiftIdentifier)
        XCTAssertFalse("`$`".sd_isSwiftIdentifier)
        XCTAssertFalse("backtick`".sd_isSwiftIdentifier)
    }

    func testSwiftKeywordsAsIdentifiers() {
        XCTAssertTrue("import".sd_isSwiftIdentifier)
        XCTAssertTrue("func".sd_isSwiftIdentifier)
        XCTAssertTrue("var".sd_isSwiftIdentifier)
        XCTAssertTrue("typealias".sd_isSwiftIdentifier)
        XCTAssertTrue("class".sd_isSwiftIdentifier)
        XCTAssertTrue("struct".sd_isSwiftIdentifier)
        XCTAssertTrue("enum".sd_isSwiftIdentifier)
        XCTAssertTrue("associatedtype".sd_isSwiftIdentifier)
        XCTAssertTrue("prefix".sd_isSwiftIdentifier)
        XCTAssertTrue("infix".sd_isSwiftIdentifier)
        XCTAssertTrue("postfix".sd_isSwiftIdentifier)
        XCTAssertTrue("_".sd_isSwiftIdentifier)
    }

    func testUnicodeCharacters() {
        XCTAssertTrue("👨".sd_isSwiftIdentifier)
        XCTAssertFalse("❤️".sd_isSwiftIdentifier)
        XCTAssertTrue("💑".sd_isSwiftIdentifier) // Single codepoint
        XCTAssertFalse("🙍🏻‍♂️".sd_isSwiftIdentifier) // Multiple codepoints
        XCTAssertTrue("你好".sd_isSwiftIdentifier)
        XCTAssertTrue("שלום".sd_isSwiftIdentifier)
        XCTAssertTrue("வணக்கம்".sd_isSwiftIdentifier)
        XCTAssertTrue("Γειά".sd_isSwiftIdentifier)
        XCTAssertTrue("яЛюблюСвифт".sd_isSwiftIdentifier)

        XCTAssertFalse(".́duh".sd_isSwiftIdentifier,
                       "Identifiers cannot start with combining chars")

        XCTAssertTrue("s̈pin̈al_tap̈".sd_isSwiftIdentifier,
                      "Combining characters can be used within identifiers")

        XCTAssertFalse("".sd_isSwiftIdentifier,
                       "Private-use characters aren't valid Swift identifiers")
    }

    func testRawIdentifiers() {
        XCTAssertTrue("plain".sd_isValidAsRawIdentifier)
        XCTAssertTrue("has spaces".sd_isValidAsRawIdentifier)
        XCTAssertTrue("$^has/other!characters@#".sd_isValidAsRawIdentifier)

        XCTAssertFalse("has`backtick".sd_isValidAsRawIdentifier)
        XCTAssertFalse("has\\backslash".sd_isValidAsRawIdentifier)
        XCTAssertFalse("has\u{0000}control\u{007F}characters".sd_isValidAsRawIdentifier)
        XCTAssertFalse("has\u{00A0}forbidden\u{2028}whitespace".sd_isValidAsRawIdentifier)
        XCTAssertFalse(" ".sd_isValidAsRawIdentifier)
    }
}
