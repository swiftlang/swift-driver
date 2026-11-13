//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Dispatch.DispatchTime

@_spi(Testing) public enum TraceClock {

  /// The current time in microseconds on the machine clock.
  ///
  /// Abstracting `TraceClock` helps ensure data of separate, constituent
  /// process traces can combine their data into one larger trace with
  /// consistent time.
  public static func now() -> Int64 {
    Int64(DispatchTime.now().uptimeNanoseconds / 1_000)
  }
}
