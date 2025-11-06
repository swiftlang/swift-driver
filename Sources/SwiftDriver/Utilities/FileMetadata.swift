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

public struct FileMetadata {
    public let mTime: TimePoint
    public let hash: String?
    init(mTime: TimePoint, hash: String? = nil) {
        self.mTime = mTime
        if let hash = hash, !hash.isEmpty {
          self.hash = hash
        } else {
          self.hash = nil
        }
    }
}

