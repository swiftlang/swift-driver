//===---- SwiftDriverToolingInterfaceTests.swift - Swift Driver Tests ----===//
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
@_spi(Testing) import SwiftDriver
import SwiftOptions
import TSCBasic
import XCTest
import CToolingTestShim

final class SwiftDriverToolingInterfaceTests: XCTestCase {
  func testCreateCompilerInvocationV2() throws {
    try withTemporaryDirectory { path in
      let inputFile = path.appending(components: "test.swift")
      try localFileSystem.writeFileContents(inputFile) { $0.send("public func foo()") }
      
      // Expected success scenarios:
      do {
        let testCommand = inputFile.description
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in }))
      }
      do {
        let testCommand = "-emit-executable " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header -o t.out"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in }))
      }
      do {
        let testCommand = "-c " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in }))
      }
      do {
        let testCommand = inputFile.description + " -enable-batch-mode"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in }))
      }
      do { // Force no outputs
        let testCommand = "-module-name foo -emit-module -emit-module-path /tmp/foo.swiftmodule -emit-objc-header -emit-objc-header-path /tmp/foo.h -enable-library-evolution -emit-module-interface -emit-module-interface-path /tmp/foo.swiftinterface -emit-library -emit-tbd -emit-tbd-path /tmp/foo.tbd -emit-dependencies -serialize-diagnostics " + inputFile.description
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { args in
                                                                          resultingFrontendArgs = args
                                                                          return false
                                                                        },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        forceNoOutputs: true))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-module-interface-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-objc-header"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-objc-header-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-module-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-tbd-path"))
      }

      // Expected failure scenarios:
      do {
        let testCommand = "-v" // No inputs
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertTrue(getSingleFrontendInvocationFromDriverArgumentsV2(driverPath: "swiftc",
                                                                       argList: testCommand.components(separatedBy: " "),
                                                                       action: { _ in false },
                                                                       diagnostics: &emittedDiagnostics,
                                                                       diagnosticCallback: {_,_ in }))
        let errorMessage = try XCTUnwrap(emittedDiagnostics.first?.message.text)
        XCTAssertEqual(errorMessage, "unable to handle compilation, expected exactly one frontend job")
      }
    }
  }

  func testCreateCompilerInvocationV3() throws {
    try withTemporaryDirectory { path in
      let inputFile = path.appending(components: "test.swift")
      try localFileSystem.writeFileContents(inputFile) { $0.send("public func foo()") }

      let env = ProcessEnv.vars
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let executor = SimpleExecutor(resolver: resolver, fileSystem: localFileSystem, env: env)

      // Expected success scenarios:
      do {
        let testCommand = inputFile.description
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do {
        let testCommand = "-emit-executable " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header -o t.out"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do {
        let testCommand = "-c " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do {
        let testCommand = inputFile.description + " -enable-batch-mode"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do { // Force no outputs
        let testCommand = "-module-name foo -emit-module -emit-module-path /tmp/foo.swiftmodule -emit-objc-header -emit-objc-header-path /tmp/foo.h -enable-library-evolution -emit-module-interface -emit-module-interface-path /tmp/foo.swiftinterface -emit-library -emit-tbd -emit-tbd-path /tmp/foo.tbd -emit-dependencies -serialize-diagnostics " + inputFile.description
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { args in
                                                                          resultingFrontendArgs = args
                                                                          return false
                                                                        },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor,
                                                                        forceNoOutputs: true))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-module-interface-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-objc-header"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-objc-header-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-module-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-tbd-path"))
      }

      // Expected failure scenarios:
      do {
        let testCommand = "-v" // No inputs
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertTrue(getSingleFrontendInvocationFromDriverArgumentsV3(driverPath: "swiftc",
                                                                       argList: testCommand.components(separatedBy: " "),
                                                                       action: { _ in false },
                                                                       diagnostics: &emittedDiagnostics,
                                                                       diagnosticCallback: {_,_ in },
                                                                       env: env,
                                                                       executor: executor))
        let errorMessage = try XCTUnwrap(emittedDiagnostics.first?.message.text)
        XCTAssertEqual(errorMessage, "unable to handle compilation, expected exactly one frontend job")
      }
    }
  }

  func testCreateCompilerInvocationV4() throws {
    try withTemporaryDirectory { path in
      let inputFile = path.appending(components: "test.swift")
      try localFileSystem.writeFileContents(inputFile) { $0.send("public func foo()") }

      let env = ProcessEnv.vars
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let executor = SimpleExecutor(resolver: resolver, fileSystem: localFileSystem, env: env)

      // Expected success scenarios:
      do {
        let testCommand = inputFile.description
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do {
        let testCommand = "-emit-executable " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header -o t.out"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do {
        let testCommand = "-c " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do {
        let testCommand = inputFile.description + " -enable-batch-mode"
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { _ in false },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor))
      }
      do { // Force no outputs
        let testCommand = "-module-name foo -emit-module -emit-module-path /tmp/foo.swiftmodule -emit-objc-header -emit-objc-header-path /tmp/foo.h -enable-library-evolution -emit-module-interface -emit-module-interface-path /tmp/foo.swiftinterface -emit-library -emit-tbd -emit-tbd-path /tmp/foo.tbd -emit-dependencies -serialize-diagnostics " + inputFile.description
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: "swiftc",
                                                                        argList: testCommand.components(separatedBy: " "),
                                                                        action: { args in
                                                                          resultingFrontendArgs = args
                                                                          return false
                                                                        },
                                                                        diagnostics: &emittedDiagnostics,
                                                                        diagnosticCallback: {_,_ in },
                                                                        env: env,
                                                                        executor: executor,
                                                                        forceNoOutputs: true))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-module-interface-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-objc-header"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-objc-header-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-module-path"))
        XCTAssertFalse(resultingFrontendArgs.contains("-emit-tbd-path"))
      }

      // Expected failure scenarios:
      do {
        let testCommand = "-v" // No inputs
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertTrue(getSingleFrontendInvocationFromDriverArgumentsV4(driverPath: "swiftc",
                                                                       argList: testCommand.components(separatedBy: " "),
                                                                       action: { _ in false },
                                                                       diagnostics: &emittedDiagnostics,
                                                                       diagnosticCallback: {_,_ in },
                                                                       env: env,
                                                                       executor: executor))
        let errorMessage = try XCTUnwrap(emittedDiagnostics.first?.message.text)
        XCTAssertEqual(errorMessage, "unable to handle compilation, expected exactly one frontend job")
      }
    }
  }

  func testCreateCompilerInvocationCAPI() throws {
    try withTemporaryDirectory { path in
      let inputFile = path.appending(components: "test.swift")
      try localFileSystem.writeFileContents(inputFile) { $0.send("public func foo()") }
      let driverPath = "swiftc"

      // Basic compilation test
      do {
        let testCommandStr = "-emit-executable " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header -o t.out"
        let testCommand = testCommandStr.split(separator: " ").compactMap { String($0) }

        // Invoke the C shim from CToolingTestShim which calls the `getSingleFrontendInvocationFromDriverArgumentsV2`
        // C API defined in Swift in ToolingUtil
        XCTAssertFalse(driverPath.withCString { CBridgedDriverPath in
          withArrayOfCStrings(testCommand) { CBridgedArgList in
            getSingleFrontendInvocationFromDriverArgumentsTest(
              CBridgedDriverPath,
              CInt(testCommand.count),
              CBridgedArgList!,
              { argc, argvPtr in
                // Bridge argc back to [String]
                let argvBufferPtr = UnsafeBufferPointer<UnsafePointer<CChar>?>(start: argvPtr, count: Int(argc))
                let resultingFrontendArgs = argvBufferPtr.map { String(cString: $0!) }

                XCTAssertTrue(resultingFrontendArgs.contains("-frontend"))
                XCTAssertTrue(resultingFrontendArgs.contains("-c"))
                XCTAssertTrue(resultingFrontendArgs.contains("-emit-module-path"))
                XCTAssertTrue(resultingFrontendArgs.contains("-o"))
                return false
              },
              { diagKind, diagMessage in },
              false)
          }
        })
      }

      // Diagnostic callback test
      do {
        let testCommandStr = "-v"
        let testCommand = testCommandStr.split(separator: " ").compactMap { String($0) }
        XCTAssertTrue(driverPath.withCString { CBridgedDriverPath in
          withArrayOfCStrings(testCommand) { CBridgedArgList in
            getSingleFrontendInvocationFromDriverArgumentsTest(
              CBridgedDriverPath,
              CInt(testCommand.count),
              CBridgedArgList!,
              { argc, argvPtr in false },
              { diagKind, diagMessage in
                guard let nonOptionalDiagMessage = diagMessage else {
                  return XCTFail("Invalid tooling diagnostic handler message")
                }
                XCTAssertEqual(diagKind, SWIFTDRIVER_TOOLING_DIAGNOSTIC_ERROR)
                XCTAssertEqual(String(cString: nonOptionalDiagMessage),
                               "unable to handle compilation, expected exactly one frontend job")
              },
              false)
          }
        })
      }
    }
  }
}
