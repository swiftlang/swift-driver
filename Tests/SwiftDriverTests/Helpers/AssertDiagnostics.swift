//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import SwiftDriver
import TSCBasic
import TestUtilities
import Testing

@discardableResult
func assertDriverDiagnostics<Result>(
  args: [String],
  env: ProcessEnvironmentBlock = ProcessEnv.block,
  file: String = #file,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  do body: (inout TestDriver, DiagnosticVerifier) async throws -> Result
) async throws -> Result {
  let matcher = DiagnosticVerifier()
  let sourceLocation = SourceLocation(fileID: fileID, filePath: file, line: line, column: column)
  defer { matcher.verify(sourceLocation: sourceLocation) }

  var driver = try TestDriver(
    args: args,
    env: env,
    diagnosticsEngine: DiagnosticsEngine(handlers: [matcher.emit(_:), testDiagnosticsHandler])
  )
  return try await body(&driver, matcher)
}

/// Asserts that the `Driver` it instantiates will only emit warnings and errors
/// marked as expected by calls to `DiagnosticVerifier.expect(_:)`,
/// and will emit all diagnostics so marked by the end of the block.
func assertDriverDiagnostics(
  args: String...,
  env: ProcessEnvironmentBlock = ProcessEnv.block,
  file: String = #file,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  do body: (inout TestDriver, DiagnosticVerifier) async throws -> Void
) async throws {
  // Ensure there are no color codes in order to make matching work
  let argsInBlackAndWhite = [args[0], "-no-color-diagnostics"] + args.dropFirst()
  try await assertDriverDiagnostics(
    args: argsInBlackAndWhite,
    env: env,
    file: file,
    fileID: fileID,
    line: line,
    column: column,
    do: body
  )
}

/// Asserts that the `Driver` it instantiates will not emit any warnings or errors.
func assertNoDriverDiagnostics(
  args: String...,
  env: ProcessEnvironmentBlock = ProcessEnv.block,
  file: String = #file,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  do body: (inout TestDriver) async throws -> Void = { _ in }
) async throws {
  try await assertDriverDiagnostics(args: args, env: env, file: file, fileID: fileID, line: line, column: column) {
    driver,
    _ in try await body(&driver)
  }
}

/// Asserts that the `DiagnosticsEngine` it instantiates will only emit warnings
/// and errors marked as expected by calls to `DiagnosticVerifier.expect(_:)`,
/// and will emit all diagnostics so marked by the end of the block.
func assertDiagnostics(
  file: String = #file,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  do body: (DiagnosticsEngine, DiagnosticVerifier) async throws -> Void
) async rethrows {
  let matcher = DiagnosticVerifier()
  let sourceLocation = SourceLocation(fileID: fileID, filePath: file, line: line, column: column)
  defer { matcher.verify(sourceLocation: sourceLocation) }

  let diags = DiagnosticsEngine(handlers: [matcher.emit(_:), testDiagnosticsHandler])
  try await body(diags, matcher)
}

/// Asserts that the `DiagnosticsEngine` it instantiates will not emit any warnings
/// or errors.
func assertNoDiagnostics(
  file: String = #file,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  do body: (DiagnosticsEngine) async throws -> Void
) async rethrows {
  try await assertDiagnostics(file: file, fileID: fileID, line: line, column: column) { diags, _ in try await body(diags) }
}

/// Checks that the diagnostics actually emitted by a `DiagnosticsEngine`
/// or `Driver` match the ones expected to be emitted.
///
/// A `DiagnosticVerifier` receives both actual diagnostics and expected diagnostic
/// messages and compares them against each other. If the behavior of the diagnostic and
/// message are the same, and the message's text is a substring of the diagnostic's text,
/// the diagnostics are considered to match. At the end of the assertion that created the
/// verifier, the verifier evaluates all unmatched diagnostics and expectations to
/// determine if any test assertions failed.
///
/// Expected diagnostics are added to the verifier by calling
/// `DiagnosticVerifier.expect(_:repetitions:)`. Any unmet
/// expectation is always a failure. Expectations can be registered before
/// or after the matching diagnostic is emitted, but
///
/// Actual diagnostics are added via a private method. By default, only
/// unexpected warnings and errors—not notes or remarks—cause a
/// failure. You can manipulate this rule by calling
/// `DiagnosticVerifier.permitUnexpected(_:)` or
/// `DiagnosticVerifier.forbidUnexpected(_:)`.
final class DiagnosticVerifier {
  fileprivate struct Expectation {
    let message: Diagnostic.Message
    let alternativeMessage: Diagnostic.Message?
    let sourceLocation: SourceLocation
  }

