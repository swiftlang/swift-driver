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
    var to: State {
      switch self {
      case .rename: return .renamed
      case .unrename: return .initial
      }
    }
    var expecting: Expectation<Source> {
      Expectation(with: [.mainFile, .importedFile], without: allSources)
    }
  }
}

fileprivate extension RenameMemberOfImportedStruct {
  enum State: String, StateProtocol {
    case initial, renamed

    var jobs: [BuildJob<Module>] {
      let imported: Source
      switch self {
      case .initial: imported = .importedFile
      case .renamed: imported = .renamedMember
      }
      return [
        BuildJob(.importedModule, [imported]),
        BuildJob(.mainModule, [.mainFile, .otherFile])
      ]
    }
  }


}

fileprivate extension RenameMemberOfImportedStruct {
  enum Module: String, ModuleProtocol {
    typealias Source = RenameMemberOfImportedStruct.Source

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

