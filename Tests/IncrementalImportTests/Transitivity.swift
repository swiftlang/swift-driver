//===---------------- Transitivity.swift - Swift Testing ------------------===//
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

// This test establishes a "transitive" chain of modules that import one another
// and ensures that a cross-module incremental build rebuilds all modules
// involved in the chain.
//
// Module C    Module B    Module A
// -------- -> -------- -> --------
//    |                        ^
//    |                        |
//    -------------------------
class TransitivityTest: XCTestCase {
  func testTransitiveTopLevelUses() throws {
    try IncrementalTest.perform([
      // Build a baseline
      Step(adding: "transitive-baseline",
           building: [.C, .B, .A],
           .expecting([.C, .B, .A].allSourcesToCompile)),
      // Swap in a new default argument: B needs to rebuild `fromB` and
      // relink against fromC, but A doesn't import `C` so only non-incremental
      // imports rebuilds it.
      Step(adding: "transitive-add-default",
           building: [.C, .B, .A],
           .expecting(.init(expected: [.C, .B]))),
      // Now change C back to the old baseline. We edit A in the process to
      // introduce a dependency on C, so it needs to rebuild.
      Step(adding: "transitive-baseline", "transitive-add-use-in-A",
           building: [.C, .B, .A],
           .expecting(.init(expected: [.C, .B, .A]))),
      // Same as before - the addition of a default argument requires B rebuild,
      // but A doesn't use anything from C, so it doesn't rebuild unless
      // incremental imports are disabled.
      Step(adding: "transitive-add-default", "transitive-add-use-in-A",
           building: [.C, .B, .A],
           .expecting(.init(expected: [.C, .B]))),
    ])
  }

  func testTransitiveStructMember() throws {
    try IncrementalTest.perform([
      // Establish the baseline build
      Step(adding: "transitive-baseline",
           building: [.C, .B, .A],
           .expecting(.init(expected: [ .A, .B, .C ]))),
      // Add the def of a struct to C, which B imports and has a use of so
      // B rebuilds but A does not unless incremental imports are disabled.
      Step(adding: "transitive-baseline", "transitive-struct-def-in-C",
           building: [.C, .B, .A],
           .expecting(.init(expected: [ .B, .C ]))),
      // Now add a use in B, make sure C doesn't rebuild.
      Step(adding: "transitive-baseline", "transitive-struct-def-in-C", "transitive-struct-def-in-B",
           building: [.C, .B, .A],
           .expecting(.init(expected: [ .B, ]))),
      // Now add a use in A and make sure only A rebuilds.
      Step(adding: "transitive-baseline", "transitive-struct-def-in-C", "transitive-struct-def-in-B", "transitive-struct-def-in-A",
           building: [.C, .B, .A],
           .expecting(.init(expected: [ .A ]))),
      // Finally, add a member to a struct in C, which influences the layout of
      // the struct in B, which influences the layout of the struct in A.
      // Everything rebuilds!
      Step(adding: "transitive-baseline", "transitive-struct-add-member-in-C", "transitive-struct-def-in-B", "transitive-struct-def-in-A",
           building: [.C, .B, .A],
           .expecting(.init(expected: [ .A, .B, .C ]))),
    ])
  }
}

fileprivate extension Module {
  static var A = Module(named: "A", containing: [
    .A,
  ], importing: [
    .B, .C,
  ], producing: .executable)

  static var B = Module(named: "B", containing: [
    .B,
  ], importing: [
    .C
  ], producing: .library)

  static var C = Module(named: "C", containing: [
    .C,
  ], producing: .library)
}

fileprivate extension Source {
  static var A: Source {
    Self(
    named: "A",
    containing: """
                import B

                //# transitive-add-use-in-A import C
                //# transitive-add-use-in-A public func fromA() {
                //# transitive-add-use-in-A   return fromB()
                //# transitive-add-use-in-A }

                //# transitive-struct-def-in-A import C
                //# transitive-struct-def-in-A struct AStruct { var b: BStruct }
                """)
  }
}

fileprivate extension Source {
  static var B: Source {
    Self(
    named: "B",
    containing: """
                import C

                public func fromB() {
                  return fromC()
                }

                //# transitive-struct-def-in-B public struct BStruct { var c: CStruct }
                """)
  }
}

fileprivate extension Source {
  static var C: Source {
    Self(
    named: "C",
    containing: """
                //# transitive-baseline public func fromC() {}
                //# transitive-add-default public func fromC(parameter: Int = 0) {}

                //# transitive-struct-def-in-C public struct CStruct {  }
                //# transitive-struct-add-member-in-C public struct CStruct { var x: Int }
                """)
  }
}
