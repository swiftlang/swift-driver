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
import SwiftOptions
import TestUtilities

/// Testing the misc machinery for incremental compilation.
@Suite struct IncrementalMiscTests {
  @Test func readBinarySourceFileDependencyGraph() async throws {
    let absolutePath = try #require(Fixture.fixturePath(at: try RelativePath(validating: "Incremental"),
                                                         for: "main.swiftdeps"))
    let typedFile = TypedVirtualPath(file: VirtualPath.absolute(absolutePath).intern(), type: .swiftDeps)
    try MockIncrementalCompilationSynchronizer.withInternedStringTable { internedStringTable in
      let graph = try #require(
        try SourceFileDependencyGraph(
          contentsOf: typedFile,
          on: localFileSystem,
          internedStringTable: internedStringTable))
      #expect(graph.majorVersion == 1)
      #expect(graph.minorVersion == 0)
      #expect(graph.compilerVersionString == "Swift version 5.3-dev (LLVM f516ac602c, Swift c39f31febd)")
      graph.verify()
      var saw0 = false
      var saw1 = false
      var saw2 = false
      graph.forEachNode { node in
        switch (node.sequenceNumber, node.key.designator) {
        case let (0, .sourceFileProvide(name: name)):
          saw0 = true
          #expect(node.key.aspect == .interface)
          #expect(name.lookup(in: internedStringTable) == "main.swiftdeps")
          #expect(node.fingerprint?.lookup(in: internedStringTable) == "ec443bb982c3a06a433bdd47b85eeba2")
          #expect(node.defsIDependUpon == [2])
          #expect(node.definitionVsUse == .definition)
        case let (1, .sourceFileProvide(name: name)):
          saw1 = true
          #expect(node.key.aspect == .implementation)
          #expect(name.lookup(in: internedStringTable) == "main.swiftdeps")
          #expect(node.fingerprint?.lookup(in: internedStringTable) == "ec443bb982c3a06a433bdd47b85eeba2")
          #expect(node.defsIDependUpon == [])
          #expect(node.definitionVsUse == .definition)
        case let (2, .topLevel(name: name)):
          saw2 = true
          #expect(node.key.aspect == .interface)
          #expect(name.lookup(in: internedStringTable) == "a")
          #expect(node.fingerprint == nil)
          #expect(node.defsIDependUpon == [])
          #expect(node.definitionVsUse == .use)
        default:
          Issue.record()
        }
      }
      #expect(saw0)
      #expect(saw1)
      #expect(saw2)
    }
  }

  @Test func readComplexSourceFileDependencyGraph() async throws {
    let absolutePath = try #require(Fixture.fixturePath(at: try RelativePath(validating: "Incremental"),
                                                         for: "hello.swiftdeps"))
    try MockIncrementalCompilationSynchronizer.withInternedStringTable{ internedStringTable in
      let graph = try #require(
        try SourceFileDependencyGraph(
          contentsOf: TypedVirtualPath(file: VirtualPath.absolute(absolutePath).intern(), type: .swiftDeps),
          on: localFileSystem,
          internedStringTable: internedStringTable))
      #expect(graph.majorVersion == 1)
      #expect(graph.minorVersion == 0)
      #expect(graph.compilerVersionString == "Swift version 5.3-dev (LLVM 4510748e505acd4, Swift 9f07d884c97eaf4)")
      graph.verify()

      // Check that a node chosen at random appears as expected.
      var foundNode = false
      graph.forEachNode { node in
        if case let .member(context: context, name: name) = node.key.designator,
           node.sequenceNumber == 25
        {
          #expect(!foundNode)
          foundNode = true
          #expect(node.key.aspect == .interface)
          #expect(context.lookup(in: internedStringTable) == "5hello1BV")
          #expect(name.lookup(in: internedStringTable) == "init")
          #expect(node.defsIDependUpon == [])
          #expect(node.definitionVsUse == .use)
        }
      }
      #expect(foundNode)

      // Check that an edge chosen at random appears as expected.
      var foundEdge = false
      graph.forEachArc { defNode, useNode in
        if defNode.sequenceNumber == 0 && useNode.sequenceNumber == 10 {
          switch (defNode.key.designator, useNode.key.designator) {
          case let (.sourceFileProvide(name: defName),
                    .potentialMember(context: useContext)):
            #expect(!foundEdge)
            foundEdge = true

            #expect(defName.lookup(in: internedStringTable) == "/Users/owenvoorhees/Desktop/hello.swiftdeps")
            #expect(defNode.fingerprint?.lookup(in: internedStringTable) == "38b457b424090ac2e595be0e5f7e3b5b")

            #expect(useContext.lookup(in: internedStringTable) == "5hello1AC")
            #expect(useNode.fingerprint?.lookup(in: internedStringTable) == "b83bbc0b4b0432dbfabff6556a3a901f")

          default:
            Issue.record()
          }
        }
      }
      #expect(foundEdge)
    }
  }

  @Test func extractSourceFileDependencyGraphFromSwiftModule() async throws {
    let absolutePath = try #require(Fixture.fixturePath(at: try RelativePath(validating: "Incremental"),
                                                         for: "hello.swiftmodule"))
    let data = try localFileSystem.readFileContents(absolutePath)
    try MockIncrementalCompilationSynchronizer.withInternedStringTable { internedStringTable in
      let graph = try #require(
        try SourceFileDependencyGraph(internedStringTable: internedStringTable,
                                      data: data,
                                      fromSwiftModule: true))
      #expect(graph.majorVersion == 1)
      #expect(graph.minorVersion == 0)
      #expect(graph.compilerVersionString == "Apple Swift version 5.3-dev (LLVM 240312aa7333e90, Swift 15bf0478ad7c47c)")
      graph.verify()

      // Check that a node chosen at random appears as expected.
      var foundNode = false
      graph.forEachNode { node in
        if case .nominal(context: "5hello3FooV".intern(in: internedStringTable)) = node.key.designator,
           node.sequenceNumber == 4
        {
          #expect(!foundNode)
          foundNode = true
          #expect(node.key.aspect == .interface)
          #expect(node.defsIDependUpon == [0])
          #expect(node.definitionVsUse == .definition)
        }
      }
      #expect(foundNode)
    }
  }

  @Test func dateConversion() {
    let sn = TimePoint(seconds: 0, nanoseconds: 8000)
    #expect(sn.seconds == 0)
    #expect(sn.nanoseconds == 8000)
  }

  @Test func zeroDuration() {
    #expect(TimePoint.zero == TimePoint.seconds(0))
    #expect(TimePoint.zero == TimePoint.nanoseconds(0))
  }

  @Test func durationSecondsArithmetic() {
    let x = TimePoint.seconds(1)
    #expect(TimePoint.zero + x == x)
    #expect(x + TimePoint.zero == x)
    #expect(x - TimePoint.zero == x)

    let y = TimePoint.nanoseconds(1)
    let z = TimePoint.nanoseconds(2_000_000)
    #expect(x + (y + z) == (x + y) + z)
  }

  @Test func durationComparison() {
    let x = TimePoint.seconds(1)
    let y = TimePoint.nanoseconds(500)

    #expect((x < y) == !(x >= y))
  }

  @Test func durationOverflow() {
    #expect(TimePoint.nanoseconds(1_000_000_000) == TimePoint.seconds(1))
    #expect(TimePoint.nanoseconds(500_000_000) + TimePoint.nanoseconds(500_000_000) == TimePoint.seconds(1))
    #expect(TimePoint.nanoseconds(1_500_000_000) + TimePoint.nanoseconds(500_000_000) == TimePoint.seconds(2))
  }
}

