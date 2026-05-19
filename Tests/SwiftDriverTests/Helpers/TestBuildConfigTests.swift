//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Testing

@Suite struct RequireFrontendSupportsTargetTests {
  /// `wasm32-unknown-wasi` is recognized by every toolchain that ships swift-frontend
  /// (it predates emscripten support), so the probe must accept it.
  @Test func probeAcceptsKnownTriple() async throws {
    #expect(probeFrontendForTarget("wasm32-unknown-wasi") == true)
  }

  /// A nonsense OS is never recognized, so the probe must reject it (causing the trait
  /// to skip rather than run).
  @Test func probeRejectsBogusTriple() async throws {
    #expect(probeFrontendForTarget("madeup-unknown-bogusos") == false)
  }
}
