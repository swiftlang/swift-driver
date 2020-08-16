//===---------- VersionExtensions.swift - Version Parsing Utilities -------===//
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

import TSCUtility

// TODO: maybe move this to TSC.
extension Version {
  /// Create a version from a string, replacing unknown trailing components with '0'.
  init?(potentiallyIncompleteVersionString string: String) {
    // This is a copied version of TSC's version parsing, modified to fill
    // in missing components if needed.
    let prereleaseStartIndex = string.firstIndex(of: "-")
    let metadataStartIndex = string.firstIndex(of: "+")

    let requiredEndIndex = prereleaseStartIndex ?? metadataStartIndex ?? string.endIndex
    let requiredCharacters = string.prefix(upTo: requiredEndIndex)
    var requiredComponents = requiredCharacters
      .split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
      .map(String.init).compactMap({ Int($0) }).filter({ $0 >= 0 })

    requiredComponents.append(contentsOf:
                                Array(repeating: 0,
                                      count: max(0, 3 - requiredComponents.count)))

    let major = requiredComponents[0]
    let minor = requiredComponents[1]
    let patch = requiredComponents[2]

    func identifiers(start: String.Index?, end: String.Index) -> [String] {
      guard let start = start else { return [] }
      let identifiers = string[string.index(after: start)..<end]
      return identifiers.split(separator: ".").map(String.init)
    }

    let prereleaseIdentifiers = identifiers(
      start: prereleaseStartIndex,
      end: metadataStartIndex ?? string.endIndex)
    let buildMetadataIdentifiers = identifiers(
      start: metadataStartIndex,
      end: string.endIndex)

    self.init(major, minor, patch,
              prereleaseIdentifiers: prereleaseIdentifiers,
              buildMetadataIdentifiers: buildMetadataIdentifiers)
  }

  /// Returns the version with out any build/release metadata numbers.
  var withoutBuildNumbers: Version {
    return Version(self.major, self.minor, self.patch)
  }
}
