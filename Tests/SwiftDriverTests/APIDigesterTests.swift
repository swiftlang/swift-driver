//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(Testing) import SwiftDriver
import SwiftOptions
import TSCBasic
import TSCUtility
import TestUtilities
import Testing

@Suite struct APIDigesterTests {
  @Test func baselineGenerationRequiresTopLevelModule() async throws {
    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-emit-digester-baseline"]) {
      $1.expect(
        .error(
          "generating a baseline with '-emit-digester-baseline' is only supported with '-emit-module' or '-emit-module-path"
        )
      )
    }
    try await assertDriverDiagnostics(args: [
      "swiftc", "foo.swift", "-emit-digester-baseline-path", "/output/path.abi.json",
    ]) {
      $1.expect(
        .error(
          "generating a baseline with '-emit-digester-baseline-path' is only supported with '-emit-module' or '-emit-module-path"
        )
      )
    }
  }

  @Test func digesterModeValidation() async throws {
    try await assertDriverDiagnostics(args: [
      "swiftc", "foo.swift", "-emit-module", "-emit-digester-baseline", "-digester-mode", "notamode",
    ]) {
      $1.expect(.error("invalid value 'notamode' in '-digester-mode'"))
    }
    try await assertNoDriverDiagnostics(
      args: "swiftc",
      "foo.swift",
      "-emit-module",
      "-emit-digester-baseline",
      "-digester-mode",
      "api"
    )
    try await assertNoDriverDiagnostics(
      args: "swiftc",
      "foo.swift",
      "-emit-module",
      "-emit-module-interface",
      "-enable-library-evolution",
      "-emit-digester-baseline",
      "-digester-mode",
      "abi"
    )
  }

  @Test func abiDigesterRequirements() async throws {
    try await assertDriverDiagnostics(args: [
      "swiftc", "foo.swift", "-emit-module", "-emit-module-interface",
      "-emit-digester-baseline", "-digester-mode", "abi",
    ]) {
      $1.expect(.error("'-digester-mode abi' cannot be specified if '-enable-library-evolution' is not present"))
    }
    try await assertDriverDiagnostics(args: [
      "swiftc", "foo.swift", "-emit-module",
      "-enable-library-evolution", "-emit-digester-baseline", "-digester-mode", "abi",
    ]) {
      $1.expect(.error("'-digester-mode abi' cannot be specified if '-emit-module-interface' is not present"))
    }
  }

  @Test func baselineOutputPath() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-emit-digester-baseline"])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateAPIBaseline })
      #expect(digesterJob.commandLine.contains(subsequence: ["-o", try toPathOption("foo.api.json")]))
    }
    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-emit-module", "-emit-module-interface", "-enable-library-evolution",
        "-emit-digester-baseline", "-digester-mode", "abi",
      ])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateABIBaseline })
      #expect(digesterJob.commandLine.contains(subsequence: ["-o", try toPathOption("foo.abi.json")]))
    }
    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-emit-module", "-emit-digester-baseline-path", "bar.api.json",
      ])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateAPIBaseline })
      #expect(digesterJob.commandLine.contains(subsequence: ["-o", try toPathOption("bar.api.json")]))
    }
    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-emit-module", "-emit-module-interface", "-enable-library-evolution", "-digester-mode",
        "abi", "-emit-digester-baseline-path", "bar.abi.json",
      ])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateABIBaseline })
      #expect(digesterJob.commandLine.contains(subsequence: ["-o", try toPathOption("bar.abi.json")]))
    }
    do {
      try await withTemporaryDirectory { path in
        let projectDirPath = path.appending(component: "Project")
        try localFileSystem.createDirectory(projectDirPath)
        var driver = try TestDriver(args: [
          "swiftc", "-emit-module",
          path.appending(component: "foo.swift").pathString,
          "-emit-digester-baseline",
          "-o", path.appending(component: "foo.swiftmodule").pathString,
        ])
        let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateAPIBaseline })
        #expect(
          digesterJob.commandLine.contains(subsequence: [
            "-o", .path(.absolute(projectDirPath.appending(component: "foo.api.json"))),
          ])
        )
      }
    }
    do {
      try await withTemporaryDirectory { path in
        let projectDirPath = path.appending(component: "Project")
        try localFileSystem.createDirectory(projectDirPath)
        var driver = try TestDriver(args: [
          "swiftc", "-emit-module",
          "-emit-module-interface", "-enable-library-evolution",
          path.appending(component: "foo.swift").pathString,
          "-emit-digester-baseline",
          "-digester-mode", "abi",
          "-o", path.appending(component: "foo.swiftmodule").pathString,
        ])
        let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateABIBaseline })
        #expect(
          digesterJob.commandLine.contains(subsequence: [
            "-o", .path(.absolute(projectDirPath.appending(component: "foo.abi.json"))),
          ])
        )
      }
    }
    do {
      try await withTemporaryDirectory { path in
        let ofmPath = path.appending(component: "ofm.json")
        try localFileSystem.writeFileContents(ofmPath) {
          $0.send(
            """
            {
              "": {
                "abi-baseline-json": "/path/to/baseline.abi.json"
              }
            }
            """
          )
        }
        var driver = try TestDriver(args: [
          "swiftc", "-wmo", "-emit-module",
          "-emit-module-interface", "-enable-library-evolution",
          path.appending(component: "foo.swift").pathString,
          "-emit-digester-baseline",
          "-digester-mode", "abi",
          "-o", path.appending(component: "foo.swiftmodule").pathString,
          "-output-file-map", ofmPath.pathString,
        ])
        let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateABIBaseline })
        #expect(
          digesterJob.commandLine.contains(subsequence: [
            "-o", .path(.absolute(try .init(validating: "/path/to/baseline.abi.json"))),
          ])
        )
      }
    }
    do {
      try await withTemporaryDirectory { path in
        let ofmPath = path.appending(component: "ofm.json")
        try localFileSystem.writeFileContents(ofmPath) {
          $0.send(
            """
            {
              "": {
                "swiftsourceinfo": "/path/to/sourceinfo"
              }
            }
            """
          )
        }
        var driver = try TestDriver(args: [
          "swiftc", "-wmo", "-emit-module",
          "-emit-module-interface", "-enable-library-evolution",
          path.appending(component: "foo.swift").pathString,
          "-emit-digester-baseline",
          "-digester-mode", "abi",
          "-o", path.appending(component: "foo.swiftmodule").pathString,
          "-output-file-map", ofmPath.pathString,
        ])
        let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateABIBaseline })
        #expect(
          digesterJob.commandLine.contains(subsequence: [
            "-o", .path(.absolute(try .init(validating: "/path/to/sourceinfo.abi.json"))),
          ])
        )
      }
    }
  }

  @Test func baselineGenerationJobFlags() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-emit-module", "-emit-digester-baseline",
        "-sdk", "/path/to/sdk", "-I", "/some/path", "-F", "framework/path",
      ])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateAPIBaseline })
      #expect(digesterJob.commandLine.contains("-dump-sdk"))
      #expect(digesterJob.commandLine.contains(subsequence: ["-module", "foo"]))
      #expect(digesterJob.commandLine.contains(subsequence: ["-I", try toPathOption(".")]))
      #expect(
        digesterJob.commandLine.contains(subsequence: ["-sdk", .path(.absolute(try .init(validating: "/path/to/sdk")))])
      )
      #expect(
        digesterJob.commandLine.contains(subsequence: ["-I", .path(.absolute(try .init(validating: "/some/path")))])
      )
      #expect(digesterJob.commandLine.contains(subsequence: ["-F", try toPathOption("framework/path")]))
      #expect(digesterJob.commandLine.contains(subsequence: ["-o", try toPathOption("foo.api.json")]))

      #expect(!digesterJob.commandLine.contains("-abi"))
    }
    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-emit-module", "-emit-module-interface",
        "-enable-library-evolution", "-emit-digester-baseline",
        "-digester-mode", "abi",
        "-sdk", "/path/to/sdk", "-I", "/some/path", "-F", "framework/path",
      ])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .generateABIBaseline })
      #expect(digesterJob.commandLine.contains("-dump-sdk"))
      #expect(digesterJob.commandLine.contains(subsequence: ["-module", "foo"]))
      #expect(digesterJob.commandLine.contains(subsequence: ["-I", try toPathOption(".")]))
      #expect(
        digesterJob.commandLine.contains(subsequence: ["-sdk", .path(.absolute(try .init(validating: "/path/to/sdk")))])
      )
      #expect(
        digesterJob.commandLine.contains(subsequence: ["-I", .path(.absolute(try .init(validating: "/some/path")))])
      )
      #expect(digesterJob.commandLine.contains(subsequence: ["-F", try toPathOption("framework/path")]))
      #expect(digesterJob.commandLine.contains(subsequence: ["-o", try toPathOption("foo.abi.json")]))

      #expect(digesterJob.commandLine.contains("-abi"))
    }
  }

  @Test func comparisonOptionValidation() async throws {
    try await assertDriverDiagnostics(args: [
      "swiftc", "foo.swift",
      "-serialize-breaking-changes-path", "/path",
      "-digester-breakage-allowlist-path", "/path",
    ]) {
      $1.expect(
        .error("'-serialize-breaking-changes-path' cannot be specified if '-compare-to-baseline-path' is not present")
      )
      $1.expect(
        .error("'-digester-breakage-allowlist-path' cannot be specified if '-compare-to-baseline-path' is not present")
      )
    }
  }

  @Test(.requireHostOS(.macosx, comment: "ABI descriptor is only emitted on Darwin platforms"))
  func baselineComparisonJobFlags() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-emit-module", "-compare-to-baseline-path", "/baseline/path",
        "-sdk", "/path/to/sdk", "-I", "/some/path", "-F", "framework/path",
        "-digester-breakage-allowlist-path", "allowlist/path",
      ])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .compareAPIBaseline })
      #expect(digesterJob.commandLine.contains("-diagnose-sdk"))
      #expect(digesterJob.commandLine.contains(subsequence: ["-module", "foo"]))
      #expect(
        digesterJob.commandLine.contains(subsequence: [
          "-baseline-path", .path(.absolute(try .init(validating: "/baseline/path"))),
        ])
      )
      #expect(digesterJob.commandLine.contains(subsequence: ["-I", try toPathOption(".")]))
      #expect(
        digesterJob.commandLine.contains(subsequence: ["-sdk", .path(.absolute(try .init(validating: "/path/to/sdk")))])
      )
      #expect(
        digesterJob.commandLine.contains(subsequence: ["-I", .path(.absolute(try .init(validating: "/some/path")))])
      )
      #expect(digesterJob.commandLine.contains(subsequence: ["-F", try toPathOption("framework/path")]))
      #expect(
        digesterJob.commandLine.contains(subsequence: [
          "-breakage-allowlist-path",
          try toPathOption("allowlist/path"),
        ])
      )

      #expect(!digesterJob.commandLine.contains("-abi"))
    }
    do {
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "-emit-module", "-compare-to-baseline-path", "/baseline/path",
        "-emit-module-interface", "-enable-library-evolution",
        "-digester-mode", "abi",
        "-sdk", "/path/to/sdk", "-I", "/some/path", "-F", "framework/path",
        "-serialize-breaking-changes-path", "breaking-changes.dia",
        "-digester-breakage-allowlist-path", "allowlist/path",
      ])
      let digesterJob = try #require(await driver.planBuild().first { $0.kind == .compareABIBaseline })
      #expect(digesterJob.commandLine.contains("-diagnose-sdk"))
      #expect(
        digesterJob.commandLine.contains(subsequence: [
          "-input-paths", .path(.absolute(try .init(validating: "/baseline/path"))),
        ])
      )
      #expect(
        digesterJob.commandLine.contains(subsequence: [
          "-breakage-allowlist-path",
          try toPathOption("allowlist/path"),
        ])
      )
      #expect(digesterJob.commandLine.contains("-abi"))
      #expect(digesterJob.commandLine.contains("-serialize-diagnostics-path"))
    }
  }
}

