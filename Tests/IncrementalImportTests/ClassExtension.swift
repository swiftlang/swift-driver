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

@_spi(Testing) import SwiftDriver
import SwiftOptions

/// Shows that adding a class method in an extension in a submodule causes the user importing the class
/// to get recompiled, but not for a struct.
class ClassExtensionTest: XCTestCase {
  func testClassExtension() throws {
    try Test.test()
  }
  struct Test: TestProtocol {
    static let start: State = .withoutFunc
    static let steps: [Step<State>] = [
      Step(.withFunc,    expectedCompilations),
      Step(.withoutFunc, expectedCompilations),
      Step(.withFunc,    expectedCompilations),
    ]

    static let expectedCompilations = Expectation<SourceVersion>(
      with:    [.classUser, .withStructFunc, .withClassFunc],
      without: [.classUser, .withStructFunc, .withClassFunc, .structUser])

    enum State: String, StateProtocol {
      case withFunc, withoutFunc
      var jobs: [BuildJob<Module>] {
        let importedVersions: [SourceVersion]
        switch self {
        case .withFunc: importedVersions = [.withStructFunc, .withClassFunc]
        case .withoutFunc: importedVersions = [.withoutStructFunc, .withoutClassFunc]
        }
        return [BuildJob(.imported, importedVersions + [.definer]),
                BuildJob(.main, [.classUser, .structUser])]
      }
    }

    enum Module: String, ModuleProtocol {
      typealias SourceVersion = Test.SourceVersion

      case main, imported

      var imports: [Self] {
        switch self {
        case .main:     return [.imported]
        case .imported: return []
        }
      }
      var isLibrary: Bool {
        switch self {
        case .main:     return false
        case .imported: return true
        }
      }
    }


    enum SourceVersion: String, SourceVersionProtocol {
      case classUser, structUser,
          withStructFunc, withoutStructFunc, withClassFunc, withoutClassFunc,
          definer
      
      var fileName: String {
        switch self {
        case .withStructFunc, .withoutStructFunc: return "structFuncDef"
        case .withClassFunc,  .withoutClassFunc:  return "classFuncDef"
        default: return name
        }
      }
      var code: String {
        switch self {
        case .structUser: return "import \(Module.imported.nameToImport); func su() {S()}"
        case .classUser:  return "import \(Module.imported.nameToImport); func cu() {C()}"
        case .withStructFunc:    return "public extension S { func foo() {} }"
        case .withClassFunc:     return "public extension C { func foo() {} }"
        case .withoutStructFunc: return "public extension S{}"
        case .withoutClassFunc:  return "public extension C{}"
        case .definer: return """
          open class C {public init() {}}
          public struct S {public init() {}}
          """
        }
      }
    }
  }
}
