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

import Testing
import TSCBasic

@_spi(Testing) import SwiftDriver
import TestUtilities
import var Foundation.EXIT_SUCCESS
import class Foundation.NSString

@discardableResult
internal func withHijackedErrorStream(
  _ body: () async throws -> ()
) async throws -> String {
  // Replace the error stream with one we capture here.
  let errorStream = stderrStream
  var output: String = ""
  try await withTemporaryFile { file in
    TSCBasic.stderrStream = try ThreadSafeOutputByteStream(LocalFileOutputByteStream(file.path))
    try await body()
    TSCBasic.stderrStream.flush()
    output = try "\(localFileSystem.readFileContents(file.path))".replacingOccurrences(of: "\r\n", with: "\n")
  }
  // Restore the error stream to what it was
  TSCBasic.stderrStream = errorStream
  return output
}

@discardableResult
internal func withHijackedOutputStream(
  _ body: () async throws -> ()
) async throws -> String {
  // Replace the error stream with one we capture here.
  let outputStream = stdoutStream
  var output: String = ""
  try await withTemporaryFile { file in
    TSCBasic.stdoutStream = try ThreadSafeOutputByteStream(LocalFileOutputByteStream(file.path))
    try await body()
    TSCBasic.stdoutStream.flush()
    output = try localFileSystem.readFileContents(file.path).description
  }
  // Restore the error stream to what it was
  TSCBasic.stdoutStream = outputStream
  return output
}

