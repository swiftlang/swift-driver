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
  case moduleWrap = "swift-modulewrap"
  case frontend = "swift-frontend"
  case autolinkExtract = "swift-autolink-extract"
  case indent = "swift-indent"

  /// Returns true if driver kind is Swift compiler.
  public var isSwiftCompiler: Bool {
    return self == .interactive || self == .batch
  }
}

extension DriverKind {
  public var usage: String {
    usageArgs.joined(separator: " ")
  }

  public var usageArgs: [String] {
    switch self {
    case .autolinkExtract:
      return ["swift-autolink-extract"]

    case .batch:
      return ["swiftc"]

    case .frontend:
      return ["swift", "-frontend"]

    case .indent:
      return ["swift-indent"]

    case .interactive:
      return ["swift"]

    case .moduleWrap:
      return ["swift-modulewrap"]
    }
  }

  public var title: String {
    switch self {
    case .autolinkExtract:
      return "Swift Autolink Extract"

    case .frontend:
      return "Swift frontend"

    case .indent:
      return "Swift Format Tool"

    case .batch, .interactive:
      return "Swift compiler"

    case .moduleWrap:
      return "Swift Module Wrapper"
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
    default:
      return nil
    }
  }
}
