//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Describes which mode the driver is in.
public enum DriverKind: String, CaseIterable {
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
}