/// Testing the machinery for incremental compilation with nonincremental test cases.
@Suite(.enabled(if: sdkArgumentsAvailable)) struct NonincrementalCompilationTests {
  /// Run a test with two files, main and other.swift, passing on the additional arguments
  /// expecting certain diagnostics.
  private func runDriver(
    with otherArgs: [String],
    expecting expectations: [Diagnostic.Message],
    alsoExpectingWhenAutolinking autolinkExpectations: [Diagnostic.Message] = []
  ) async throws {
    let sdkArguments = try #require(try Driver.sdkArgumentsForTesting())
    try await withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main, bytes: "let foo = 1")
      let other = path.appending(component: "other.swift")
      try localFileSystem.writeFileContents(other, bytes: "let bar = 2")

      try await assertDriverDiagnostics(args: [
        "swiftc", "-module-name", "theModule", "-working-directory", path.pathString,
        main.pathString, other.pathString
      ] + otherArgs + sdkArguments) {driver, verifier in
        verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)

        expectations.forEach {verifier.expect($0)}
        if driver.isAutolinkExtractJobNeeded {
          autolinkExpectations.forEach {verifier.expect($0)}
        }

        let jobs = try await driver.planBuild()
        try await driver.run(jobs: jobs)
      }
    }
  }

  @Test func showJobLifecycleAndIncremental() async throws {
    // Legacy MacOS driver output:
    //    Adding standard job to task queue: {compile: main.o <= main.swift}
    //    Added to TaskQueue: {compile: main.o <= main.swift}
    //    Adding standard job to task queue: {compile: other.o <= other.swift}
    //    Added to TaskQueue: {compile: other.o <= other.swift}
    //    Job finished: {compile: main.o <= main.swift}
    //    Job finished: {compile: other.o <= other.swift}

    try await runDriver( with: [
      "-c",
      "-driver-show-job-lifecycle",
      "-driver-show-incremental",
    ],
    expecting: [
      .remark("Starting Compiling main.swift"),
      .remark("Finished Compiling main.swift"),
      .remark("Starting Compiling other.swift"),
      .remark("Finished Compiling other.swift"),
    ],
    alsoExpectingWhenAutolinking: [
      .remark("Starting Extracting autolink information for module theModule"),
      .remark("Finished Extracting autolink information for module theModule"),
    ])

  }
  @Test func noIncremental() async throws {
    try await runDriver( with: [
      "-c",
      "-incremental",
    ],
    expecting: [
      .warning("ignoring -incremental (currently requires an output file map)")
    ])
    // Legacy driver output:
    //    <unknown>:0: warning: ignoring -incremental (currently requires an output file map)
  }
}
