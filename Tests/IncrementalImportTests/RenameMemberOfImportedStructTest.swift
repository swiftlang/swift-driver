//===--------------- IncrementalImportTests.swift - Swift Testing ---------===//
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


/// Rename an imported member  and see that non-users of the struct are not recompiled.
class RenameMemberOfImportedStructTest: XCTestCase {
  func testRenamingMember() throws {

    // MARK: - Define the imported module

    let memberDefiner = Source(named: "memberDefiner", containing: """
        // Define the structure
        public struct ImportedStruct {
          public init() {}
          public func importedMember() {}
          // Simulate a name change:
          //# original public func nameToBeChanged() {}
          //# renamed  public func wasRenamed() {}
        }
        """)

    let imported = Module(named: "imported",
                          containing: [memberDefiner],
                          producing: .library)

    // MARK: - Define the main module

    let main = Source(named: "main", containing: """
        // Import the structure and use it
        import \(imported.name)
        ImportedStruct().importedMember()
        """)
    let other = Source(named: "other", containing: """
        // Import the module but don't use the imported structure
        import \(imported.name)
        """)

    let mainModule = Module(named: "mainModule",
                            containing: [main, other],
                            importing: [imported],
                            producing: .executable)

    let modules = [imported, mainModule]

    /// Incremental imports save a recompilation.
    let whenRenaming = ExpectedCompilations(expected: [memberDefiner, main])

    let steps = [
      Step(adding: ["original"], building: modules, .expecting(modules.allSourcesToCompile)),
      Step(adding: ["original"], building: modules, .expecting(.none)),
      Step(adding: ["renamed"],  building: modules, .expecting(whenRenaming)),
      Step(adding: ["original"], building: modules, .expecting(whenRenaming)),
      Step(adding: ["renamed"],  building: modules, .expecting(whenRenaming)),
    ]
    try IncrementalTest.perform(steps)
  }
}
