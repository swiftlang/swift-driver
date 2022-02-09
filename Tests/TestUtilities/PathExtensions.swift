//===---------- PathExtensions.swift - Driver Testing Extensions ----------===//
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

import Foundation
import TSCBasic

extension String {
  public func escaped() -> Self {
#if os(Windows)
    return self.replacingOccurrences(of: "\\", with: "\\\\")
#else
    return self
#endif
  }

  public func nativePathString() -> Self {
    return URL(fileURLWithPath: self).withUnsafeFileSystemRepresentation {
      String(cString: $0!)
    }
  }
}

extension AbsolutePath {
  public func nativePathString(escaped: Bool) -> String {
    return URL(fileURLWithPath: self.pathString).withUnsafeFileSystemRepresentation {
      let repr: String = String(cString: $0!)
      if escaped { return repr.replacingOccurrences(of: "\\", with: "\\\\") }
      return repr
    }
  }
}
