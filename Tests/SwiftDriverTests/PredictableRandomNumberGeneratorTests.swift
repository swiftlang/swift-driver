//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Testing
@_spi(Testing) import SwiftDriver

/// This generator is deterministic and platform independent, so the sequence for each seed should remain constant.
@Suite struct PredictableRandomNumberGeneratorTests {
  @Test func predictability() {
    var generator = PredictableRandomNumberGenerator(seed: 42)
    #expect([generator.next(), generator.next(), generator.next(),
                    generator.next(), generator.next()] ==
                   [1546998764402558742, 6990951692964543102,
                    12544586762248559009, 17057574109182124193,
                    18295552978065317476])

    var generator2 = PredictableRandomNumberGenerator(seed: 42)
    #expect([generator2.next(), generator2.next(), generator2.next(),
                    generator2.next(), generator2.next()] ==
                   [1546998764402558742, 6990951692964543102,
                    12544586762248559009, 17057574109182124193,
                    18295552978065317476])
  }

  @Test func unusualSeeds() {
    var generator = PredictableRandomNumberGenerator(seed: 0)
    #expect([generator.next(), generator.next(), generator.next(),
                    generator.next(), generator.next()] ==
                   [11091344671253066420, 13793997310169335082,
                    1900383378846508768, 7684712102626143532,
                    13521403990117723737])

    var generator2 = PredictableRandomNumberGenerator(seed: 0xFFFFFFFFFFFFFFFF)
    #expect([generator2.next(), generator2.next(), generator2.next(),
                    generator2.next(), generator2.next()] ==
                   [10328197420357168392, 14156678507024973869,
                    9357971779955476126, 13791585006304312367,
                    10463432026814718762])
  }
}
