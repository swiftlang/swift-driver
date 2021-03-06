import Foundation
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

@_spi(Testing) import SwiftDriver
import SwiftOptions

class ExtensionChangeWithinModuleTests: XCTestCase {
  func testExtensionChangeWithinModule() throws {
    try ExtensionChange.test()
  }
}

fileprivate struct ExtensionChange: TestProtocol {
  static let start: State = .noFunc
  static let steps: [Step<State>] = [
    Step(.withFunc, expectedCompilations),
    Step(.noFunc,   expectedCompilations),
    Step(.withFunc, expectedCompilations),
  ]
  static var expectedCompilations: Expectation<SourceVersion> =
    Expectation(with: [.main, .noFunc, .instantiator], without: [.main, .noFunc, .instantiator, .userOfT])


  enum State: String, StateProtocol {
    case noFunc, withFunc

    var jobs: [BuildJob<Module>] {
      switch self {
      case   .noFunc: return [BuildJob(.mainM, [.main,   .noFunc, .instantiator])]
      case .withFunc: return [BuildJob(.mainM, [.main, .withFunc, .instantiator])]
      }
    }
  }

  enum Module: String, ModuleProtocol {
    typealias SourceVersion = ExtensionChange.SourceVersion
    case mainM

    var imports: [Self] { return [] }
    var isLibrary: Bool { false }
  }

  enum SourceVersion: String, SourceVersionProtocol {
    case main, noFunc, withFunc, instantiator, userOfT

    var fileName: String {
      switch self {
      case .noFunc, .withFunc: return "extensionHolder"
      default:                 return name
      }
    }

    var code: String {
      switch self {
      case .main: return """
        struct S { static func foo<I: SignedInteger>(_ si: I) {} }
        S.foo(3)
        """
      case .noFunc: return """
        extension S {}
        struct T {static func foo() {}}
        """
      case .withFunc: return """
        extension S { static func foo(_ i: Int) {} }
        struct T {static func foo() {}}
        """
      case .instantiator: return "func bar() {S()}"
      case .userOfT: return "func baz() {T.foo()}"
      }
    }
  }
}

