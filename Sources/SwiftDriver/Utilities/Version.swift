//===--------------- Version.swift - Version Handling Routines ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Errors related to a version string.
public enum VersionError: Error {
  /// The version string contains non-ASCII characters.
  case nonASCIIVersionString(_ string: String)
  /// The version core contains an invalid number of components.
  case invalidComponentCount(_ components: [String], lenient: Bool)
  /// Some or all of the version core components contain non-numerical
  /// characters or are empty.
  case nonNumericalOrEmptyVersionCoreIdentifiers(_ components: [String])
  /// Some or all of the build metadata components contain characters outside
  /// the alphanumeric class joined with hyphen.
  case nonAlphaNumericOrHyphenBuildMetadataComponents(_ components: [String])
  /// Some or all of the pre-release components contain characters outside the
  /// alphanumeric class joined with hyphen.
  case nonAlphaNumericOrHyphenPrereleaseComponents(_ components: [String])
}

extension VersionError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .nonASCIIVersionString(string):
      return "non-ASCII characters in version string '\(string)'"
    case let .invalidComponentCount(components, lenient):
      return "\(components.count > 3 ? "more than 3" : "fewer than \(lenient ? 2 : 3)") identifiers in version core '\(components.joined(separator: "."))'"
    case let .nonNumericalOrEmptyVersionCoreIdentifiers(components):
      if !components.allSatisfy({ !$0.isEmpty }) {
        return "empty identifiers in version core '\(components.joined(separator: "."))'"
      }

      let invalidComponents = components.filter { !$0.allSatisfy(\.isNumber) }
      return "non-numerical characters in version core identifier\(invalidComponents.count > 1 ? "s" : "") \(invalidComponents.map { "'\($0)'" }.joined(separator: ", "))"
    case let .nonAlphaNumericOrHyphenBuildMetadataComponents(components):
      let invalidComponents = components.filter { !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
      return "characters other than alphanumeric or hyphen in build metadata identifier\(invalidComponents.count > 1 ? "s" : "") \(invalidComponents.map { "'\($0)'" }.joined(separator: ", "))"
    case let .nonAlphaNumericOrHyphenPrereleaseComponents(components):
      let invalidComponents = components.filter { !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
      return "characters other than alphanumeric or hyphen in pre-release identifier\(invalidComponents.count > 1 ? "s" : "") \(invalidComponents.map { "'\($0)'" }.joined(separator: ", "))"
    }
  }
}

/// A representation of a semantic version.
public struct Version {
  /// The major version number component.
  public let major: Int
  /// The minor version number component.
  public let minor: Int
  /// The patch version number component.
  public let patch: Int

  /// The pre-release components.
  public let prerelease: [String]
  /// The build metadata components.
  public let metadata: [String]

  public init(_ major: Int, _ minor: Int, _ patch: Int,
              prerelease: [String] = [], metadata: [String] = []) {
    precondition(major >= 0 && minor >= 0 && patch >= 0, "negative versioning is invalid")
    self.major = major
    self.minor = minor
    self.patch = patch

    self.prerelease = prerelease
    self.metadata = metadata
  }
}

extension Version: Comparable {
  @inlinable
  public static func == (_ lhs: Version, _ rhs: Version) -> Bool {
    return !(lhs < rhs) && !(lhs > rhs)
  }

  public static func < (_ lhs: Version, _ rhs: Version) -> Bool {
    let lhsVersion: [Int] = [lhs.major, lhs.minor, lhs.patch]
    let rhsVersion: [Int] = [rhs.major, rhs.minor, rhs.patch]

    guard lhsVersion == rhsVersion else {
      return lhsVersion.lexicographicallyPrecedes(rhsVersion)
    }

    // Non-pre-release lhs >= potentially pre-release rhs
    guard lhs.prerelease.count > 0 else { return false }
    // Pre-release lhs < non-pre-release rhs
    guard rhs.prerelease.count > 0 else { return true }

    for (lhs, rhs) in zip(lhs.prerelease, rhs.prerelease) {
      if lhs == rhs { continue }

      // Check if either of the 2 pre-release components is numeric.
      switch (Int(lhs), Int(rhs)) {
      case let (.some(lhs), .some(rhs)):
        return lhs < rhs
      case (.some(_), .none):
        // numeric pre-release < non-numeric pre-releaes
        return true
      case (.none, .some(_)):
        // non-numeric pre-release > numeric pre-release
        return false
      case (.none, .none):
        return lhs < rhs
      }
    }

    return lhs.prerelease.count < rhs.prerelease.count
  }
}

// Custom `Equatable` conformance leads to custom `Hashable` conformance.
// [SR-11588](https://bugs.swift.org/browse/SR-11588)
extension Version: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(major)
    hasher.combine(minor)
    hasher.combine(patch)
    hasher.combine(prerelease)
  }
}

extension Version: CustomStringConvertible {
  public var description: String {
    var version: String = "\(major).\(minor).\(patch)"
    if !prerelease.isEmpty {
      version += "-\(prerelease.joined(separator: "."))"
    }
    if !metadata.isEmpty {
      version += "+\(metadata.joined(separator: "."))"
    }
    return version
  }
}

extension Version {
  public init(string: String, lenient: Bool = false) throws {
    guard string.allSatisfy(\.isASCII) else {
      throw VersionError.nonASCIIVersionString(string)
    }

    let metadata: String.Index? = string.firstIndex(of: "+")
    // SemVer 2.0.0 requires that pre-release identifiers come before build
    // metadata identifiers.
    let prerelease: Substring.Index? =
        string[..<(metadata ?? string.endIndex)].firstIndex(of: "-")

    let version: String.SubSequence =
        string[..<(prerelease ?? metadata ?? string.endIndex)]
    let components: [Substring.SubSequence] =
        version.split(separator: ".", omittingEmptySubsequences: false)

    guard components.count == 3 || (lenient && components.count == 2) else {
      throw VersionError.invalidComponentCount(components.map { String($0) },
                                               lenient: lenient)
    }

    guard let major = Int(components[0]),
        let minor = Int(components[1]),
        let patch = lenient && components.count == 2 ? 0 : Int(components[2]) else {
      throw VersionError.nonNumericalOrEmptyVersionCoreIdentifiers(components.map { String($0) })
    }

    var prereleaseComponents: [String]?
    var metadataComponents: [String]?

    if let prereleaseStartIndex = prerelease {
      let offset = string.index(after: prereleaseStartIndex)
      let components = string[offset ..< (metadata ?? string.endIndex)].split(separator: ",", omittingEmptySubsequences: false)
      guard components.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
        throw VersionError.nonAlphaNumericOrHyphenBuildMetadataComponents(components.map { String($0) })
      }
      prereleaseComponents = components.map { String($0) }
    }

    if let metadataStartIndex = metadata {
      let offset = string.index(after: metadataStartIndex)
      let components = string[offset...].split(separator: ".", omittingEmptySubsequences: false)
      guard components.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
        throw VersionError.nonAlphaNumericOrHyphenBuildMetadataComponents(components.map { String($0) })
      }
      metadataComponents = components.map { String($0) }
    }

    self.init(major, minor, patch,
              prerelease: prereleaseComponents ?? [],
              metadata: metadataComponents ?? [])
  }
}
