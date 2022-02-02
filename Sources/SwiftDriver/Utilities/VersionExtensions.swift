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

import struct TSCUtility.Version

// TODO: maybe move this to TSC.
extension Version {
  /// Returns the version with out any build/release metadata numbers.
  var withoutBuildNumbers: Version {
    return Version(self.major, self.minor, self.patch)
  }
}
