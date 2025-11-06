//===---------- PathExtensions.swift - Driver Testing Extensions ----------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import TSCBasic
import SwiftDriver
import struct Foundation.URL

extension AbsolutePath {
  public func nativePathString(escaped: Bool) -> String {
    return URL(fileURLWithPath: self.pathString).withUnsafeFileSystemRepresentation {
      let repr: String = String(cString: $0!)
      if escaped { return repr.replacingOccurrences(of: "\\", with: "\\\\") }
      return repr
    }
  }
}

extension VirtualPath {
  public func nativePathString(escaped: Bool) -> String {
    return URL(fileURLWithPath: self.description).withUnsafeFileSystemRepresentation {
      let repr: String = String(cString: $0!)
      if escaped { return repr.replacingOccurrences(of: "\\", with: "\\\\") }
      return repr
    }
  }
}
