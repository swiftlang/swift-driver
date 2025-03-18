//===--------------- StringAdditions.swift - Swift String Additions -------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
extension String {
  /// Whether this string is a Swift identifier.
  public var sd_isSwiftIdentifier: Bool {
    guard let start = unicodeScalars.first else {
      return false
    }

    let continuation = unicodeScalars.dropFirst()

    return start.isValidSwiftIdentifierStart &&
           continuation.allSatisfy { $0.isValidSwiftIdentifierContinuation }
  }

  /// Whether this string is a valid Swift raw identifier.
  public var sd_isValidAsRawIdentifier: Bool {
    guard !isEmpty else {
      return false
    }
    return unicodeScalars.allSatisfy { $0.isValidRawIdentifierScalar }
           && !unicodeScalars.allSatisfy { $0.isPermittedRawIdentifierWhitespace }
  }
}

extension DefaultStringInterpolation {
  /// Interpolates either the provided `value`, or if it is `nil`, the
  /// `defaultValue`.
  mutating func appendInterpolation<T>(_ value: T?, or defaultValue: String) {
    guard let value = value else {
      return appendInterpolation(defaultValue)
    }
    appendInterpolation(value)
  }
}

extension Unicode.Scalar {

  var isValidSwiftIdentifierStart: Bool {
    guard isValidSwiftIdentifierContinuation else { return false }

    if isASCIIDigit || self == "$" {
      return false
    }

    // N1518: Recommendations for extended identifier characters for C and C++
    // Proposed Annex X.2: Ranges of characters disallowed initially
    if (0x0300...0x036F).contains(value) ||
       (0x1DC0...0x1DFF).contains(value) ||
       (0x20D0...0x20FF).contains(value) ||
       (0xFE20...0xFE2F).contains(value) {
      return false
    }

    return true
  }

  var isValidSwiftIdentifierContinuation: Bool {
    if isASCII {
      return isCIdentifierBody(allowDollar: true)
    }

    // N1518: Recommendations for extended identifier characters for C and C++
    // Proposed Annex X.1: Ranges of characters allowed
    return value == 0x00A8 ||
           value == 0x00AA ||
           value == 0x00AD ||
           value == 0x00AF ||

           (0x00B2...0x00B5).contains(value) ||
           (0x00B7...0x00BA).contains(value) ||
           (0x00BC...0x00BE).contains(value) ||
           (0x00C0...0x00D6).contains(value) ||
           (0x00D8...0x00F6).contains(value) ||
           (0x00F8...0x00FF).contains(value) ||

           (0x0100...0x167F).contains(value) ||
           (0x1681...0x180D).contains(value) ||
           (0x180F...0x1FFF).contains(value) ||

           (0x200B...0x200D).contains(value) ||
           (0x202A...0x202E).contains(value) ||
           (0x203F...0x2040).contains(value) ||
           value == 0x2054                   ||
           (0x2060...0x206F).contains(value) ||

           (0x2070...0x218F).contains(value) ||
           (0x2460...0x24FF).contains(value) ||
           (0x2776...0x2793).contains(value) ||
           (0x2C00...0x2DFF).contains(value) ||
           (0x2E80...0x2FFF).contains(value) ||

           (0x3004...0x3007).contains(value) ||
           (0x3021...0x302F).contains(value) ||
           (0x3031...0x303F).contains(value) ||

           (0x3040...0xD7FF).contains(value) ||

           (0xF900...0xFD3D).contains(value) ||
           (0xFD40...0xFDCF).contains(value) ||
           (0xFDF0...0xFE44).contains(value) ||
           (0xFE47...0xFFF8).contains(value) ||

           (0x10000...0x1FFFD).contains(value) ||
           (0x20000...0x2FFFD).contains(value) ||
           (0x30000...0x3FFFD).contains(value) ||
           (0x40000...0x4FFFD).contains(value) ||
           (0x50000...0x5FFFD).contains(value) ||
           (0x60000...0x6FFFD).contains(value) ||
           (0x70000...0x7FFFD).contains(value) ||
           (0x80000...0x8FFFD).contains(value) ||
           (0x90000...0x9FFFD).contains(value) ||
           (0xA0000...0xAFFFD).contains(value) ||
           (0xB0000...0xBFFFD).contains(value) ||
           (0xC0000...0xCFFFD).contains(value) ||
           (0xD0000...0xDFFFD).contains(value) ||
           (0xE0000...0xEFFFD).contains(value)
  }

  /// `true` if this character is an ASCII digit: [0-9]
  var isASCIIDigit: Bool { (0x30...0x39).contains(value) }

  /// `true` if this scalar is valid in a Swift raw identifier.
  var isValidRawIdentifierScalar: Bool {
    // A raw identifier is terminated by a backtick, and the backslash is reserved for possible
    // future escaping.
    if self == "`" || self == "\\" {
      return false
    }
    // Unprintable ASCII control characters are forbidden.
    if (0x0000...0x001F).contains(value) || value == 0x007F {
      return false;
    }
    return !isForbiddenRawIdentifierWhitespace
  }

  var isForbiddenRawIdentifierWhitespace: Bool {
    // This is the set of code points satisfying the `White_Space` property, excluding the set
    // satisfying the `Pattern_White_Space` property, and excluding any other ASCII non-printables
    // and Unicode separators. In other words, the only whitespace code points allowed in a raw
    // identifier are U+0020, and U+200E/200F (LTR/RTL marks) (see
    // `isPermittedRawIdentifierWhitespace` below).
    return (0x0009...0x000D).contains(value) ||
           value == 0x0085 ||
           value == 0x00A0 ||
           value == 0x1680 ||
           (0x2000...0x200A).contains(value) ||
           (0x2028...0x2029).contains(value) ||
           value == 0x202F ||
           value == 0x205F ||
           value == 0x3000
  }

  var isPermittedRawIdentifierWhitespace: Bool {
    return value == 0x0020 ||
           value == 0x200E ||
           value == 0x200F
  }

  /// `true` if this is a body character of a C identifier,
  /// which is [a-zA-Z0-9_].
  func isCIdentifierBody(allowDollar: Bool = false) -> Bool {
    if (0x41...0x5A).contains(value) ||
       (0x61...0x7A).contains(value) ||
       isASCIIDigit                  ||
       self == "_" {
      return true
    } else {
      return allowDollar && self == "$"
    }
  }
}

extension Character {
  var isShellQuote: Bool {
    return self == "\"" || self == "'"
  }
}
