//===--------------- DriverKind.swift - Swift Driver Kind -----------------===//
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

/// Describes which mode the driver is in.
public enum DriverKind: String {
  case interactive = "swift"
  case batch = "swiftc"
}

extension DriverKind {
  public var usage: String {
    switch self {
    case .interactive:
      return "swift"
    case .batch:
      return "swiftc"
    }
  }

  public var seeAlsoHelpMessage: String? {
    switch self {
    case .interactive:
      return """
             SEE ALSO - PACKAGE MANAGER COMMANDS:
                     "swift build" Build sources into binary products
                     "swift package" Perform operations on Swift packages
                     "swift run" Build and run an executable product
                     "swift test" Build and run tests
             """
    case .batch:
      return "SEE ALSO: swift build, swift run, swift package, swift test"
    }
  }
}
