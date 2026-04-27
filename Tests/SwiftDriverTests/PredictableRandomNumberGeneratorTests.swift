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

@_spi(Testing) import SwiftDriver
import Testing

/// This generator is deterministic and platform independent, so the sequence for each seed should remain constant.
@Suite struct PredictableRandomNumberGeneratorTests {
  @Test func predictability() {
    var generator = PredictableRandomNumberGenerator(seed: 42)
    #expect(
      [
        generator.next(), generator.next(), generator.next(),
        generator.next(), generator.next(),
      ] == [
        1_546_998_764_402_558_742, 6_990_951_692_964_543_102,
        12_544_586_762_248_559_009, 17_057_574_109_182_124_193,
        18_295_552_978_065_317_476,
      ]
    )

    var generator2 = PredictableRandomNumberGenerator(seed: 42)
    #expect(
      [
        generator2.next(), generator2.next(), generator2.next(),
        generator2.next(), generator2.next(),
      ] == [
        1_546_998_764_402_558_742, 6_990_951_692_964_543_102,
        12_544_586_762_248_559_009, 17_057_574_109_182_124_193,
        18_295_552_978_065_317_476,
      ]
    )
  }

  @Test func unusualSeeds() {
    var generator = PredictableRandomNumberGenerator(seed: 0)
    #expect(
      [
        generator.next(), generator.next(), generator.next(),
        generator.next(), generator.next(),
      ] == [
        11_091_344_671_253_066_420, 13_793_997_310_169_335_082,
        1_900_383_378_846_508_768, 7_684_712_102_626_143_532,
        13_521_403_990_117_723_737,
      ]
    )

    var generator2 = PredictableRandomNumberGenerator(seed: 0xFFFF_FFFF_FFFF_FFFF)
    #expect(
      [
        generator2.next(), generator2.next(), generator2.next(),
        generator2.next(), generator2.next(),
      ] == [
        10_328_197_420_357_168_392, 14_156_678_507_024_973_869,
        9_357_971_779_955_476_126, 13_791_585_006_304_312_367,
        10_463_432_026_814_718_762,
      ]
    )
  }
}
