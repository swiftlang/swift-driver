//===-------------- StepProtocol.swift - Swift Testing --------------------===//
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



/// A test step: includes the source state to compile and what compilations are expected.
protocol StepProtocol: TestPartProtocol {
  associatedtype State: StateProtocol
  typealias Source = State.Source

  var to: State {get}
  var expecting: Expectation<Source> {get}
}
extension StepProtocol {
  var name: String {rawValue}

  func mutateAndRebuildAndCheck(_ context: TestContext) {
    print(name)
    let compiledSources = to.mutateAndRebuild(context)
    expecting.check(against: compiledSources, context, stepName: name)
  }

  var allSources: [Source] {to.allOriginals}
}
