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
import SwiftDriver
import SwiftOptions
import TSCBasic
import XCTest

final class SwiftDriverToolingInterfaceTests: XCTestCase {
  func testCreateCompilerInvocation() throws {
    try withTemporaryDirectory { path in
      let inputFile = path.appending(components: "test.swift")
      try localFileSystem.writeFileContents(inputFile) { $0 <<< "public func foo()" }
      
      // Expected success scenarios:
      do {
        let testCommand = inputFile.description
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArguments(argList: testCommand.components(separatedBy: " "),
                                                                      outputFrontendArgs: &resultingFrontendArgs,
                                                                      emittedDiagnostics: &emittedDiagnostics))
      }
      do {
        let testCommand = "-emit-executable " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header -o t.out"
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArguments(argList: testCommand.components(separatedBy: " "),
                                                                      outputFrontendArgs: &resultingFrontendArgs,
                                                                      emittedDiagnostics: &emittedDiagnostics))
      }
      do {
        let testCommand = "-c " + inputFile.description + " main.swift lib.swift -module-name createCompilerInvocation -emit-module -emit-objc-header"
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArguments(argList: testCommand.components(separatedBy: " "),
                                                                      outputFrontendArgs: &resultingFrontendArgs,
                                                                      emittedDiagnostics: &emittedDiagnostics))
      }
      do {
        let testCommand = inputFile.description + " -enable-batch-mode"
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArguments(argList: testCommand.components(separatedBy: " "),
                                                                      outputFrontendArgs: &resultingFrontendArgs,
                                                                      emittedDiagnostics: &emittedDiagnostics))
      }
      do { // Force no outputs
        let testCommand = "-module-name foo -emit-module -emit-module-path /tmp/foo.swiftmodule -emit-objc-header -emit-objc-header-path /tmp/foo.h -enable-library-evolution -emit-module-interface -emit-module-interface-path /tmp/foo.swiftinterface -emit-library -emit-tbd -emit-tbd-path /tmp/foo.tbd -emit-dependencies -serialize-diagnostics " + inputFile.description
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertFalse(getSingleFrontendInvocationFromDriverArguments(argList: testCommand.components(separatedBy: " "),
                                                                      outputFrontendArgs: &resultingFrontendArgs,
                                                                      emittedDiagnostics: &emittedDiagnostics,
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
        var resultingFrontendArgs: [String] = []
        var emittedDiagnostics: [Diagnostic] = []
        XCTAssertTrue(getSingleFrontendInvocationFromDriverArguments(argList: testCommand.components(separatedBy: " "),
                                                                     outputFrontendArgs: &resultingFrontendArgs,
                                                                     emittedDiagnostics: &emittedDiagnostics))
        let errorMessage = try XCTUnwrap(emittedDiagnostics.first?.message.text)
        XCTAssertEqual(errorMessage, "unable to handle compilation, expected exactly one frontend job")
      }
    }
  }
}
