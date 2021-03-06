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
class RenameMemberOfImportedStructTest: XCTestCase {
  func testRenamingMember() throws {
    try RenameMemberOfImportedStruct.test()
  }
}

// MARK: - RenameMemberOfImportedStruct

/// Change the name of a member of an imported struct.
/// Ensure that only the users get rebuilt
fileprivate struct RenameMemberOfImportedStruct: TestProtocol {
  static let start = State.initial
  static let steps: [Step] = [.rename, .unrename]
}

fileprivate extension RenameMemberOfImportedStruct {
  enum Step: String, StepProtocol {
     case rename, unrename
    var nextState: State {
      switch self {
      case .rename: return .renamed
      case .unrename: return .initial
      }
    }
    var expecting: Expectation<SourceVersion> {
      Expectation(with: [.mainFile, .originalMember], without: allSourceVersions)
    }
  }
}

fileprivate extension RenameMemberOfImportedStruct {
  enum State: String, StateProtocol {
    case initial, renamed

    var jobs: [BuildJob<Module>] {
      let importedSource: SourceVersion
      switch self {
      case .initial: importedSource = .originalMember
      case .renamed: importedSource = .renamedMember
      }
      return [
        BuildJob(.importedModule, [importedSource]),
        BuildJob(.mainModule, [.mainFile, .otherFile])
      ]
    }
  }
}

fileprivate extension RenameMemberOfImportedStruct {
  enum Module: String, ModuleProtocol {
    typealias SourceVersion = RenameMemberOfImportedStruct.SourceVersion

    // Must be in build order
    case importedModule, mainModule

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
  enum SourceVersion: String, SourceVersionProtocol {

    case mainFile, otherFile, originalMember, renamedMember

    var fileName: String {
      switch self {
      case .renamedMember, .originalMember: return "memberDefiner"
      case .mainFile: return "main"
      default: return name
      }
    }

    var code: String {
      switch self {
      case .mainFile:
        return """
               import \(Module.importedModule.nameToImport)
               ImportedStruct().importedMember()
               """
      case .otherFile:
        return ""
      case .originalMember:
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

