//===---------------- Antisymmetry.swift - Swift Testing ------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import IncrementalTestFramework

// This test establishes an "antisymmetric" chain of modules that import one
// another and ensures that rebuilds propagate in one direction.
//
// Module B    Module A
// -------- -> --------
//    ^          x
//    |          |
//    ----XXX-----
class AntisymmetryTest: XCTestCase {
  private let defAdditions = [
    "b-add-struct",
    "b-add-class",
    "b-add-protocol",
    "b-add-extension",
  ]

  private let useAdditions = [
    "use-struct",
    "use-class",
    "use-protocol",
    "use-extension",
  ]

  func testAntisymmetricTopLevelDefs() throws {
    try IncrementalTest.perform([
      // The baseline step is special, we want everything to get built first.
      Step(adding: defAdditions,
           building: [ .B, .A ],
           .expecting(.init(expected: [ .main, .B ])))
    ] + defAdditions.dropFirst().indices.map { idx in
      // Make sure the addition of defs without users only causes cascading
      // rebuilds when incremental imports are disabled.
      Step(adding: Array(defAdditions[0..<idx]),
           building: [ .B, .A ],
           .expecting(.init(expected: [ .B ])))
    })
  }

  func testAntisymmetricTopLevelUses() throws {
    try IncrementalTest.perform([
      // The baseline step is special, we want everything to get built first.
      Step(adding: defAdditions,
           building: [ .B, .A ],
           .expecting(.init(expected: [ .main, .B ])))
    ] + useAdditions.indices.dropFirst().map { idx in
      // Make sure the addition of uses causes only users to recompile.
      Step(adding: defAdditions + Array(useAdditions[0..<idx]),
           building: [ .B, .A ],
           .expecting(.init(expected: [ .main ])))
    })
  }
}

fileprivate extension Module {
  static var A = Module(named: "A", containing: [
    .main,
  ], importing: [
    .B,
  ], producing: .executable)

  static var B = Module(named: "B", containing: [
    .B,
  ], producing: .library)
}

fileprivate extension Source {
  static var main: Source {
    Self(
    named: "main",
    containing: """
                import B

                //# use-struct _ = BStruct()
                //# use-class _ = BClass()
                //# use-protocol extension BStruct: BProtocol { public func foo(parameter: Int = 0) {} }
                //# use-extension BStruct().foo()
                """)
  }
}

fileprivate extension Source {
  static var B: Source {
    Self(
    named: "B",
    containing: """
                //# b-add-struct public struct BStruct { public init() {} }
                //# b-add-class public class BClass { public init() {} }
                //# b-add-protocol public protocol BProtocol {}
                //# b-add-extension extension BStruct { public func foo() {} }
                """)
  }
}
