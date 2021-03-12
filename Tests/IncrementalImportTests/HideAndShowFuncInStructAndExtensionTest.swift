//===-- HideAndShowFuncInStructAndExtensionTests.swift - Swift Testing ----===//
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
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions

import IncrementalTestFramework

/// Add and remove function in imported struct and in imported extension of imported struct.
class HideAndShowFuncInStructAndExtensionTests: XCTestCase {
  func testHideAndShowFuncInStructAndExtension() throws {

    // MARK: - Define imported module
    let imported = Source(named: "imported", containing: """
        // Just for fun, a protocol, as well as the struc with the optional specific func.
        public protocol PP {}
        public struct S: PP {
          public init() {}
          // Optionally expose a specific function in the structure
          //# publicInStruct public
          static func inStruct(_ i: Int) {print("1: private")}
          func fo() {}
        }
        public struct T {
          public init() {}
          public static func bar(_ s: String) {print(s)}
        }
        extension S {
        // Optionally expose a specific function in the extension
        //# publicInExtension public
        static func inExtension(_ i: Int) {print("2: private")}
        }
        """)

    let importedModule = Module(named: "importedModule",
                                containing: [imported],
                                producing: .library)

    // MARK: - Define the main module

    let instantiatesS = Source(named: "instantiatesS", containing:  """
        // Instantiate S
        import \(importedModule.name)
        func late() { _ = S() }
        """)

    let callFunctionInExtension = Source(named: "callFunctionInExtension", containing: """
        // Call the function defined in an extension
        import \(importedModule.name)
        func fred() { S.inExtension(3) }
        """)

    let noUseOfS = Source(named: "noUseOfS", containing: """
        /// Call a function in an unchanging struct
        import \(importedModule.name)
        func baz() { T.bar("asdf") }
        """)

    let main = Source(named: "main", containing: """
        /// Extend S with general functions
        import \(importedModule.name)
        extension S {
          static func inStruct<I: SignedInteger>(_ si: I) {
            print("1: not public")
          }
          static func inExtension<I: SignedInteger>(_ si: I) {
            print("2: not public")
          }
        }
        S.inStruct(3)
        """)

    let mainModule = Module(named: "mainModule",
                            containing: [instantiatesS,
                                         callFunctionInExtension,
                                         noUseOfS,
                                         main],
                            importing: [importedModule],
                            producing: .executable)

    // MARK: - Define the test

    let modules = [importedModule, mainModule]

    let addOrRmInStruct = ExpectedCompilations(
      always: [callFunctionInExtension, imported, instantiatesS, main],
      andWhenDisabled: [noUseOfS])

    // Interestingly, changes to the imported extension do not change the
    /// structure's instantiation. (Compare to above.)
    let addOrRmInExt = ExpectedCompilations(
      always: [callFunctionInExtension, imported, main],
      andWhenDisabled: [instantiatesS, noUseOfS])

    let addOrRmBoth = addOrRmInStruct

    let steps = [
      Step(          compiling: modules),
      Step(adding: "publicInStruct"                     , compiling: modules, expecting: addOrRmInStruct),
      Step(                                               compiling: modules, expecting: addOrRmInStruct),
      Step(adding: "publicInExtension"                  , compiling: modules, expecting: addOrRmInExt   ),
      Step(                                               compiling: modules, expecting: addOrRmInExt   ),
      Step(adding: "publicInStruct", "publicInExtension", compiling: modules, expecting: addOrRmBoth    ),
      Step(                                               compiling: modules, expecting: addOrRmBoth    ),
      Step(adding: "publicInStruct"                     , compiling: modules, expecting: addOrRmInStruct),
      Step(adding:                   "publicInExtension", compiling: modules, expecting: addOrRmInStruct),
      Step(adding: "publicInStruct"                     , compiling: modules, expecting: addOrRmInStruct),
      Step(adding: "publicInStruct", "publicInExtension", compiling: modules, expecting: addOrRmInExt   ),
      Step(adding:                   "publicInExtension", compiling: modules, expecting: addOrRmInStruct),
      Step(adding: "publicInStruct", "publicInExtension", compiling: modules, expecting: addOrRmInStruct),
    ]

    try IncrementalTest.perform(steps)
  }
}




