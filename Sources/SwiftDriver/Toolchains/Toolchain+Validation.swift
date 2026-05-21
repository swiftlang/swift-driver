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

import SwiftOptions

import class TSCBasic.DiagnosticsEngine

extension Toolchain {
  /// Emit the standard `-Xemcc-linker` "wrong target" warning for any
  /// non-Emscripten toolchain. Call from each non-Emscripten toolchain's
  /// `validateArgs` so the diagnostic surfaces uniformly.
  ///
  /// `parsedOptions` is `inout` because `ParsedOptions.arguments(for:)` is
  /// `mutating` (it consumes lookup state on the underlying parser).
  internal func warnIfEmccLinkerArgs(
    _ parsedOptions: inout ParsedOptions,
    diagnosticsEngine: DiagnosticsEngine
  ) {
    for arg in parsedOptions.arguments(for: .XemccLinker) {
      diagnosticsEngine.emit(
        .warning_xemcc_linker_unsupported_for_non_emscripten(arg.argument.asSingle))
    }
  }
}
