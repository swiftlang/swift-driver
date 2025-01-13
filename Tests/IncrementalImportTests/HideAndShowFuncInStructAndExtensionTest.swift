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
/// This is a very complicated test, so it is built programmatically.
class HideAndShowFuncInStructAndExtensionTests: XCTestCase {
  func testHideAndShowFuncInStructAndExtension() throws {
    try IncrementalTest.perform(steps)
  }
}

/// The changes to be tested
fileprivate let stepChanges: [[Change]] = [
  [],
  [],
  [.exposeFuncInStruct],
  [],
  [.exposeFuncInExtension],
  [],
  Change.allCases,
  [],
  [.exposeFuncInStruct],
  [.exposeFuncInExtension],
  [.exposeFuncInStruct],
  Change.allCases,
  [.exposeFuncInExtension],
  Change.allCases
]


// MARK: - Reify the source changes

fileprivate enum Change: String, CustomStringConvertible, CaseIterable {
  /// Make the imported specific method defined in a structure public
  case exposeFuncInStruct

  /// Make the imported specific method defined in an extension public
  case exposeFuncInExtension

  var name: String {rawValue}
  var description: String {name}
}

// MARK: - Define imported module
fileprivate let imported = Source(named: "imported", containing: """
        // Just for fun, a protocol, as well as the struct with the optional specific func.
        public protocol PP {}
        public struct S: PP {
          public init() {}
          // Optionally expose a specific function in the structure
          //# \(Change.exposeFuncInStruct) public
          static func inStruct(_ i: Int) {print("specific in struct")}
          func fo() {}
        }
        public struct T {
          public init() {}
          public static func bar(_ s: String) {print(s)}
        }
        extension S {
        // Optionally expose a specific function in the extension
        //# \(Change.exposeFuncInExtension) public
        static func inExtension(_ i: Int) {print("specific in extension")}
        }
        """)

fileprivate let importedModule = Module(named: "importedModule",
                                        containing: [imported],
                                        producing: .library)

// MARK: - Define the main module

fileprivate let instantiatesS = Source(named: "instantiatesS", containing:  """
        // Instantiate S
        import \(importedModule.name)
        func late() { _ = S() }
        """)

fileprivate let callFunctionInExtension = Source(named: "callFunctionInExtension", containing: """
        // Call the function defined in an extension
        import \(importedModule.name)
        func fred() { S.inExtension(3) }
        """)

fileprivate let noUseOfS = Source(named: "noUseOfS", containing: """
        /// Call a function in an unchanging struct
        import \(importedModule.name)
        func baz() { T.bar("asdf") }
        """)

fileprivate let main = Source(named: "main", containing: """
        /// Extend S with general functions
        import \(importedModule.name)
        extension S {
          static func inStruct<I: SignedInteger>(_ si: I) {
            print("general in struct")
          }
          static func inExtension<I: SignedInteger>(_ si: I) {
            print("general in extension")
          }
        }
        S.inStruct(3)
        S.inExtension(4)
        """)

fileprivate let mainModule = Module(named: "mainModule",
                                    containing: [instantiatesS,
                                                 callFunctionInExtension,
                                                 noUseOfS,
                                                 main],
                                    importing: [importedModule],
                                    producing: .executable)

// MARK: - Define the whole app
fileprivate let modules = [importedModule, mainModule]

// MARK: - Compute the expectations
fileprivate extension Change {
  var expectedCompilationsWithIncrementalImports: [Source] {
    switch self {
    case .exposeFuncInStruct:    return [callFunctionInExtension, imported, instantiatesS, main]
    case .exposeFuncInExtension: return [callFunctionInExtension, imported,                main]
    }
  }

  var locusOfExposure: String {
    switch self {
    case .exposeFuncInStruct:    return "struct"
    case .exposeFuncInExtension: return "extension"
    }
  }
  static var allLociOfExposure: [String] {
    allCases.map {$0.locusOfExposure}
  }
}

// MARK: - Building a step from combinations of Changes
fileprivate extension Array where Element == Change {
  var addOns: [String] {map {$0.name} }

  func expectedCompilations(_ prevStep: Step?) -> ExpectedCompilations {
    guard let prevStep = prevStep else {
      return modules.allSourcesToCompile
    }
    let deltas = Set(map{$0.name}).symmetricDifference(prevStep.addOns.map{$0.name})
      .map {Change.init(rawValue: $0)!}

    let expectedCompilationsWithIncrementalImports: [Source] =
      deltas.reduce(into: Set<Source>()) {sources, change in
        sources.formUnion(change.expectedCompilationsWithIncrementalImports)
      }
      .sorted()

    return ExpectedCompilations(expected: Set(expectedCompilationsWithIncrementalImports))
  }

  var expectedOutput: ExpectedProcessResult {
#if os(Windows)
      let eol = "\r\n"
#else
      let eol = "\n"
#endif

    let specOrGen = Change.allCases.map {
      contains($0) ? "specific" : "general"
    }
    let output = zip(specOrGen, Change.allLociOfExposure)
      .map { "\($0.0) in \($0.1)"}
      .joined(separator: eol)
    return ExpectedProcessResult(output: output)
  }

  func step(prior: Step?) -> Step {
    Step(adding: addOns,
         building: modules,
         .expecting(expectedCompilations(prior), expectedOutput))
  }
}
// MARK: - All steps

var steps: [Step] {
  stepChanges.reduce(into: []) { steps, changes in
    steps.append(changes.step(prior: steps.last))
  }
}
