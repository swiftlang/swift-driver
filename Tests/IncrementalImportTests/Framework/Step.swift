//===-------------- Step.swift - Swift Testing --------------------===//
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

/// A test step: includes the source state to compile and what compilations are expected.
/// A given test consists of a start state, and a sequence of steps.
/// (See `TestProtocol`.)
struct Step<State: StateProtocol> {
  typealias SourceVersion = State.Module.SourceVersion
  let nextState: State
  let expecting: Expectation<SourceVersion>

  init(_ nextState: State, _ expecting: Expectation<SourceVersion>) {
    self.nextState = nextState
    self.expecting = expecting
  }

  func mutateAndRebuildAndCheck(_ context: TestContext) {
    let compiledSources = nextState.enter(context)
    expecting.check(against: compiledSources, context, nextStateName: nextState.name)
  }

  var allSourceVersions: [SourceVersion] {nextState.allInputs}
}
