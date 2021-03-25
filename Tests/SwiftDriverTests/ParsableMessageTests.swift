//===--------------- ParsableMessageTests.swift - Swift Parsable Output ---===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import Foundation
import TSCBasic
import TSCUtility

@_spi(Testing) import SwiftDriver

final class ParsableMessageTests: XCTestCase {
  func testBeganMessage() throws {
    let message = BeganMessage(
      pid: 1,
      realPid: 1,
      inputs: ["/path/to/foo.swift"],
      outputs: [
      .init(path: "/path/to/foo.o", type: "object")
      ],
      commandExecutable: "/path/to/swiftc",
      commandArguments: ["-frontend", "compile"]
    )

    let beganMessage = ParsableMessage(name: "compile", kind: .began(message))

    let encoded = try beganMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    XCTAssertEqual(string, """
      {
        "command_arguments" : [
          "-frontend",
          "compile"
        ],
        "command_executable" : "\\/path\\/to\\/swiftc",
        "inputs" : [
          "\\/path\\/to\\/foo.swift"
        ],
        "kind" : "began",
        "name" : "compile",
        "outputs" : [
          {
            "path" : "\\/path\\/to\\/foo.o",
            "type" : "object"
          }
        ],
        "pid" : 1
      }
      """)
  }

  func testFinishedMessage() throws {
    let message = FinishedMessage(exitStatus: 1, output: "hello", pid: 1, realPid: 1)
    let finishedMessage = ParsableMessage(name: "compile", kind: .finished(message))
    let encoded = try finishedMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    XCTAssertEqual(string, """
    {
      "exit-status" : 1,
      "kind" : "finished",
      "name" : "compile",
      "output" : "hello",
      "pid" : 1
    }
    """)
  }

    func testSignalledMessage() throws {
      let message = SignalledMessage(pid: 2, realPid: 2, output: "sig",
                                     errorMessage: "err", signal: 3)
      let signalledMessage = ParsableMessage(name: "compile", kind: .signalled(message))
      let encoded = try signalledMessage.toJSON()
      let string = String(data: encoded, encoding: .utf8)!

      XCTAssertEqual(string, """
      {
        "error-message" : "err",
        "kind" : "signalled",
        "name" : "compile",
        "output" : "sig",
        "pid" : 2,
        "signal" : 3
      }
      """)
    }

  func testFrontendMessages() throws {
    do {
      try withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        let output = path.appending(component: "main.o")
        try localFileSystem.writeFileContents(main) {
          $0 <<< "print(\"hello, world!\")"
        }
        let diags = DiagnosticsEngine()
        var driver = try Driver(args: ["swiftc", main.pathString,
                                       "-use-frontend-parseable-output",
                                       "-o", output.pathString],
                                env: ProcessEnv.vars,
                                diagnosticsEngine: diags,
                                fileSystem: localFileSystem)
        let jobs = try driver.planBuild()
        XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
        XCTAssertEqual(jobs[0].outputs.count, 1)
        let compileArgs = jobs[0].commandLine
        XCTAssertTrue(compileArgs.contains((.flag("-frontend-parseable-output"))))

        // Replace the error stream with one we capture here.
        let errorStream = stderrStream
        let errorOutputFile = path.appending(component: "dummy_error_stream")
        TSCBasic.stderrStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(errorOutputFile))

        try driver.run(jobs: jobs)
        let invocationErrorOutput = try localFileSystem.readFileContents(errorOutputFile).description
        XCTAssertTrue(invocationErrorOutput.contains("""
{
  "kind": "began",
  "name": "compile",
"""))
        XCTAssertTrue(invocationErrorOutput.contains("""
{
  "kind": "finished",
  "name": "compile",
"""))
        // Restore the error stream to what it was
        TSCBasic.stderrStream = errorStream
      }
    }

    do {
      try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-parseable-output",
                                         "-use-frontend-parseable-output"]) {
        $1.expect(.error(Driver.Error.conflictingOptions(.parseableOutput,
                                                         .useFrontendParseableOutput)))
      }
    }
  }
}