@Suite(.serialized) struct ParsableMessageTests {
  @Test func beganMessage() throws {
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

    #expect(string == """
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
        "pid" : 1,
        "process" : {
          "real_pid" : 1
        }
      }
      """)
  }

  @Test func finishedMessage() throws {
    let message = FinishedMessage(exitStatus: 1, output: "hello", pid: 1, realPid: 1)
    let finishedMessage = ParsableMessage(name: "compile", kind: .finished(message))
    let encoded = try finishedMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    #expect(string == """
    {
      "exit-status" : 1,
      "kind" : "finished",
      "name" : "compile",
      "output" : "hello",
      "pid" : 1,
      "process" : {
        "real_pid" : 1
      }
    }
    """)
  }

  @Test func signalledMessage() throws {
    let message = SignalledMessage(pid: 2, realPid: 2, output: "sig",
                                   errorMessage: "err", signal: 3)
    let signalledMessage = ParsableMessage(name: "compile", kind: .signalled(message))
    let encoded = try signalledMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    #expect(string == """
    {
      "error-message" : "err",
      "kind" : "signalled",
      "name" : "compile",
      "output" : "sig",
      "pid" : 2,
      "process" : {
        "real_pid" : 2
      },
      "signal" : 3
    }
    """)
  }

  @Test func abnormalExitMessage() throws {
    let exit = AbnormalExitMessage(pid: 1024, realPid: 1024, output: nil, exception: 0x8000_0003)
    let message = ParsableMessage(name: "compile", kind: .abnormal(exit))
    let encoded = try message.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    #expect(string == """
    {
      "exception" : 2147483651,
      "kind" : "abnormal-exit",
      "name" : "compile",
      "pid" : 1024,
      "process" : {
        "real_pid" : 1024
      }
    }
    """)
  }

  @Test func beganBatchMessages() async throws {
    do {
      try await withTemporaryDirectory { path in
        let workdir: AbsolutePath = localFileSystem.currentWorkingDirectory!.appending(components: "WorkDir")
        let resolver = try ArgsResolver(fileSystem: localFileSystem)

        var driver = try TestDriver(args: ["swiftc", "-o", "test.o",
                                       "main.swift", "test1.swift", "test2.swift",
                                       "-enable-batch-mode", "-driver-batch-count", "1",
                                       "-working-directory", workdir.pathString])
        let jobs = try await driver.planBuild()
        let compileJob = jobs[0]
        let args : [String] = try resolver.resolveArgumentList(for: compileJob, useResponseFiles: .disabled)
        let toolDelegate = ToolExecutionDelegate(mode: .parsableOutput,
                                                 buildRecordInfo: nil,
                                                 showJobLifecycle: false,
                                                 argsResolver: resolver,
                                                 diagnosticEngine: DiagnosticsEngine())

        let errorOutput = try await withHijackedErrorStream {
          // Emit the began messages and examine the output
          toolDelegate.jobStarted(job: compileJob, arguments: args, pid: 42)
        }


        // There were 3 messages emitted
        #expect(errorOutput.components(separatedBy:
          """
            "kind" : "began",
            "name" : "compile",
          """).count - 1 == 3)

#if os(Windows)
        let mainPath: String = workdir.appending(component: "main.swift").nativePathString(escaped: true)
        let test1Path: String = workdir.appending(component: "test1.swift").nativePathString(escaped: true)
        let test2Path: String = workdir.appending(component: "test2.swift").nativePathString(escaped: true)
#else
        let mainPath: String = workdir.appending(component: "main.swift").pathString.replacingOccurrences(of: "/", with: "\\/")
        let test1Path: String = workdir.appending(component: "test1.swift").pathString.replacingOccurrences(of: "/", with: "\\/")
        let test2Path: String = workdir.appending(component: "test2.swift").pathString.replacingOccurrences(of: "/", with: "\\/")
#endif

        /// One per primary
        #expect(errorOutput.contains(
          """
            "pid" : -1000,
          """))
        #expect(errorOutput.contains(
          """
            \"inputs\" : [
              \"\(mainPath)\"
            ],
          """))
        #expect(errorOutput.contains(
          """
            "pid" : -1001,
          """))
        #expect(errorOutput.contains(
          """
            \"inputs\" : [
              \"\(test1Path)\"
            ],
          """))
        #expect(errorOutput.contains(
          """
            "pid" : -1002,
          """))
        #expect(errorOutput.contains(
          """
            \"inputs\" : [
              \"\(test2Path)\"
            ],
          """))

        /// Real PID appeared in every message
        #expect(errorOutput.components(separatedBy:
          """
            \"process\" : {
              \"real_pid\" : 42
            }
          """).count - 1 == 3)
      }
    }
  }

  @Test func finishedBatchMessages() async throws {
    do {
      try await withTemporaryDirectory { path in
        // Take over the error stream just to prevent it being printed in test runs
        let resolver = try ArgsResolver(fileSystem: localFileSystem)
        var driver = try TestDriver(args: ["swiftc", "-o", "test.o",
                                       "main.swift", "test1.swift", "test2.swift",
                                       "-enable-batch-mode", "-driver-batch-count", "1",
                                       "-working-directory", "/WorkDir"])
        let jobs = try await driver.planBuild()
        let compileJob = jobs[0]
        let args: [String] = try resolver.resolveArgumentList(for: compileJob)
        let toolDelegate = ToolExecutionDelegate(mode: .parsableOutput,
                                             buildRecordInfo: nil,
                                             showJobLifecycle: false,
                                             argsResolver: resolver,
                                             diagnosticEngine: DiagnosticsEngine())

        let _ = try await withHijackedErrorStream {
          // First emit the began messages
          toolDelegate.jobStarted(job: compileJob, arguments: args, pid: 42)
        }

        // Now hijack the error stream and emit finished messages
        let errorOutput = try await withHijackedErrorStream {
          let resultSuccess = ProcessResult(arguments: args,
                                            environmentBlock: ProcessEnv.block,
                                            exitStatus: ProcessResult.ExitStatus.terminated(code: EXIT_SUCCESS),
                                            output: Result.success([]),
                                            stderrOutput: Result.success([]))
          // Emit the finished messages and examine the output
          toolDelegate.jobFinished(job: compileJob, result: resultSuccess, pid: 42)
        }
        #expect(errorOutput.contains(
          """
          {
            \"exit-status\" : 0,
            \"kind\" : \"finished\",
            \"name\" : \"compile\",
            \"pid\" : -1000,
            \"process\" : {
              \"real_pid\" : 42
            }
          }
          """))
        #expect(errorOutput.contains(
          """
          {
            \"exit-status\" : 0,
            \"kind\" : \"finished\",
            \"name\" : \"compile\",
            \"pid\" : -1001,
            \"process\" : {
              \"real_pid\" : 42
            }
          }
          """))
        #expect(errorOutput.contains(
          """
          {
            \"exit-status\" : 0,
            \"kind\" : \"finished\",
            \"name\" : \"compile\",
            \"pid\" : -1002,
            \"process\" : {
              \"real_pid\" : 42
            }
          }
          """))
      }
    }
  }

  @Test func signalledBatchMessages() async throws {
    do {
      try await withTemporaryDirectory { path in
        // Take over the error stream just to prevent it being printed in test runs
        let resolver = try ArgsResolver(fileSystem: localFileSystem)
        var driver = try TestDriver(args: ["swiftc", "-o", "test.o",
                                       "main.swift", "test1.swift", "test2.swift",
                                       "-enable-batch-mode", "-driver-batch-count", "1",
                                       "-working-directory", "/WorkDir"])
        let jobs = try await driver.planBuild()
        let compileJob = jobs[0]
        let args: [String] = try resolver.resolveArgumentList(for: compileJob)
        let toolDelegate = ToolExecutionDelegate(mode: .parsableOutput,
                                             buildRecordInfo: nil,
                                             showJobLifecycle: false,
                                             argsResolver: resolver,
                                             diagnosticEngine: DiagnosticsEngine())

        let _ = try await withHijackedErrorStream {
          // First emit the began messages
          toolDelegate.jobStarted(job: compileJob, arguments: args, pid: 42)
        }

#if os(Windows)
          let status = ProcessResult.ExitStatus.terminated(code: EXIT_SUCCESS)
          let kind = "finished"
          let signal = ""
#else
          let status = ProcessResult.ExitStatus.signalled(signal: 9)
          let kind = "signalled"
          let signal = """
          ,
            \"signal\" : 9
          """
#endif

        // Now hijack the error stream and emit finished messages
        let errorOutput = try await withHijackedErrorStream {
          let resultSignalled = ProcessResult(arguments: args,
                                              environmentBlock: ProcessEnv.block,
                                              exitStatus: status,
                                              output: Result.success([]),
                                              stderrOutput: Result.success([]))
          // First emit the began messages
          toolDelegate.jobFinished(job: compileJob, result: resultSignalled, pid: 42)
        }
        #expect(errorOutput.contains(
          """
            \"kind\" : \"\(kind)\",
            \"name\" : \"compile\",
            \"pid\" : -1000,
            \"process\" : {
              \"real_pid\" : 42
            }\(signal)
          }
          """))
        #expect(errorOutput.contains(
          """
            \"kind\" : \"\(kind)\",
            \"name\" : \"compile\",
            \"pid\" : -1001,
            \"process\" : {
              \"real_pid\" : 42
            }\(signal)
          }
          """))
        #expect(errorOutput.contains(
          """
            \"kind\" : \"\(kind)\",
            \"name\" : \"compile\",
            \"pid\" : -1002,
            \"process\" : {
              \"real_pid\" : 42
            }\(signal)
          }
          """))
      }
    }
  }

  @Test func silentIntegratedMode() async throws {
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        let output = path.appending(component: "main.o")
        try localFileSystem.writeFileContents(main, bytes: "nonexistentPrint(\"hello, compilation error!\")")

        let diags = DiagnosticsEngine()
        let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
        var driver = try TestDriver(args: ["swiftc", main.pathString,
                                       "-o", output.pathString] + sdkArgumentsForTesting,
                                diagnosticsEngine: diags,
                                integratedDriver: true)
        let jobs = try await driver.planBuild()
        let errorOutput = try await withHijackedErrorStream {
          await #expect(throws: (any Error).self) {
            try await driver.run(jobs: jobs)
          }
        }
        #expect(!errorOutput.contains("error: cannot find 'nonexistentPrint' in scope"))
      }
    }
  }

  @Test func frontendMessages() async throws {
    do {
      try await withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        let output = path.appending(component: "main.o")
        try localFileSystem.writeFileContents(main, bytes: "print(\"hello, world!\")")

        let diags = DiagnosticsEngine()
        let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
        var driver = try TestDriver(args: ["swiftc", main.pathString,
                                       "-use-frontend-parseable-output",
                                       "-o", output.pathString] + sdkArgumentsForTesting,
                                diagnosticsEngine: diags,
                                integratedDriver: false)
        let jobs = try await driver.planBuild()
        #expect(jobs.removingAutolinkExtractJobs().map(\.kind) == [.compile, .link])
        #expect(jobs[0].outputs.count == 1)
        let compileArgs = jobs[0].commandLine
        #expect(compileArgs.contains((.flag("-frontend-parseable-output"))))
        let errorOutput = try await withHijackedErrorStream {
          try await driver.run(jobs: jobs)
        }
        #expect(errorOutput.contains(
          """
          {
            "kind": "began",
            "name": "compile",
          """))
        #expect(errorOutput.contains(
          """
          {
            "kind": "finished",
            "name": "compile",
          """))
      }
    }

    do {
      try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-parseable-output",
                                         "-use-frontend-parseable-output"]) {
        $1.expect(.error(Driver.Error.conflictingOptions(.parseableOutput,
                                                         .useFrontendParseableOutput)))
      }
    }
  }
}

