//===-------------- ClassExtensionTest.swift - Swift Testing --------------===//
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
import SwiftOptions
import IncrementalTestFramework

/// Test what happens when adding a function in an extension to a class and a struct.
class AddFuncInImportedExtensionTest: XCTestCase {

  func testAddFuncInImportedExtension() throws {

    // MARK: - Define sources & imported module
    let definer = Source(named: "definer", containing: """
        // Define a class and a struct
        open class C {public init() {}}
        public struct S {public init() {}}
        """)
    let structExtension = Source( named: "structExtension", containing: """
        // Extend the struct, possibly with an additional function.
        public extension S{
          //# withFunc func foo() {}
        }
        """)
    let  classExtension = Source( named:  "classExtension", containing: """
        // Extend the class, possibly with an additional function.
        public extension C{
          //# withFunc func foo() {}
        }
        """)

    let importedModule = Module(
      named: "ImportedModule",
      containing: [definer, structExtension, classExtension],
      producing: .library)

    // MARK: - Define main module
    let structConstructor = Source(named: "structConstructor", containing: """
      // Instantiate the struct
      import ImportedModule
      func su() {_ = S()}
      """)
    let  classConstructor = Source(named:  "classConstructor", containing: """
      /// Instantiate the class
      import ImportedModule
      func cu() {_ = C()}
      """)

    let mainFile = Source(named: "main", containing: "")

    let mainModule = Module(
      named: "main",
      containing: [mainFile, structConstructor, classConstructor],
      importing: [importedModule],
      producing: .executable)

    // MARK: - Define the test

    // Define module ordering & what to compile
    let modules = [importedModule, mainModule]

    // Define what is expected
    let whenAddOrRmFunc = ExpectedCompilations(
      expected: [structExtension, classExtension, ])

    let steps = [
      Step(                    building: modules, .expecting(modules.allSourcesToCompile)),
      Step(                    building: modules, .expecting(.none)),
      Step(adding: "withFunc", building: modules, .expecting(whenAddOrRmFunc)),
      Step(                    building: modules, .expecting(whenAddOrRmFunc)),
      Step(adding: "withFunc", building: modules, .expecting(whenAddOrRmFunc)),
    ]

    // Do the test
    try IncrementalTest.perform(steps)
  }
}
