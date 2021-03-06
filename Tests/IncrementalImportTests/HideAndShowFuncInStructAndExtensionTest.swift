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

class HideAndShowFuncInStructAndExtensionTests: XCTestCase {
  func testHideAndShowFuncInStruct() throws {
    try HideAndShowFunc<InStructStep>.test()
  }
  func testHideAndShowFuncInExtension() throws {
    try HideAndShowFunc<InExtensionStep>.test()
  }
  func testHideAndShowFuncInBoth() throws {
    try HideAndShowFunc<BothStep>.test()
  }
}

fileprivate struct HideAndShowFunc<Step: HideAndShowStep>: TestProtocol {
  static var start: Step.State { HideAndShowFuncState.bothHidden as! Step.State }
  static var steps: [Step] { [.show, .hide, .show] }
}

fileprivate protocol HideAndShowStep: StepProtocol {
  associatedtype State = HideAndShowFuncState
  static var show: Self {get}
  static var hide: Self {get}
}


fileprivate enum InStructStep: String, HideAndShowStep {
  case hide, show

  var nextState: State {
    switch self {
    case .hide: return .bothHidden
    case .show: return .shownInStruct
    }
  }
  var expecting: Expectation<SourceVersion> { nextState.commonExpectations }
}

fileprivate enum InExtensionStep: String, HideAndShowStep {
  case hide, show

  var nextState: State {
    switch self {
    case .hide: return .bothHidden
    case .show: return .shownInExtension
    }
  }
  var expecting: Expectation<SourceVersion> { nextState.commonExpectations }
}


fileprivate enum BothStep: String, HideAndShowStep {
  case hide, show

  var nextState: State {
    switch self {
    case .hide: return .bothHidden
    case .show: return .bothShown
    }
  }
  var expecting: Expectation<SourceVersion> { nextState.commonExpectations }
}


fileprivate enum HideAndShowFuncState: String, StateProtocol {
  case bothHidden, shownInStruct, shownInExtension, bothShown

  var jobs: [BuildJob<Module>] {
    let importedSourceVersion: SourceVersion
    switch self {
    case .bothHidden:        importedSourceVersion = .importedWithoutPublicFuncs
    case .shownInStruct:     importedSourceVersion = .importedFileWithPublicFuncInStruct
    case .shownInExtension:  importedSourceVersion = .importedFileWithPublicFuncInExtension
    case .bothShown:         importedSourceVersion = .importedFileWithPublicFuncInStructAndExtension
    }
    let  subJob = BuildJob<Module>(.importedModule, [importedSourceVersion])
    let mainJob = BuildJob<Module>(.mainModule,
                                            [.definesGeneralFuncsAndCallsFuncInStruct,
                                             .noUseOfS,
                                             .callsFuncInExtension,
                                             .instantiatesS])
    return [subJob, mainJob]
  }
}


fileprivate extension HideAndShowFuncState {
  var commonExpectations: Expectation<Module.SourceVersion> {
    Expectation(with: [.definesGeneralFuncsAndCallsFuncInStruct,
                       .callsFuncInExtension,
                       .instantiatesS,
                       .importedWithoutPublicFuncs],
                without: allInputs)
  }
}

fileprivate extension HideAndShowFuncState {
  enum Module: String, ModuleProtocol {
    case importedModule, mainModule

    var imports: [Self] {
      switch self {
      case .importedModule:  return []
      case .mainModule:      return [.importedModule]
      }
    }

    var isLibrary: Bool {
      switch self {
      case .importedModule: return true
      case .mainModule:      return false
      }
    }
  }
}

fileprivate extension HideAndShowFuncState.Module {
  enum SourceVersion: String, SourceVersionProtocol {
    typealias Module = HideAndShowFuncState.Module

    case importedWithoutPublicFuncs,
         importedFileWithPublicFuncInStruct,
         importedFileWithPublicFuncInExtension,
         importedFileWithPublicFuncInStructAndExtension,
         definesGeneralFuncsAndCallsFuncInStruct,
         noUseOfS,
         callsFuncInExtension,
         instantiatesS

    var fileName: String {
      switch self {
      case .importedWithoutPublicFuncs,
           .importedFileWithPublicFuncInStruct,
           .importedFileWithPublicFuncInExtension,
           .importedFileWithPublicFuncInStructAndExtension:
        return "importedFile"
      case .definesGeneralFuncsAndCallsFuncInStruct: return "main"
      default: return name
      }
    }

    var code: String {
      switch self {
      case .definesGeneralFuncsAndCallsFuncInStruct: return """
                  import \(Module.importedModule.nameToImport)
                  extension S {
                    static func inStruct<I: SignedInteger>(_ si: I) {
                      print("1: not public")
                    }
                    static func inExtension<I: SignedInteger>(_ si: I) {
                      print("2: not public")
                    }
                  }
                  S.inStruct(3)
    """
      case .noUseOfS: return """
                  import \(Module.importedModule.nameToImport)
                  func baz() { T.bar("asdf") }
    """
      case .callsFuncInExtension: return """
                  import \(Module.importedModule.nameToImport)
                  func fred() { S.inExtension(3) }
      """
      case .instantiatesS: return """
                 import \(Module.importedModule.nameToImport)
                 func late() { S() }
    """
      case .importedWithoutPublicFuncs: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    // public // was commented out; should rebuild users of inStruct
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   // public
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
    """
      case .importedFileWithPublicFuncInStruct: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    public // was uncommented out; should rebuild users of inStruct
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   // public
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
    """
      case .importedFileWithPublicFuncInExtension: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    // public // was commented out; should rebuild users of inStruct
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   // public
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
      """
      case .importedFileWithPublicFuncInStructAndExtension: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    public
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   public  // was uncommented; should rebuild users of inExtension
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
    """
      }
    }
  }
}
