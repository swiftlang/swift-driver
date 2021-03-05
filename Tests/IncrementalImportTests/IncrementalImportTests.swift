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

// MARK: - Test cases
class MultimoduleTests: XCTestCase {
  func testRenamingMember() throws {
    try RenameMemberOfImportedStruct.test()
  }
  func testHideAndShowFuncInStructAndExtension() throws {
//xxx    try HideAndShowFuncInStructAndExtension.test()
  }
}


// MARK: - RenameMemberOfImportedStruct

/// Change the name of a member of an imported struct.
/// Ensure that only the users get rebuilt
fileprivate struct RenameMemberOfImportedStruct: TestProtocol {
  typealias Test = Self

  let withIncrementalImports: Bool
  let testDir: AbsolutePath

  static let start = Phase.initial
  static let steps: [Step] = [.rename, .unrename]
}

fileprivate extension RenameMemberOfImportedStruct {
  enum Step: String, CaseIterable, StepProtocol {

    case rename, unrename
    var to: Phase {
      switch self {
      case .rename: return .renamed
      case .unrename: return .initial
      }
    }
    var expectingWithout: [Source] {to.allOriginals}
    var expectingWith: [Source] {[.mainFile, .importedFile]}
  }
}

fileprivate extension RenameMemberOfImportedStruct {
  enum Module: String, ModuleProtocol {
    // Must be in build order
    case importedModule, mainModule

    var sources: [Source] {
      switch self {
      case .importedModule: return [.importedFile]
      case .mainModule: return [.mainFile, .otherFile]
      }
    }
    var imports: [Module] {
      switch self {
      case .importedModule: return []
      case .mainModule: return [.importedModule]
      }
    }
    var isLibrary: Bool {
      switch self {
      case .importedModule: return true
      case .mainModule: return false
      }
    }
  }
}

fileprivate extension RenameMemberOfImportedStruct {
  enum Source: String, SourceProtocol {

    case mainFile = "main", otherFile, importedFile, renamedMember

    var original: Self {
      switch self {
      case .renamedMember: return .importedFile
      default: return self
      }
    }

    var code: String {
      switch self {
      case .mainFile:
        return """
               import \(Module.importedModule.name)
               ImportedStruct().importedMember()
               """
      case .otherFile:
        return ""
      case .importedFile:
        return """
                  public struct ImportedStruct {
                    public init() {}
                    public func importedMember() {}
                    // change the name below, only mainFile should rebuild:
                    public func nameToBeChanged() {}
                  }
                  """
      case .renamedMember:
        return """
                  public struct ImportedStruct {
                    public init() {}
                    public func importedMember() {}
                    // change the name below, only mainFile should rebuild:
                    public func nameWasChanged() {}
                  }
                  """
      }
    }
  }
}

fileprivate extension RenameMemberOfImportedStruct {
  enum Phase: String, PhaseProtocol {
    case initial, renamed

    var jobs: [CompileJob<Module>] {
      switch self {
      case .initial: return .building(.importedModule, .mainModule)
      case .renamed: return Self.initial.jobs.substituting(.renamedMember)
      }
    }
  }
}


fileprivate extension RenameMemberOfImportedStruct {
}



//  , [.mainFile, .importedFile]),
//              .init(, [.mainFile, .importedFile])
//        ])
//      }
//    }
//  }
// }

// MARK: - TransitiveExternals

//fileprivate struct HideAndShowFuncInStructAndExtension: TestProtocol {
//  fileprivate let paths = Paths<Module>()
//}
//
//extension HideAndShowFuncInStructAndExtension {
//  fileprivate enum Module: String, ModuleProtocol {
//    // Must be in build order
//    case importedModule, mainModule
//
//    var sources: [SourceFile] {
//      switch self {
//      case .mainModule: return [.mainFile, .otherFile, .anotherFile, .yetAnotherFile]
//      case .importedModule: return [.importedFile]
//      }
//    }
//    var imports: [Self] {
//      switch self {
//      case .mainModule: return [.importedModule]
//      case .importedModule: return []
//      }
//    }
//    var isLibrary: Bool {
//      switch self {
//      case .mainModule: return false
//      case .importedModule: return true
//      }
//    }
//  }
//}
//
//extension HideAndShowFuncInStructAndExtension {
//  fileprivate enum SourceFile: String, SourceProtocol {
//    case mainFile = "main", otherFile, anotherFile, yetAnotherFile, importedFile
//
//    var description: SourceFileDescription<Self> {
//      switch self {
//      case .mainFile: return .stable("""
//                        import \(Module.importedModule.name)
//                        extension S {
//                          static func foo<I: SignedInteger>(_ si: I) {
//                            print("1: not public")
//                          }
//                          static func foo2<I: SignedInteger>(_ si: I) {
//                            print("2: not public")
//                          }
//                        }
//                        S.foo(3)
//                        S.foo2(3)
//                        """)
//      case .otherFile: return .stable("""
//                        import \(Module.importedModule.name)
//                        func baz() {
//                          T.bar("asdf")
//
//                        }
//                        """)
//      case .anotherFile: return .stable("""
//                          import \(Module.importedModule.name)
//                          func fred() {
//                            T()
//                          }
//                          """)
//      case .yetAnotherFile: return .stable("""
//                              import \(Module.importedModule.name)
//                              func late() {
//                                S()
//                              }
//                              """)
//      case .importedFile:
//        return .mutable([
//          .init("""
//              public protocol PP {}
//              public struct S: PP {
//                public init() {}
//                // public // was commented out; should rebuild users of foo
//                static func foo(_ i: Int) {print("1: private")}
//                func fo() {}
//              }
//              public struct T {
//                public init() {}
//                public static func bar(_ s: String) {print(s)}
//              }
//              extension S {
//               // public
//               static func foo2(_ i: Int) {print("2: private")}
//              }
//              """, [.mainFile, .yetAnotherFile, .importedFile]),
//          .init("""
//              public protocol PP {}
//              public struct S: PP {
//                public init() {}
//                public // was uncommented out; should rebuild users of foo
//                static func foo(_ i: Int) {print("1: private")}
//                func fo() {}
//              }
//              public struct T {
//                public init() {}
//                public static func bar(_ s: String) {print(s)}
//              }
//              extension S {
//               // public
//               static func foo2(_ i: Int) {print("2: private")}
//              }
//              """, [.mainFile, .yetAnotherFile, .importedFile]),
//          .init("""
//              public protocol PP {}
//              public struct S: PP {
//                public init() {}
//                public
//                static func foo(_ i: Int) {print("1: private")}
//                func fo() {}
//              }
//              public struct T {
//                public init() {}
//                public static func bar(_ s: String) {print(s)}
//              }
//              extension S {
//               public  // was uncommented; should rebuild users of foo2
//               static func foo2(_ i: Int) {print("2: private")}
//              }
//              """, [.mainFile, .importedFile]),
//          .init("""
//              public protocol PP {}
//              public struct S: PP {
//                public init() {}
//                public
//                static func foo(_ i: Int) {print("1: private")}
//                func fo() {}
//              }
//              public struct T {
//                public init() {}
//                public static func bar(_ s: String) {print(s)}
//              }
//              extension S {
//               // public  // was commented out; should rebuild users of foo2
//               static func foo2(_ i: Int) {print("2: private")}
//              }
//              """, [.mainFile, .importedFile])
//        ])
//      }
//    }
//  }
//
//}