@Suite struct APIDigesterBuildTests {
  @Test(.disabled("rdar://82302797")) func baselineGenerationEndToEnd() async throws {
    try await withTemporaryDirectory { path in
      let source = path.appending(component: "foo.swift")
      try localFileSystem.writeFileContents(source) {
        $0.send(
          """
          import C
          import E
          import G

          public struct MyStruct {}
          """
        )
      }

      let packageRootPath = URL(fileURLWithPath: #file).pathComponents
        .prefix(while: { $0 != "Tests" }).joined(separator: "/").dropFirst()
      let testInputsPath = packageRootPath + "/TestInputs"
      let cHeadersPath: String = testInputsPath + "/ExplicitModuleBuilds/CHeaders"
      let swiftModuleInterfacesPath: String = testInputsPath + "/ExplicitModuleBuilds/Swift"
      var driver = try TestDriver(args: [
        "swiftc",
        "-I", cHeadersPath,
        "-I", swiftModuleInterfacesPath,
        "-working-directory", path.pathString,
        source.pathString,
        "-emit-module",
        "-emit-digester-baseline",
      ])
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)
      let baseline = try localFileSystem.readFileContents(path.appending(component: "foo.api.json"))
      try baseline.withData {
        let json = try JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any]
        #expect((json?["children"] as? [Any])!.count >= 1)
      }
    }
  }

  @Test(.disabled("rdar://82302797"), .requireFrontendArgSupport(.disableFailOnError)) func apiComparisonEndToEnd()
    async throws
  {
    try await withTemporaryDirectory { path in
      let source = path.appending(component: "foo.swift")
      try localFileSystem.writeFileContents(source) {
        $0.send(
          """
          public struct MyStruct {
            public var a: Int
          }
          """
        )
      }
      var driver = try TestDriver(args: [
        "swiftc",
        "-working-directory", path.pathString,
        source.pathString,
        "-emit-module",
        "-emit-digester-baseline",
      ])
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      try localFileSystem.writeFileContents(source) {
        $0.send(
          """
          public struct MyStruct {
            public var a: Bool
          }
          """
        )
      }
      var driver2 = try TestDriver(args: [
        "swiftc",
        "-working-directory", path.pathString,
        source.pathString,
        "-emit-module",
        "-compare-to-baseline-path",
        path.appending(component: "foo.api.json").pathString,
        "-serialize-breaking-changes-path",
        path.appending(component: "changes.dia").pathString,
      ])
      let jobs2 = try await driver2.planBuild()
      try await driver2.run(jobs: jobs2)
      #expect(!driver2.diagnosticEngine.hasErrors)
      let contents = try localFileSystem.readFileContents(path.appending(component: "changes.dia"))
      let diags = try SerializedDiagnostics(bytes: contents)
      #expect(
        diags.diagnostics.map(\.text) == [
          "API breakage: var MyStruct.a has declared type change from Swift.Int to Swift.Bool",
          "API breakage: accessor MyStruct.a.Get() has return type change from Swift.Int to Swift.Bool",
          "API breakage: accessor MyStruct.a.Set() has parameter 0 type change from Swift.Int to Swift.Bool",
        ]
      )
    }
  }

  @Test(.disabled("rdar://82302797"), .requireFrontendArgSupport(.disableFailOnError)) func abiComparisonEndToEnd()
    async throws
  {
    try await withTemporaryDirectory { path in
      let source = path.appending(component: "foo.swift")
      let allowlist = path.appending(component: "allowlist.txt")
      try localFileSystem.writeFileContents(source) {
        $0.send(
          """
          @frozen public struct MyStruct {
            var a: Int
            var b: String
            var c: Int
          }
          """
        )
      }
      try localFileSystem.writeFileContents(allowlist) {
        $0.send("ABI breakage: var MyStruct.c has declared type change from Swift.Int to Swift.String")
      }
      var driver = try TestDriver(args: [
        "swiftc",
        "-working-directory", path.pathString,
        source.pathString,
        "-emit-module",
        "-emit-module-interface",
        "-enable-library-evolution",
        "-emit-digester-baseline",
        "-digester-mode", "abi",
      ])
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)

      try localFileSystem.writeFileContents(source) {
        $0.send(
          """
          @frozen public struct MyStruct {
            var b: String
            var a: Int
            var c: String
          }
          """
        )
      }
      var driver2 = try TestDriver(args: [
        "swiftc",
        "-working-directory", path.pathString,
        source.pathString,
        "-emit-module",
        "-emit-module-interface",
        "-enable-library-evolution",
        "-compare-to-baseline-path",
        path.appending(component: "foo.abi.json").pathString,
        "-serialize-breaking-changes-path",
        path.appending(component: "changes.dia").pathString,
        "-digester-breakage-allowlist-path",
        allowlist.pathString,
        "-digester-mode", "abi",
      ])
      let jobs2 = try await driver2.planBuild()
      try await driver2.run(jobs: jobs2)
      #expect(!driver2.diagnosticEngine.hasErrors)
      let contents = try localFileSystem.readFileContents(path.appending(component: "changes.dia"))
      let diags = try SerializedDiagnostics(bytes: contents)
      let messages = diags.diagnostics.map(\.text)
      #expect(messages.contains("ABI breakage: var MyStruct.a in a non-resilient type changes position from 0 to 1"))
      #expect(messages.contains("ABI breakage: var MyStruct.b in a non-resilient type changes position from 1 to 0"))
    }
  }
}
