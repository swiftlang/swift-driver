//===--------------- DateAdditions.swift - Swift Date Additions -----------===//
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
import Foundation

public extension Date {
  init(legacyDriverSecsAndNanos secsAndNanos: [Int]) throws {
  enum Errors: LocalizedError {
    case needSecondsAndNanoseconds
  }
  guard secsAndNanos.count == 2 else {
    throw Errors.needSecondsAndNanoseconds
    }
    self = Self(legacyDriverSecs: secsAndNanos[0], nanos: secsAndNanos[1])
  }
  init(legacyDriverSecs secs: Int, nanos: Int) {
    self = Date(timeIntervalSince1970: Double(secs) + Double(nanos) / 1e9)
  }
  var legacyDriverSecsAndNanos: [Int] {
    let totalNanos = timeIntervalSince1970
    let secs  = Int(              floor(totalNanos))
    let nanos = Int((totalNanos - floor(totalNanos)) * 1e9)
    return [secs, nanos]
  }
}
