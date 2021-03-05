//===------- IncrementalImportTestFramework.swift - Swift Testing ---------===//
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
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities




// MARK: - StepProtocol
protocol StepProtocol: TestPartProtocol {
  associatedtype State: StateProtocol
  typealias Source = State.Source

  var to: State {get}
  var expectingWith: [Source] {get}
  var expectingWithout: [Source] {get}
}
extension StepProtocol {
  var name: String {rawValue}

  func mutateAndRebuildAndCheck(_ context: TestContext) {
    to.mutateAndRebuildAndCheck(context,
                                expecting: expecting(context),
                                stepName: name)
  }

  func expecting(_ context: TestContext) -> [Source] {
    context.withIncrementalImports ? expectingWith : expectingWithout
  }
}
