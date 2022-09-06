//===------------- WindowsExtensions.swift - Windows Extensions -----------===//
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

internal func executableName(_ name: String) -> String {
#if os(Windows)
  if name.count > 4, name.suffix(from: name.index(name.endIndex, offsetBy: -4)) == ".exe" {
    return name
  }
  return "\(name).exe"
#else
  return name
#endif
}
