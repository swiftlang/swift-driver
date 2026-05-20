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

import SwiftDriver
import Testing

@Suite struct StringAdditionsTests {

  @Test func basicIdentifiers() {
    #expect("contains_Underscore".sd_isSwiftIdentifier)
    #expect("_startsWithUnderscore".sd_isSwiftIdentifier)
    #expect("contains_Number5".sd_isSwiftIdentifier)
    #expect("_1".sd_isSwiftIdentifier)
    #expect(!"5startsWithNumber".sd_isSwiftIdentifier)
    #expect(!"contains space".sd_isSwiftIdentifier)
    #expect(!"contains\nnewline".sd_isSwiftIdentifier)
    #expect(!"contains\ttab".sd_isSwiftIdentifier)
    #expect(!"contains_punctuation,.!?#".sd_isSwiftIdentifier)
    #expect("contains$dollar".sd_isSwiftIdentifier)
    #expect(!"$startsWithDollar".sd_isSwiftIdentifier)
    #expect(!"operators+-=*/^".sd_isSwiftIdentifier)
    #expect(!"braces{}".sd_isSwiftIdentifier)
    #expect(!"angleBrackets<>".sd_isSwiftIdentifier)
    #expect(!"parens()".sd_isSwiftIdentifier)
    #expect(!"squareBrackets[]".sd_isSwiftIdentifier)

    #expect(
      !"<#some name#>".sd_isSwiftIdentifier,
      "Placeholders are not valid identifiers"
    )

    #expect(!"".sd_isSwiftIdentifier)
    #expect(!"`$`".sd_isSwiftIdentifier)
    #expect(!"backtick`".sd_isSwiftIdentifier)
  }

  @Test func swiftKeywordsAsIdentifiers() {
    #expect("import".sd_isSwiftIdentifier)
    #expect("func".sd_isSwiftIdentifier)
    #expect("var".sd_isSwiftIdentifier)
    #expect("typealias".sd_isSwiftIdentifier)
    #expect("class".sd_isSwiftIdentifier)
    #expect("struct".sd_isSwiftIdentifier)
    #expect("enum".sd_isSwiftIdentifier)
    #expect("associatedtype".sd_isSwiftIdentifier)
    #expect("prefix".sd_isSwiftIdentifier)
    #expect("infix".sd_isSwiftIdentifier)
    #expect("postfix".sd_isSwiftIdentifier)
    #expect("_".sd_isSwiftIdentifier)
  }

  @Test func unicodeCharacters() {
    #expect("👨".sd_isSwiftIdentifier)
    #expect(!"❤️".sd_isSwiftIdentifier)
    #expect("💑".sd_isSwiftIdentifier)  // Single codepoint
    #expect(!"🙍🏻‍♂️".sd_isSwiftIdentifier)  // Multiple codepoints
    #expect("你好".sd_isSwiftIdentifier)
    #expect("שלום".sd_isSwiftIdentifier)
    #expect("வணக்கம்".sd_isSwiftIdentifier)
    #expect("Γειά".sd_isSwiftIdentifier)
    #expect("яЛюблюСвифт".sd_isSwiftIdentifier)

    #expect(
      !".́duh".sd_isSwiftIdentifier,
      "Identifiers cannot start with combining chars"
    )

    #expect(
      "s̈pin̈al_tap̈".sd_isSwiftIdentifier,
      "Combining characters can be used within identifiers"
    )

    #expect(
      !"".sd_isSwiftIdentifier,
      "Private-use characters aren't valid Swift identifiers"
    )
  }

  @Test func rawIdentifiers() {
    #expect("plain".sd_isValidAsRawIdentifier)
    #expect("has spaces".sd_isValidAsRawIdentifier)
    #expect("$^has/other!characters@#".sd_isValidAsRawIdentifier)

    #expect(!"has`backtick".sd_isValidAsRawIdentifier)
    #expect(!"has\\backslash".sd_isValidAsRawIdentifier)
    #expect(!"has\u{0000}control\u{007F}characters".sd_isValidAsRawIdentifier)
    #expect(!"has\u{00A0}forbidden\u{2028}whitespace".sd_isValidAsRawIdentifier)
    #expect(!" ".sd_isValidAsRawIdentifier)
  }
}
