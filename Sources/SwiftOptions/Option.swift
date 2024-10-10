//===--------------- Option.swift - Swift Command Line Option -------------===//
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
/// Attributes that describe where and how the option is used.
public struct OptionAttributes: OptionSet, Hashable {
  public let rawValue: UInt

  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  public static let helpHidden                    = OptionAttributes(rawValue: 0x1)
  public static let frontend                      = OptionAttributes(rawValue: 0x2)
  public static let noDriver                      = OptionAttributes(rawValue: 0x4)
  public static let noInteractive                 = OptionAttributes(rawValue: 0x8)
  public static let noBatch                       = OptionAttributes(rawValue: 0x10)
  public static let doesNotAffectIncrementalBuild = OptionAttributes(rawValue: 0x20)
  public static let autolinkExtract               = OptionAttributes(rawValue: 0x40)
  public static let moduleWrap                    = OptionAttributes(rawValue: 0x80)
  public static let synthesizeInterface           = OptionAttributes(rawValue: 0x100)
  public static let argumentIsPath                = OptionAttributes(rawValue: 0x200)
  public static let moduleInterface               = OptionAttributes(rawValue: 0x400)
  public static let supplementaryOutput           = OptionAttributes(rawValue: 0x800)
  public static let argumentIsFileList            = OptionAttributes(rawValue: 0x1000)
  public static let cacheInvariant                = OptionAttributes(rawValue: 0x2000)
}

/// Describes a command-line option.
public struct Option {
  /// The kind of option we have, which determines how it will be parsed.
  public enum Kind: Hashable {
    /// An input file, which doesn't have a spelling but contains a single extension Driver {
    /// argument.
    case input
    /// An option that enables/disables some specific behavior.
    case flag
    /// An option whose argument directly follows the spelling.
    case joined
    /// An option whose argument is in the following command-line argument.
    case separate
    /// An option whose argument either directly follows the spelling (like
    /// `.joined`) when non-empty, or otherwise is the following command-line
    /// argument (like `.separate`).
    case joinedOrSeparate
    /// An option with multiple arguments, which are collected from all
    /// falling command-line arguments.
    case remaining
    /// An option with multiple arguments, which are collected by splitting
    /// the text directly following the spelling at each comma.
    case commaJoined
    /// An option with multiple arguments, which the number of arguments is
    /// specified by numArgs.
    case multiArg
  }

  /// The spelling of the option, including any leading dashes.
  public let spelling: String

  /// The kind of option, which determines how it is parsed.
  public let kind: Kind

  /// The option that this aliases, if any, as a closure that produces the
  /// valid.
  private let aliasFunction: (() -> Option)?

  /// The attributes that describe where and how the attribute is used.
  public let attributes: OptionAttributes

  /// For options that have an argument, the name of the metavariable to
  /// use in documentation.
  public let metaVar: String?

  /// Help text to display with this option.
  public let helpText: String?

  /// The group in which this option occurs.
  public let group: Group?

  /// The number of arguments for MultiArg options.
  public let numArgs: UInt

  public init(_ spelling: String, _ kind: Kind,
              alias: Option? = nil,
              attributes: OptionAttributes = [], metaVar: String? = nil,
              helpText: String? = nil,
              group: Group? = nil,
              numArgs: UInt = 0) {
    self.spelling = spelling
    self.kind = kind
    self.aliasFunction = alias.map { aliasOption in { aliasOption }}
    self.attributes = attributes
    self.metaVar = metaVar
    self.helpText = helpText
    self.group = group
    self.numArgs = numArgs
  }
}

extension Option: Equatable {
  public static func ==(lhs: Option, rhs: Option) -> Bool {
    return lhs.spelling == rhs.spelling
  }
}

extension Option: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(spelling)
  }
}

extension Option {
  /// Whether this option is an alias.
  public var isAlias: Bool { aliasFunction != nil }

  /// Retrieves the alias option, if there is one.
  public var alias: Option? {
    aliasFunction.map { function in function() }
  }

  /// Whether this option's help is hidden under normal circumstances.
  public var isHelpHidden: Bool { attributes.contains(.helpHidden) }

  /// Whether this option can affect an incremental build.
  public var affectsIncrementalBuild: Bool {
    !attributes.contains(.doesNotAffectIncrementalBuild)
  }

  /// Retrieves the canonical option, to be used for comparisons.
  public var canonical: Option {
    guard let alias = alias else { return self }
    return alias.canonical
  }
}

extension Option {
  /// Whether this option is accepted by a driver of the given kind.
  public func isAccepted(by driverKind: DriverKind) -> Bool {
    switch driverKind {
    case .batch:
      return attributes.isDisjoint(with: [.noDriver, .noBatch])
    case .interactive:
      return attributes.isDisjoint(with: [.noDriver, .noInteractive])
    }
  }
}
