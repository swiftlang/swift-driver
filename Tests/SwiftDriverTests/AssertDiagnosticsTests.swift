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

@_spi(Testing) import SwiftDriver
import Testing

// Yes, these are meta-tests! `assertDiagnostics(do:)` and friends are
// complicated enough to warrant a few tests of their own. To test that they
// fail when they're supposed to, we use `withKnownIssue` to catch expected
// failures.

@Suite(.suppressKnownIssues())
struct AssertDiagnosticsTests {
  @Test func noDiagnostics() async throws {
    await assertNoDiagnostics { _ in }

    try await expectedIssue {
      await assertNoDiagnostics { diags in
        diags.emit(error: "something happened")
      }
    }
    try await expectedIssue {
      await assertNoDiagnostics { diags in
        diags.emit(warning: "hello")
      }
    }

    // Unexpected warnings/notes/remarks are okay
    await assertNoDiagnostics { diags in
      diags.emit(note: "hello")
    }
    await assertNoDiagnostics { diags in
      diags.emit(remark: "hello")
    }
  }

  @Test func diagnostics() async throws {
    await assertDiagnostics { diags, match in
      diags.emit(error: "yankees won again")
      match.expect(.error("won"))
    }
    await assertDiagnostics { diags, match in
      match.expect(.error("won"))
      diags.emit(error: "yankees won again")
    }

    try await expectedIssue(count: 2) {
      await assertDiagnostics { diags, match in
        match.expect(.error("lost"))
        diags.emit(error: "yankees won again")
      }
    }

    try await expectedIssue(count: 2) {
      await assertDiagnostics { diags, match in
        diags.emit(error: "yankees won again")
        diags.emit(error: "yankees won yet again")
      }
    }

    try await expectedIssue(count: 2) {
      await assertDiagnostics { diags, match in
        match.expect(.error("won"))
        match.expect(.error("won"))
      }
    }

    // We should get two assertion failures: one for expecting the warning, one
    // for emitting the error.
    try await expectedIssue(count: 2) {
      await assertDiagnostics { diags, match in
        match.expect(.warning("won"))
        diags.emit(.error("yankees won again"))
      }
    }

    // We should get one assertion failure for the unexpected error. An
    // unexpected note is okay.
    try await expectedIssue(count: 1) {
      await assertDiagnostics { diags, match in
        diags.emit(error: "yankees won again")
        diags.emit(note: "investigate their star's doctor")
      }
    }

    // ...unless we tighten things up.
    try await expectedIssue(count: 2) {
      await assertDiagnostics { diags, match in
        diags.emit(error: "yankees won again")
        diags.emit(note: "investigate their star's doctor")
        match.forbidUnexpected(.note)
      }
    }

    // ...or loosen them.
    await assertDiagnostics { diags, match in
      diags.emit(error: "yankees won again")
      diags.emit(note: "investigate their star's doctor")
      match.permitUnexpected(.error)
    }
  }

  @Test func driverDiagnostics() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "test.swift")

    try await assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
      driver.diagnosticEngine.emit(.error("this mode does not support emitting modules"))
      verify.expect(.error("this mode does not support emitting modules"))
    }

    try await expectedIssue {
      try await assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
        verify.expect(.error("this mode does not support emitting modules"))
      }
    }

    try await expectedIssue {
      try await assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
        driver.diagnosticEngine.emit(.error("this mode does not support emitting modules"))
      }
    }

    try await expectedIssue(count: 2) {
      try await assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
        driver.diagnosticEngine.emit(.error("this mode does not support emitting modules"))
        verify.expect(.error("-static may not be used with -emit-executable"))
      }
    }
  }
}

/// Invoke a function that is expected to record a specific number of issues.
///
/// - Parameters:
///   - expectedCount: The exact number of issues expected.
///   - comment: An optional comment describing the known issues.
///   - file: The source file to attribute issues to.
///   - line: The source line to attribute issues to.
///   - body: The function to invoke.
private func expectedIssue(
  count: Int = 1,
  _ comment: Comment? = nil,
  file: String = #file,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ body: () async throws -> Void
) async throws {
  let sourceLocation = SourceLocation(
    fileID: fileID,
    filePath: file,
    line: line,
    column: column
  )
  try await confirmation(
    comment,
    expectedCount: count,
    sourceLocation: sourceLocation
  ) { issueConfirmation in
    try await withKnownIssue(
      comment,
      isIntermittent: false,
      sourceLocation: sourceLocation
    ) {
      try await body()
    } matching: { issue in
      issueConfirmation.confirm()
      return true
    }
  }
}

private extension Trait where Self == IssueHandlingTrait {
  /// Filter out known issues, keeping only real failures (like confirmation miscounts).
  static func suppressKnownIssues() -> Self {
    #if compiler(>=6.3)
    .filterIssues { $0.isFailure }
    #else
    // Older version do not have the API to filter so test will show as known issue.
    .filterIssues { issue in true }
    #endif
  }
}
