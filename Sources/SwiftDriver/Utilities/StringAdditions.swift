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
  var isSwiftIdentifier: Bool {
    if isEmpty { return false }

    // FIXME: This is a hack. Check the actual identifier grammar here.
    return spm_mangledToC99ExtendedIdentifier() == self
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