  // When we're finished, we will nil the dispatch queue so that any diagnostics
  // emitted after verification will cause a crash.
  fileprivate var queue: DispatchQueue? =
    DispatchQueue(label: "DiagnosticVerifier")

  // Access to `actual` and `expected` must be synchronized on `queue`. (Even
  // reads should be, although we only enforce writes.)
  fileprivate var actual: [Diagnostic] = [] {
    didSet {
      if #available(macOS 10.12, *) {
        dispatchPrecondition(condition: .onQueue(queue!))
      }
    }
  }
  fileprivate var expected: [Expectation] = [] {
    didSet {
      if #available(macOS 10.12, *) {
        dispatchPrecondition(condition: .onQueue(queue!))
      }
    }
  }

  // Access to `permitted` is not synchronized because it is only used from the
  // test.
  fileprivate var permitted: Set<Diagnostic.Behavior> = [.note, .remark, .ignored]

  /// Callback for the diagnostic engine or driver to use.
  func emit(_ diag: Diagnostic) {
    guard let queue = queue else {
      fatalError("Diagnostic emitted after the test was complete! \(diag)")
    }
    queue.async {
      for (i, expectation) in self.expected.zippedIndices {
        if diag.matches(expectation.message) {
          self.expected.remove(at: i)
          return
        } else if let alternativeExpectedMessage = expectation.alternativeMessage,
          diag.matches(alternativeExpectedMessage)
        {
          self.expected.remove(at: i)
          return
        }
      }

      self.actual.append(diag)
    }
  }

  /// Adds an expectation that, by the end of the assertion that created this
  /// verifier, the indicated diagnostic will have been emitted. If no diagnostic
  /// with the same behavior and a message containing this message's text
  /// is emitted by then, a test assertion will fail.
  func expect(
    _ message: Diagnostic.Message,
    alternativeMessage: Diagnostic.Message? = nil,
    repetitions: Int = 1,
    file: String = #file,
    fileID: String = #fileID,
    line: Int = #line,
    column: Int = #column,
  ) {
    queue!.async {
      var remaining = repetitions

      for (i, diag) in self.actual.zippedIndices where diag.matches(message) {
        self.actual.remove(at: i)
        remaining -= 1
        if remaining < 1 { return }
      }

      let expectation = Expectation(
        message: message,
        alternativeMessage: alternativeMessage,
        sourceLocation: SourceLocation(fileID: fileID, filePath: file, line: line, column: column)
      )
      self.expected.append(contentsOf: repeatElement(expectation, count: remaining))
    }
  }

  /// Tells the verifier to permit unexpected diagnostics with
  /// the indicated behaviors without causing a test failure.
  func permitUnexpected(_ behaviors: Diagnostic.Behavior...) {
    permitted.formUnion(behaviors)
  }

  /// Tells the verifier to forbid unexpected diagnostics with
  /// the indicated behaviors; any such diagnostics will cause
  /// a test failure.
  func forbidUnexpected(_ behaviors: Diagnostic.Behavior...) {
    permitted.subtract(behaviors)
  }

  /// Performs the final verification that the actual diagnostics
  /// matched the expectations.
  func verify(sourceLocation: SourceLocation) {
    // All along, we have removed expectations and diagnostics as they've been
    // matched, so if there's anything left, it didn't get matched.

    var failures: [(String, SourceLocation)] = []

    queue!.sync {
      for diag in self.actual where !self.permitted.contains(diag.behavior) {
        failures.append(
          (
            "Driver emitted unexpected diagnostic \(diag.behavior): \(diag)",
            sourceLocation
          )
        )
      }

      for expectation in self.expected {
        failures.append(
          (
            "Driver did not emit expected diagnostic: \(expectation.message)",
            expectation.sourceLocation
          )
        )
      }
      self.queue = nil
    }

    for failure in failures {
      Issue.record(
        Comment(rawValue: failure.0),
        sourceLocation: sourceLocation
      )
    }
  }
}

extension Diagnostic {
  func matches(_ expectation: Diagnostic.Message) -> Bool {
    behavior == expectation.behavior && message.text.contains(expectation.text)
  }
}

fileprivate extension Collection {
  var zippedIndices: Zip2Sequence<Indices, Self> {
    zip(indices, self)
  }
}
