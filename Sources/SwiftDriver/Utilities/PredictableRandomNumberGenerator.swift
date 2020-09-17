//===------------ PredictableRandomNumberGenerator.swift ------------------===//
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

/// An _insecure_ random number generator which given an initial seed will generate a _predictable_
/// sequence of pseudo-random numbers. This generator is not thread safe.
///
/// The generator uses the [xoshiro256**](http://prng.di.unimi.it/xoshiro256starstar.c)
/// algorithm to produce its output. It is initialized using the
/// [splitmix64](http://prng.di.unimi.it/splitmix64.c) algorithm.
@_spi(Testing) public struct PredictableRandomNumberGenerator: RandomNumberGenerator {

  var state: (UInt64, UInt64, UInt64, UInt64)

  public init(seed: UInt64) {
    func initNext(_ state: inout UInt64) -> UInt64 {
      state = state &+ 0x9e3779b97f4a7c15
      var z = state
      z = (z ^ (z &>> 30)) &* 0xbf58476d1ce4e5b9
      z = (z ^ (z &>> 27)) &* 0x94d049bb133111eb
      return z ^ (z &>> 31)
    }

    var initState = seed
    state = (initNext(&initState), initNext(&initState),
             initNext(&initState), initNext(&initState))
  }

  mutating public func next() -> UInt64 {
    defer {
      let t = state.1 &<< 17
      state.2 ^= state.0
      state.3 ^= state.1
      state.1 ^= state.2
      state.0 ^= state.3
      state.2 ^= t
      state.3 = state.3.rotateLeft(45)
    }
    return (state.1 &* 5).rotateLeft(7) &* 9
  }
}

fileprivate extension UInt64 {
  func rotateLeft(_ numBits: UInt8) -> UInt64 {
    return (self &<< numBits) | (self &>> (64 - numBits))
  }
}
