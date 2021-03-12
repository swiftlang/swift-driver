//===------ ExtensionChangeWithinModuleTests.swift - Swift Testing --------===//
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
import IncrementalTestFramework

@_spi(Testing) import SwiftDriver
import SwiftOptions

/// Try adding a more specific function in an extension in the same module
class SpecificFuncAdditionInExtensionWithinModuleTest: XCTestCase {
  func testSpecificFuncAdditionInExtensionWithinModule() throws {
    
    // MARK: - Define the module
    let main = Source(named: "main", containing: """
      // Define a struct with a general method and call it
      struct S {static func foo<I: SignedInteger>(_ si: I) {}}
      S.foo(3)
      """)
    let sExtension = Source(named: "sExtension", containing: """
      // Extend the structure and optionally add a specific method
      extension S {
        //# withFunc static func foo(_ i: Int) {}
      }
      // Also define a structure that won't be changed.
      struct T {static func foo() {}}
      """)
    let userOfT = Source(named: "userOfT", containing: """
      // Use the unchanging structure
      func baz() {T.foo()}
      """)
    let instantiator = Source(named: "instantiator", containing: """
      /// Instantiate the changing structure
      func bar() {_ = S()}
      """)

    let mainModule = Module(named: "mainM",
                            containing: [main, sExtension, userOfT, instantiator],
                            producing: .executable)

    let whenAddOrRmSpecificFunc = ExpectedCompilations(always: [main, sExtension],
                                                       andWhenDisabled: [])
    let steps = [
      Step(                    compiling: [mainModule]),
      Step(                    compiling: [mainModule], expecting: .none),
      Step(adding: "withFunc", compiling: [mainModule], expecting: whenAddOrRmSpecificFunc),
      Step(                    compiling: [mainModule], expecting: whenAddOrRmSpecificFunc),
      Step(adding: "withFunc", compiling: [mainModule], expecting: whenAddOrRmSpecificFunc),
    ]

    try IncrementalTest.perform(steps)
  }
}

/// Try fileprivate extension style
fileprivate extension Source {
  static var main: Source {
    Self(
    named: "main",
    containing: """
            struct S {static func foo<I: SignedInteger>(_ si: I) {}}
            S.foo(3)
            """)
  }
}

