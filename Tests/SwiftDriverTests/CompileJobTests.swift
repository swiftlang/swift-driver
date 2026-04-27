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

import SwiftOptions
import TSCBasic
import TestUtilities
import Testing

@testable @_spi(Testing) import SwiftDriver

@Suite struct CompileJobTests {

  private var ld: AbsolutePath { get throws { try makeLdStub() } }

  @Test func standardCompileJobs() async throws {
    var driver1 = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test"])
    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 3)
    #expect(plannedJobs[0].outputs.count == 1)
    #expect(!plannedJobs[0].commandLine.contains(.flag("-resource-dir")))
    #expect(matchTemporary(plannedJobs[0].outputs.first!.file, "foo.o"))
    #expect(plannedJobs[1].outputs.count == 1)
    #expect(!plannedJobs[1].commandLine.contains(.flag("-resource-dir")))
    #expect(matchTemporary(plannedJobs[1].outputs.first!.file, "bar.o"))
    #expect(plannedJobs[2].tool.name.contains(executableName("clang")))
    #expect(plannedJobs[2].outputs.count == 1)
    #expect(try plannedJobs[2].outputs.first!.file == toPath(executableName("Test")))

    // Forwarding of arguments.
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "tmp")

    var driver2 = try TestDriver(args: [
      "swiftc", "-color-diagnostics", "foo.swift", "bar.swift", "-working-directory", workingDirectory.pathString,
      "-api-diff-data-file", "diff.txt", "-Xfrontend", "-HI", "-no-color-diagnostics", "-g",
    ])
    let plannedJobs2 = try await driver2.planBuild()
    let compileJob = try plannedJobs2.findJob(.compile)
    #expect(
      compileJob.commandLine.contains(
        Job.ArgTemplate.path(.absolute(try AbsolutePath(validating: rebase("diff.txt", at: workingDirectory))))
      )
    )
    #expect(compileJob.commandLine.contains(.flag("-HI")))
    #expect(!compileJob.commandLine.contains(.flag("-Xfrontend")))
    #expect(compileJob.commandLine.contains(.flag("-no-color-diagnostics")))
    #expect(!compileJob.commandLine.contains(.flag("-color-diagnostics")))
    #expect(compileJob.commandLine.contains(.flag("-target")))
    #expect(compileJob.commandLine.contains(.flag(driver2.targetTriple.triple)))
    #expect(compileJob.commandLine.contains(.flag("-enable-anonymous-context-mangled-names")))

    var driver3 = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-module-name", "Test"])
    let plannedJobs3 = try await driver3.planBuild()
    expectJobInvocationMatches(plannedJobs3[0], .flag("-module-name"), .flag("Test"))
    expectJobInvocationMatches(plannedJobs3[0], .flag("-parse-as-library"))
  }

  @Test func emitModuleSeparatelyDiagnosticPath() async throws {
    try await withTemporaryDirectory { dir in
      let fileMapFile = dir.appending(component: "file-map-file")
      let outputMapContents: ByteString = """
        {
          "": {
            "diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.dia",
            "emit-module-diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.dia"
          },
          "foo.swift": {
            "diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.dia"
          }
        }
        """
      try localFileSystem.writeFileContents(fileMapFile, bytes: outputMapContents)

      // Plain (batch/single-file) compile
      do {
        var driver = try TestDriver(args: [
          "swiftc", "foo.swift", "-emit-module", "-output-file-map", fileMapFile.pathString,
          "-emit-library", "-module-name", "Test", "-serialize-diagnostics",
        ])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        #expect(plannedJobs.count == 3)
        #expect(plannedJobs[0].kind == .emitModule)
        #expect(plannedJobs[1].kind == .compile)
        #expect(plannedJobs[2].kind == .link)
        try expectJobInvocationMatches(
          plannedJobs[0],
          .flag("-serialize-diagnostics-path"),
          .path(
            .absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.dia"))
          )
        )
        try expectJobInvocationMatches(
          plannedJobs[1],
          .flag("-serialize-diagnostics-path"),
          .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.dia")))
        )
      }

      // WMO
      do {
        var driver = try TestDriver(args: [
          "swiftc", "foo.swift", "-whole-module-optimization", "-emit-module",
          "-output-file-map", fileMapFile.pathString, "-disable-cmo",
          "-emit-library", "-module-name", "Test", "-serialize-diagnostics",
        ])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        #expect(plannedJobs.count == 3)
        #expect(plannedJobs[0].kind == .compile)
        #expect(plannedJobs[1].kind == .emitModule)
        #expect(plannedJobs[2].kind == .link)
        try expectJobInvocationMatches(
          plannedJobs[0],
          .flag("-serialize-diagnostics-path"),
          .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.dia")))
        )
        try expectJobInvocationMatches(
          plannedJobs[1],
          .flag("-serialize-diagnostics-path"),
          .path(
            .absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.dia"))
          )
        )
      }
    }
  }

  @Test func emitModuleSeparatelyDependenciesPath() async throws {
    try await withTemporaryDirectory { dir in
      let fileMapFile = dir.appending(component: "file-map-file")
      let outputMapContents: ByteString = """
        {
          "": {
            "dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.d",
            "emit-module-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.d"
          },
          "foo.swift": {
            "dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d"
          }
        }
        """
      try localFileSystem.writeFileContents(fileMapFile, bytes: outputMapContents)

      // Plain (batch/single-file) compile
      do {
        var driver = try TestDriver(args: [
          "swiftc", "foo.swift", "-emit-module", "-output-file-map", fileMapFile.pathString,
          "-emit-library", "-module-name", "Test", "-emit-dependencies",
        ])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        #expect(plannedJobs.count == 3)
        #expect(plannedJobs[0].kind == .emitModule)
        #expect(plannedJobs[1].kind == .compile)
        #expect(plannedJobs[2].kind == .link)
        try expectJobInvocationMatches(
          plannedJobs[0],
          .flag("-emit-dependencies-path"),
          .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.d")))
        )
        try expectJobInvocationMatches(
          plannedJobs[1],
          .flag("-emit-dependencies-path"),
          .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d")))
        )
      }

      // WMO
      do {
        var driver = try TestDriver(args: [
          "swiftc", "foo.swift", "-whole-module-optimization", "-emit-module",
          "-output-file-map", fileMapFile.pathString, "-disable-cmo",
          "-emit-library", "-module-name", "Test", "-emit-dependencies",
        ])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        #expect(plannedJobs.count == 3)
        #expect(plannedJobs[0].kind == .compile)
        #expect(plannedJobs[1].kind == .emitModule)
        #expect(plannedJobs[2].kind == .link)
        try expectJobInvocationMatches(
          plannedJobs[0],
          .flag("-emit-dependencies-path"),
          .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.d")))
        )
        try expectJobInvocationMatches(
          plannedJobs[1],
          .flag("-emit-dependencies-path"),
          .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.d")))
        )
      }
    }
  }

  @Test func batchModeCompiles() async throws {
    do {
      var driver1 = try TestDriver(args: [
        "swiftc", "foo1.swift", "bar1.swift", "foo2.swift", "bar2.swift", "foo3.swift", "bar3.swift", "foo4.swift",
        "bar4.swift", "foo5.swift", "bar5.swift", "wibble.swift", "-module-name", "Test", "-enable-batch-mode",
        "-driver-batch-count", "3",
      ])
      let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 4)
      #expect(plannedJobs[0].outputs.count == 4)
      #expect(matchTemporary(plannedJobs[0].outputs.first!.file, "foo1.o"))
      expectEqual(plannedJobs[1].outputs.count, 4)
      #expect(matchTemporary(plannedJobs[1].outputs.first!.file, "foo3.o"))
      #expect(plannedJobs[2].outputs.count == 3)
      #expect(matchTemporary(plannedJobs[2].outputs.first!.file, "foo5.o"))
      #expect(plannedJobs[3].tool.name.contains("clang"))
      expectEqual(plannedJobs[3].outputs.count, 1)
      try expectEqual(plannedJobs[3].outputs.first!.file, try toPath(executableName("Test")))
    }

    // Test 1 partition results in 1 job
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-toolchain-stdlib-rpath", "-module-cache-path", "/tmp/clang-module-cache", "-swift-version", "4",
        "-Xfrontend", "-ignore-module-source-info", "-module-name", "batch", "-enable-batch-mode", "-j", "1", "-c",
        "main.swift", "lib.swift",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 1)
      var count = 0
      for arg in plannedJobs[0].commandLine where arg == .flag("-primary-file") {
        count += 1
      }
      expectEqual(count, 2)
    }
  }

  @Test func batchModeDiagnostics() async throws {
    try await assertNoDriverDiagnostics(args: "swiftc", "-enable-batch-mode") { driver in
      switch driver.compilerMode {
      case .batchCompile:
        break
      default:
        Issue.record("Expected batch compile, got \(driver.compilerMode)")
      }
    }

    try await assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-whole-module-optimization") {
      driver,
      diagnostics in
      #expect(driver.compilerMode == .singleCompile)
      diagnostics.expect(
        .warning("ignoring '-enable-batch-mode' because '-whole-module-optimization' was also specified")
      )
    }

    try await assertDriverDiagnostics(
      args: "swiftc",
      "-enable-batch-mode",
      "-whole-module-optimization",
      "-no-whole-module-optimization",
      "-index-file",
      "-module-name",
      "foo"
    ) { driver, diagnostics in
      #expect(driver.compilerMode == .singleCompile)
      diagnostics.expect(.warning("ignoring '-enable-batch-mode' because '-index-file' was also specified"))
    }

    try await assertNoDriverDiagnostics(
      args: "swiftc",
      "-enable-batch-mode",
      "-whole-module-optimization",
      "-no-whole-module-optimization"
    ) { driver in
      switch driver.compilerMode {
      case .batchCompile:
        break
      default:
        Issue.record("Expected batch compile, got \(driver.compilerMode)")
      }
    }
  }

  @Test func singleThreadedWholeModuleOptimizationCompiles() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)
    var driver1 = try TestDriver(
      args: [
        "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "-emit-library", "-emit-module",
        "-module-name", "Test", "-emit-module-interface", "-emit-objc-header-path", "Test-Swift.h",
        "-emit-private-module-interface-path", "Test.private.swiftinterface", "-emit-tbd", "-o", "libTest",
      ],
      env: envVars
    )
    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 3)
    expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

    #expect(plannedJobs[0].kind == .compile)
    #expect(plannedJobs[0].outputs.count == 1)
    #expect(matchTemporary(plannedJobs[0].outputs[0].file, "Test.o"))
    #expect(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

    let emitModuleJob = try plannedJobs.findJob(.emitModule)
    expectEqual(emitModuleJob.outputs.count, driver1.targetTriple.isDarwin ? 8 : 7)
    #expect(try emitModuleJob.outputs[0].file == toPath("Test.swiftmodule"))
    #expect(try emitModuleJob.outputs[1].file == toPath("Test.swiftdoc"))
    #expect(try emitModuleJob.outputs[2].file == toPath("Test.swiftsourceinfo"))
    #if os(Windows)
    #expect(try emitModuleJob.outputs[3].file == toPath("Test.swiftinterface"))
    #else
    #expect(try emitModuleJob.outputs[3].file == VirtualPath(path: "./Test.swiftinterface"))
    #endif
    #expect(try emitModuleJob.outputs[4].file == toPath("Test.private.swiftinterface"))
    #expect(try emitModuleJob.outputs[5].file == toPath("Test-Swift.h"))
    #if os(Windows)
    #expect(try emitModuleJob.outputs[6].file == toPath("Test.tbd"))
    #else
    #expect(try emitModuleJob.outputs[6].file == VirtualPath(path: "./Test.tbd"))
    #endif
    if driver1.targetTriple.isDarwin {
      try expectEqual(emitModuleJob.outputs[7].file, try toPath("Test.abi.json"))
    }
    #expect(!emitModuleJob.commandLine.contains(.flag("-primary-file")))
    expectJobInvocationMatches(emitModuleJob, .flag("-emit-module-interface-path"))
    expectJobInvocationMatches(emitModuleJob, .flag("-emit-private-module-interface-path"))
  }

  @Test func multiThreadedWholeModuleOptimizationCompiles() async throws {
    do {
      var driver1 = try TestDriver(args: [
        "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift",
        "-module-name", "Test", "-num-threads", "4",
      ])
      let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)
      #expect(plannedJobs[0].outputs.count == 3)
      #expect(matchTemporary(plannedJobs[0].outputs[0].file, "foo.o"))
      #expect(matchTemporary(plannedJobs[0].outputs[1].file, "bar.o"))
      #expect(matchTemporary(plannedJobs[0].outputs[2].file, "wibble.o"))
      #expect(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

      #expect(plannedJobs[1].kind == .link)
    }

    // emit-module
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-module-name=ThisModule", "-wmo", "-num-threads", "4", "main.swift", "multi-threaded.swift",
        "-emit-module", "-o", "test.swiftmodule",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      expectEqual(plannedJobs[0].inputs.count, 2)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("main.swift"))
      try expectEqual(plannedJobs[0].inputs[1].file, try toPath("multi-threaded.swift"))
      #expect(plannedJobs[0].outputs.count == (driver.targetTriple.isDarwin ? 4 : 3))
      #expect(try plannedJobs[0].outputs[0].file == toPath("test.swiftmodule"))
    }
  }

  @Test func wholeModuleOptimizationOutputFileMap() async throws {
    let contents = ByteString(
      """
      {
        "": {
          "swiftinterface": "/tmp/salty/Test.swiftinterface"
        }
      }
      """.utf8
    )

    try await withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try await assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file, bytes: contents)
        var driver1 = try TestDriver(args: [
          "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
          "-num-threads", "4", "-output-file-map", file.pathString, "-emit-module-interface",
        ])
        let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
        #expect(plannedJobs.count == 3)
        expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

        #expect(plannedJobs[0].kind == .compile)
        #expect(plannedJobs[0].outputs.count == 3)
        #expect(matchTemporary(plannedJobs[0].outputs[0].file, "foo.o"))
        #expect(matchTemporary(plannedJobs[0].outputs[1].file, "bar.o"))
        #expect(matchTemporary(plannedJobs[0].outputs[2].file, "wibble.o"))
        #expect(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

        let emitModuleJob = plannedJobs.first(where: { $0.kind == .emitModule })!
        #expect(
          emitModuleJob.outputs[3].file == VirtualPath.absolute(try .init(validating: "/tmp/salty/Test.swiftinterface"))
        )
        #expect(!emitModuleJob.commandLine.contains(.flag("-primary-file")))
        #expect(plannedJobs[2].kind == .link)
      }
    }
  }

  @Test func wholeModuleOptimizationUsingSupplementaryOutputFileMap() async throws {
    var driver1 = try TestDriver(args: [
      "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
      "-emit-module-interface", "-driver-filelist-threshold=0",
    ])
    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 3)
    #expect(plannedJobs[0].kind == .compile)
    #expect(plannedJobs[0].commandLine.contains(.flag("-supplementary-output-file-map")))
  }

  @Test func wmoWithNonSourceInput() async throws {
    var driver1 = try TestDriver(args: [
      "swiftc", "-whole-module-optimization", "danger.o", "foo.swift", "bar.swift", "wibble.swift", "-module-name",
      "Test",
      "-driver-filelist-threshold=0",
    ])
    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 2)
    let compileJob = plannedJobs[0]
    expectEqual(compileJob.kind, .compile)
    let outFileMap = try compileJob.commandLine.supplementaryOutputFilemap
    let firstKey: String = VirtualPath.lookup(try #require(outFileMap.entries.keys.first)).basename
    expectEqual(firstKey, "foo.swift")
  }

  @Test func explicitBuildWithJustObjectInputs() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-explicit-module-build", "foo.o", "bar.o",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 1)
    expectEqual(plannedJobs.first?.kind, .link)
  }

  @Test func wmoWithNonSourceInputFirstAndModuleOutput() async throws {
    var driver1 = try TestDriver(args: [
      "swiftc", "-wmo", "danger.o", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
      "-driver-filelist-threshold=0", "-emit-module", "-emit-library", "-no-emit-module-separately-wmo",
    ])
    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 2)
    let compileJob = plannedJobs[0]
    expectEqual(compileJob.kind, .compile)
    #expect(compileJob.commandLine.contains(.flag("-supplementary-output-file-map")))
    let argIdx = try #require(
      compileJob.commandLine.firstIndex(where: { $0 == .flag("-supplementary-output-file-map") })
    )
    let supplOutputs = compileJob.commandLine[argIdx + 1]
    guard case let .path(path) = supplOutputs,
      case let .fileList(_, fileList) = path,
      case let .outputFileMap(outFileMap) = fileList
    else {
      throw StringError("Unexpected argument for output file map")
    }
    let firstKeyHandle = try #require(outFileMap.entries.keys.first)
    let firstKey = VirtualPath.lookup(firstKeyHandle).basename
    expectEqual(firstKey, "foo.swift")
    let firstKeyOutputs = try #require(outFileMap.entries[firstKeyHandle])
    #expect(firstKeyOutputs.keys.contains(where: { $0 == .swiftModule }))
  }

  @Test func wmoWithJustObjectInputs() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-wmo", "foo.o", "bar.o",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 1)
    expectEqual(plannedJobs.first?.kind, .link)
  }

  @Test func emitModuleSeparately() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      var driver = try TestDriver(
        args: [
          "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
          rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", "/foo/bar/",
          "-experimental-emit-module-separately", "-emit-library",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 4)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))
      #expect(plannedJobs[0].tool.name.contains("swift"))
      expectJobInvocationMatches(plannedJobs[0], .flag("-parse-as-library"))
      #expect(plannedJobs[0].outputs.count == (driver.targetTriple.isDarwin ? 4 : 3))
      let module: VirtualPath = .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))
      #expect(plannedJobs[0].outputs[0].file == module)
      try expectEqual(
        plannedJobs[0].outputs[1].file,
        .absolute(try .init(validating: rebase("Test.swiftdoc", at: root)))
      )
      try expectEqual(
        plannedJobs[0].outputs[2].file,
        .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))
      )
      if driver.targetTriple.isDarwin {
        try expectEqual(
          plannedJobs[0].outputs[3].file,
          .absolute(try .init(validating: rebase("Test.abi.json", at: root)))
        )
      }

      // We don't know the output file of the symbol graph, just make sure the flag is passed along.
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-symbol-graph"))
    }

    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      // We don't expect partial jobs when asking only for the swiftmodule with
      // -experimental-emit-module-separately.
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-experimental-emit-module-separately",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.emitModule, .compile]))
      #expect(plannedJobs[0].tool.name.contains("swift"))
      #expect(plannedJobs[0].outputs.count == (driver.targetTriple.isDarwin ? 4 : 3))
      let module: VirtualPath = .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))
      #expect(plannedJobs[0].outputs[0].file == module)
      try expectEqual(
        plannedJobs[0].outputs[1].file,
        .absolute(try .init(validating: rebase("Test.swiftdoc", at: root)))
      )
      try expectEqual(
        plannedJobs[0].outputs[2].file,
        .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))
      )
      if driver.targetTriple.isDarwin {
        try expectEqual(
          plannedJobs[0].outputs[3].file,
          .absolute(try .init(validating: rebase("Test.abi.json", at: root)))
        )
      }
    }

    do {
      // Calls using the driver to link a library shouldn't trigger an emit-module job, like in LLDB tests.
      var driver = try TestDriver(
        args: [
          "swiftc", "-emit-library", "foo.swiftmodule", "foo.o", "-emit-module-path", "foo.swiftmodule",
          "-experimental-emit-module-separately", "-target", "x86_64-apple-macosx10.15", "-module-name", "Test",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 1)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.link]))
    }

    do {
      // Use emit-module to build sil files.
      var driver = try TestDriver(
        args: [
          "swiftc", "foo.sil", "bar.sil", "-module-name", "Test", "-emit-module-path", "/foo/bar/Test.swiftmodule",
          "-experimental-emit-module-separately", "-emit-library", "-target", "x86_64-apple-macosx10.15",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 4)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))
    }

    do {
      // Schedule an emit-module separately job even if there are non-compilable inputs.
      var driver = try TestDriver(
        args: [
          "swiftc", "foo.swift", "bar.dylib", "-emit-library", "foo.dylib", "-emit-module-path", "foo.swiftmodule",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

      let emitJob = try plannedJobs.findJob(.emitModule)
      try expectJobInvocationMatches(emitJob, toPathOption("foo.swift"))
      #expect(!emitJob.commandLine.contains(try toPathOption("bar.dylib")))

      let linkJob = try plannedJobs.findJob(.link)
      try expectJobInvocationMatches(linkJob, toPathOption("bar.dylib"))
    }
  }

  @Test func emitModuleSeparatelyWMO() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)
    let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

    do {
      var driver = try TestDriver(
        args: [
          "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
          rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", root.pathString,
          "-emit-library", "-target", "x86_64-apple-macosx10.15", "-wmo", "-emit-module-separately-wmo",
        ],
        env: envVars
      )

      let abiFileCount = (driver.isFeatureSupported(.emit_abi_descriptor) && driver.targetTriple.isDarwin) ? 1 : 0
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

      // The compile job only produces the object file.
      let compileJob = try plannedJobs.findJob(.compile)
      #expect(compileJob.tool.name.contains("swift"))
      expectJobInvocationMatches(compileJob, .flag("-parse-as-library"))
      expectEqual(compileJob.outputs.count, 1)
      expectEqual(1, compileJob.outputs.filter({ $0.type == .object }).count)

      // The emit module job produces the module files.
      let emitModuleJob = try plannedJobs.findJob(.emitModule)
      #expect(emitModuleJob.tool.name.contains("swift"))
      expectEqual(emitModuleJob.outputs.count, 3 + abiFileCount)
      try expectEqual(
        1,
        try emitModuleJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))
        }).count
      )
      try expectEqual(
        1,
        try emitModuleJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftdoc", at: root)))
        }).count
      )
      try expectEqual(
        1,
        try emitModuleJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))
        }).count
      )
      if abiFileCount == 1 {
        try expectEqual(
          abiFileCount,
          try emitModuleJob.outputs.filter({
            $0.file == .absolute(try .init(validating: rebase("Test.abi.json", at: root)))
          }).count
        )
      }

      // We don't know the output file of the symbol graph, just make sure the flag is passed along.
      expectJobInvocationMatches(emitModuleJob, .flag("-emit-symbol-graph-dir"))
    }

    do {
      // Ignore the `-emit-module-separately-wmo` flag when building only the module files to avoid duplicating outputs.
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-wmo", "-emit-module-separately-wmo",
      ])
      let abiFileCount = (driver.isFeatureSupported(.emit_abi_descriptor) && driver.targetTriple.isDarwin) ? 1 : 0
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile]))

      // The compile job produces the module files.
      let emitModuleJob = plannedJobs[0]
      #expect(emitModuleJob.tool.name.contains("swift"))
      expectEqual(emitModuleJob.outputs.count, 3 + abiFileCount)
      try expectEqual(
        1,
        try emitModuleJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))
        }).count
      )
      try expectEqual(
        1,
        try emitModuleJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftdoc", at: root)))
        }).count
      )
      try expectEqual(
        1,
        try emitModuleJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))
        }).count
      )
      if abiFileCount == 1 {
        try expectEqual(
          abiFileCount,
          try emitModuleJob.outputs.filter({
            $0.file == .absolute(try .init(validating: rebase("Test.abi.json", at: root)))
          }).count
        )
      }
    }

    do {
      // Specifying -no-emit-module-separately-wmo doesn't schedule the separate emit-module job.
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-emit-library", "-wmo", "-emit-module-separately-wmo",
        "-no-emit-module-separately-wmo",
      ])
      let abiFileCount = (driver.isFeatureSupported(.emit_abi_descriptor) && driver.targetTriple.isDarwin) ? 1 : 0
      let plannedJobs = try await driver.planBuild()
      #if os(Linux) || os(Android)
      #expect(plannedJobs.count == 3)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .link, .autolinkExtract]))
      #else
      #expect(plannedJobs.count == 2)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .link]))
      #endif

      // The compile job produces both the object file and the module files.
      let compileJob = try plannedJobs.findJob(.compile)
      expectEqual(compileJob.outputs.count, 4 + abiFileCount)
      expectEqual(1, compileJob.outputs.filter({ $0.type == .object }).count)
      try expectEqual(
        1,
        try compileJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))
        }).count
      )
      try expectEqual(
        1,
        try compileJob.outputs.filter({ $0.file == .absolute(try .init(validating: rebase("Test.swiftdoc", at: root))) }
        ).count
      )
      try expectEqual(
        1,
        try compileJob.outputs.filter({
          $0.file == .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))
        }).count
      )
      if abiFileCount == 1 {
        try expectEqual(
          abiFileCount,
          try compileJob.outputs.filter({
            $0.file == .absolute(try .init(validating: rebase("Test.abi.json", at: root)))
          }).count
        )
      }
    }

    do {
      // non library-evolution builds require a single job, because cross-module-optimization is enabled by default.
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      expectJobInvocationMatches(plannedJobs[0], .flag("-enable-default-cmo"))
    }

    do {
      // -cross-module-optimization should supersede -enable-default-cmo
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O",
        "-cross-module-optimization",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      #expect(!plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      expectJobInvocationMatches(plannedJobs[0], .flag("-cross-module-optimization"))
    }

    do {
      // -enable-cmo-everything should supersede -enable-default-cmo
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O",
        "-enable-cmo-everything",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      #expect(!plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      expectJobInvocationMatches(plannedJobs[0], .flag("-enable-cmo-everything"))
    }

    do {
      // library-evolution builds can emit the module in a separate job.
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O",
        "-enable-library-evolution",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      #expect(!plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      #expect(!plannedJobs[1].commandLine.contains(.flag("-enable-default-cmo")))
    }

    do {
      // When disabling cross-module-optimization, the module can be emitted in a separate job.
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O", "-disable-cmo",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      #expect(!plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      #expect(!plannedJobs[1].commandLine.contains(.flag("-enable-default-cmo")))
    }

    do {
      // non optimized builds can emit the module in a separate job.
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path",
        rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      #expect(!plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      #expect(!plannedJobs[1].commandLine.contains(.flag("-enable-default-cmo")))
    }

    do {
      // Don't use emit-module-separately as a linker.
      var driver = try TestDriver(
        args: [
          "swiftc", "foo.sil", "bar.sil", "-module-name", "Test", "-emit-module-path", "/foo/bar/Test.swiftmodule",
          "-emit-library", "-target", "x86_64-apple-macosx10.15", "-wmo", "-emit-module-separately-wmo",
        ],
        env: envVars
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))
    }
  }

  @Test func moduleWrapJob() async throws {
    // FIXME: These tests will fail when run on macOS, because
    // swift-autolink-extract is not present
    #if os(Linux) || os(Android)
    do {
      var driver = try TestDriver(args: ["swiftc", "-target", "x86_64-unknown-linux-gnu", "-g", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 5)
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .autolinkExtract, .moduleWrap, .link]))
      let wrapJob = try plannedJobs.findJob(.moduleWrap)
      expectEqual(wrapJob.inputs.count, 1)
      expectJobInvocationMatches(wrapJob, .flag("-target"), .flag("x86_64-unknown-linux-gnu"))
      let mergeJob = try plannedJobs.findJob(.emitModule)
      #expect(mergeJob.outputs.contains(wrapJob.inputs.first!))
      #expect(plannedJobs[4].inputs.contains(wrapJob.outputs.first!))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-target", "x86_64-unknown-linux-gnu", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      // No merge module/module wrap jobs.
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .autolinkExtract, .link]))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-target", "x86_64-unknown-linux-gnu", "-gdwarf-types", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 4)
      // Merge module, but no module wrapping.
      expectEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .autolinkExtract, .link]))
    }
    #endif
    // dsymutil won't be found on other platforms
    #if os(macOS)
    do {
      var driver = try TestDriver(args: ["swiftc", "-target", "x86_64-apple-macosx10.15", "-g", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 4)
      // No module wrapping with Mach-O.
      expectEqual(plannedJobs.map { $0.kind }, [.emitModule, .compile, .link, .generateDSYM])
    }
    #endif
  }

  @Test func multithreading() async throws {
    #expect(try TestDriver(args: ["swiftc"]).numParallelJobs == nil)

    try expectEqual(try TestDriver(args: ["swiftc", "-j", "4"]).numParallelJobs, 4)

    var env = ProcessEnv.block
    env["SWIFTC_MAXIMUM_DETERMINISM"] = "1"
    try expectEqual(try TestDriver(args: ["swiftc", "-j", "4"], env: env).numParallelJobs, 1)
  }

  @Test func multithreadingDiagnostics() async throws {
    try await assertDriverDiagnostics(args: "swiftc", "-j", "0") {
      $1.expect(.error("invalid value '0' in '-j'"))
    }

    var env = ProcessEnv.block
    env["SWIFTC_MAXIMUM_DETERMINISM"] = "1"
    try await assertDriverDiagnostics(args: "swiftc", "-j", "8", env: env) {
      $1.expect(.remark("SWIFTC_MAXIMUM_DETERMINISM overriding -j"))
    }
  }

  @Test func multiThreadingOutputs() async throws {
    try await assertDriverDiagnostics(
      args: "swiftc",
      "-c",
      "foo.swift",
      "bar.swift",
      "-o",
      "bar.ll",
      "-o",
      "foo.ll",
      "-num-threads",
      "2",
      "-whole-module-optimization"
    ) {
      $1.expect(.error("cannot specify -o when generating multiple output files"))
    }

    try await assertDriverDiagnostics(
      args: "swiftc",
      "-c",
      "foo.swift",
      "bar.swift",
      "-o",
      "bar.ll",
      "-o",
      "foo.ll",
      "-num-threads",
      "0"
    ) {
      $1.expect(.error("cannot specify -o when generating multiple output files"))
    }
  }

  @Test func pchGeneration() async throws {
    try await checkPCHGeneration(internalBridgingHeader: false)

    let driver = try TestDriver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
    if driver.isFrontendArgSupported(.internalImportBridgingHeader) {
      try await checkPCHGeneration(internalBridgingHeader: true)
    }
  }

  func checkPCHGeneration(internalBridgingHeader: Bool) async throws {
    let importHeaderFlag =
      internalBridgingHeader
      ? "-internal-import-bridging-header"
      : "-import-objc-header"

    do {
      var driver = try TestDriver(args: ["swiftc", "-typecheck", importHeaderFlag, "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)

      #expect(plannedJobs[0].kind == .generatePCH)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      expectEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      #expect(plannedJobs[0].outputs.count == 1)
      #expect(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.pch"))
      expectEqual(plannedJobs[0].outputs[0].type, .pch)
      #expect(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.pch"))

      #expect(plannedJobs[1].kind == .compile)
      expectEqual(plannedJobs[1].inputs.count, 2)
      try expectEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      #expect(plannedJobs[1].commandLine.contains(.flag(importHeaderFlag)))
      #expect(commandContainsTemporaryPath(plannedJobs[1].commandLine, "TestInputHeader.pch"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", "-disable-bridging-pch", importHeaderFlag, "TestInputHeader.h", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)

      #expect(plannedJobs[0].kind == .compile)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("foo.swift"))
      #expect(plannedJobs[0].commandLine.contains(.flag(importHeaderFlag)))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", "-index-store-path", "idx", importHeaderFlag, "TestInputHeader.h", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)

      #expect(plannedJobs[0].kind == .generatePCH)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      expectEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      #expect(plannedJobs[0].outputs.count == 1)
      #expect(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.pch"))
      expectEqual(plannedJobs[0].outputs[0].type, .pch)
      #expect(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-index-store-path")))
      #expect(plannedJobs[0].commandLine.contains(.path(try toPath("idx"))))
      #expect(plannedJobs[0].commandLine.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.pch"))

      #expect(plannedJobs[1].kind == .compile)
      expectEqual(plannedJobs[1].inputs.count, 2)
      try expectEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", importHeaderFlag, "TestInputHeader.h", "-pch-output-dir", "/pch", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)

      #expect(plannedJobs[0].kind == .generatePCH)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      expectEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      #expect(plannedJobs[0].outputs.count == 1)
      try expectEqual(
        plannedJobs[0].outputs[0].file.nativePathString(escaped: false),
        try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false)
      )
      expectEqual(plannedJobs[0].outputs[0].type, .pch)
      #expect(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      #expect(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      #expect(plannedJobs[1].kind == .compile)
      expectEqual(plannedJobs[1].inputs.count, 2)
      try expectEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      #expect(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", "-disable-bridging-pch", importHeaderFlag, "TestInputHeader.h", "-pch-output-dir",
        "/pch", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)

      #expect(plannedJobs[0].kind == .compile)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("foo.swift"))
      #expect(plannedJobs[0].commandLine.contains(.flag(importHeaderFlag)))
      #expect(!plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", "-disable-bridging-pch", importHeaderFlag, "TestInputHeader.h", "-pch-output-dir",
        "/pch", "-whole-module-optimization", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)

      #expect(plannedJobs[0].kind == .compile)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("foo.swift"))
      #expect(plannedJobs[0].commandLine.contains(.flag(importHeaderFlag)))
      #expect(!plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", importHeaderFlag, "TestInputHeader.h", "-pch-output-dir", "/pch",
        "-serialize-diagnostics", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)

      #expect(plannedJobs[0].kind == .generatePCH)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      expectEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      #expect(plannedJobs[0].outputs.count == 2)
      #expect(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.dia"))
      expectEqual(plannedJobs[0].outputs[0].type, .diagnostics)
      try expectEqual(
        plannedJobs[0].outputs[1].file.nativePathString(escaped: false),
        try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false)
      )
      expectEqual(plannedJobs[0].outputs[1].type, .pch)
      #expect(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
      #expect(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.dia"))
      #expect(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      #expect(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      #expect(plannedJobs[1].kind == .compile)
      expectEqual(plannedJobs[1].inputs.count, 2)
      try expectEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      #expect(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", importHeaderFlag, "TestInputHeader.h", "-pch-output-dir", "/pch",
        "-serialize-diagnostics", "foo.swift", "-emit-module", "-emit-module-path", "/module-path-dir",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)

      #expect(plannedJobs[0].kind == .generatePCH)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      expectEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      #expect(plannedJobs[0].outputs.count == 2)
      #expect(
        plannedJobs[0].outputs[0].file.name.range(
          of: #"[\\/]pch[\\/]TestInputHeader-.*.dia"#,
          options: .regularExpression
        ) != nil
      )
      expectEqual(plannedJobs[0].outputs[0].type, .diagnostics)
      try expectEqual(
        plannedJobs[0].outputs[1].file.nativePathString(escaped: false),
        try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false)
      )
      expectEqual(plannedJobs[0].outputs[1].type, .pch)
      #expect(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
      #expect(
        plannedJobs[0].commandLine.contains {
          guard case .path(let path) = $0 else { return false }
          return path.name.range(of: #"[\\/]pch[\\/]TestInputHeader-.*.dia"#, options: .regularExpression) != nil
        }
      )
      #expect(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      #expect(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      #expect(plannedJobs[1].kind == .emitModule)
      expectEqual(plannedJobs[1].inputs.count, 2)
      try expectEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      #expect(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))

      // FIXME: validate that merge module is correct job and that it has correct inputs and flags
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", importHeaderFlag, "TestInputHeader.h", "-pch-output-dir", "/pch",
        "-whole-module-optimization", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)

      #expect(plannedJobs[0].kind == .generatePCH)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      expectEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      #expect(plannedJobs[0].outputs.count == 1)
      try expectEqual(
        plannedJobs[0].outputs[0].file.nativePathString(escaped: false),
        try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false)
      )
      expectEqual(plannedJobs[0].outputs[0].type, .pch)
      #expect(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      #expect(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      #expect(plannedJobs[1].kind == .compile)
      expectEqual(plannedJobs[1].inputs.count, 2)
      try expectEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      #expect(!plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", "-O", importHeaderFlag, "TestInputHeader.h", "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)

      #expect(plannedJobs[0].kind == .generatePCH)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      expectEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      #expect(plannedJobs[0].outputs.count == 1)
      #expect(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.pch"))
      expectEqual(plannedJobs[0].outputs[0].type, .pch)
      #expect(plannedJobs[0].commandLine.contains(.flag("-O")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      #expect(plannedJobs[0].commandLine.contains(.flag("-o")))
      #expect(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.pch"))

      #expect(plannedJobs[1].kind == .compile)
      expectEqual(plannedJobs[1].inputs.count, 2)
      try expectEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
    }

    // Immediate mode doesn't generate a pch
    do {
      var driver = try TestDriver(args: ["swift", importHeaderFlag, "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .interpret)
      #expect(plannedJobs[0].commandLine.contains(.flag(importHeaderFlag)))
      #expect(plannedJobs[0].commandLine.contains(try toPathOption("TestInputHeader.h")))
    }
  }

  @Test func pcmGeneration() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-pcm", "module.modulemap", "-module-name", "Test"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)

      #expect(plannedJobs[0].kind == .generatePCM)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("module.modulemap"))
      #expect(plannedJobs[0].outputs.count == 1)
      #expect(plannedJobs[0].outputs[0].file == .relative(try RelativePath(validating: "Test.pcm")))
    }
  }

  @Test func pcmDump() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-dump-pcm", "module.pcm"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)

      #expect(plannedJobs[0].kind == .dumpPCM)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("module.pcm"))
      #expect(plannedJobs[0].outputs.count == 0)
    }
  }

  @Test func indexFilePathHandling() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-index-file", "-index-file-path",
        "bar.swift", "foo.swift", "bar.swift", "baz.swift",
        "-module-name", "Test",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      try expectJobInvocationMatches(
        plannedJobs[0],
        toPathOption("foo.swift"),
        .flag("-primary-file"),
        toPathOption("bar.swift"),
        toPathOption("baz.swift")
      )
    }
  }

  @Test func indexMultipleFilesInSingleCommandLineInvocation() async throws {
    try await withTemporaryDirectory { dir in
      let outputFileMap = dir.appending(component: "output-filelist")
      let outputMapContents = ByteString(
        """
        {
          "first.swift": {
            "index-unit-output-path": "first.o"
          },
          "second.swift": {
            "index-unit-output-path": "second.o"
          }
        }
        """.utf8
      )
      try localFileSystem.writeFileContents(outputFileMap, bytes: outputMapContents)
      try await assertNoDriverDiagnostics(
        args:
          "swiftc",
        "-index-file",
        "first.swift",
        "second.swift",
        "third.swift",
        "-index-file-path",
        "first.swift",
        "-index-file-path",
        "second.swift",
        "-index-store-path",
        "/tmp/idx",
        "-output-file-map",
        outputFileMap.pathString
      ) { driver in
        let jobs = try await driver.planBuild()
        #expect(jobs.count == 1)
        let commandLine = jobs[0].commandLine
        expectJobInvocationMatches(
          jobs[0],
          .flag("-index-unit-output-path"),
          .path(.relative(try RelativePath(validating: "first.o")))
        )
        expectJobInvocationMatches(
          jobs[0],
          .flag("-index-unit-output-path"),
          .path(.relative(try RelativePath(validating: "second.o")))
        )
        expectEqual(commandLine.filter { $0 == .flag("-index-unit-output-path") }.count, 2)
        expectJobInvocationMatches(
          jobs[0],
          .flag("-primary-file"),
          .path(.relative(try RelativePath(validating: "first.swift")))
        )
        expectJobInvocationMatches(
          jobs[0],
          .flag("-primary-file"),
          .path(.relative(try RelativePath(validating: "second.swift")))
        )
        expectEqual(commandLine.filter { $0 == .flag("-primary-file") }.count, 2)
      }
    }
  }

  @Test func indexFileEntryInSupplementaryFileOutputMap() async throws {
    let workingDirectory = try AbsolutePath(validating: "/tmp")
    var driver1 = try TestDriver(args: [
      "swiftc", "foo1.swift", "foo2.swift", "foo3.swift", "foo4.swift", "foo5.swift",
      "-index-file", "-index-file-path", "foo5.swift", "-o", "/tmp/t.o",
      "-index-store-path", "/tmp/idx",
      "-working-directory", workingDirectory.nativePathString(escaped: false),
    ])
    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 1)
    let map = try plannedJobs[0].commandLine.supplementaryOutputFilemap
    // This is to match the legacy driver behavior
    // Make sure the supplementary output map has an entry for the Swift file
    // under indexing and its indexData entry is the primary output file
    let entry = try #require(
      map.entries[VirtualPath.absolute(workingDirectory.appending(component: "foo5.swift")).intern()]
    )
    expectEqual(VirtualPath.lookup(entry[.indexData]!), .absolute(workingDirectory.appending(component: "t.o")))
  }

  @Test func pchAsCompileInput() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    var driver = try TestDriver(
      args: [
        "swiftc", "-target", "x86_64-apple-macosx10.14", "-enable-bridging-pch", "-import-objc-header",
        "TestInputHeader.h", "foo.swift",
      ],
      env: envVars
    )
    let plannedJobs = try await driver.planBuild()
    #expect(plannedJobs.count == 3)
    #expect(plannedJobs[0].kind == .generatePCH)
    #expect(plannedJobs[1].kind == .compile)
    #expect(plannedJobs[1].inputs[0].file.extension == "swift")
    #expect(plannedJobs[1].inputs[1].file.extension == "pch")
  }

  @Test func internalPCHasCompileInput() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    var driver = try TestDriver(
      args: [
        "swiftc", "-target", "x86_64-apple-macosx10.14", "-enable-bridging-pch", "-internal-import-bridging-header",
        "TestInputHeader.h", "foo.swift",
      ],
      env: envVars
    )
    let plannedJobs = try await driver.planBuild()
    #expect(plannedJobs.count == 3)
    #expect(plannedJobs[0].kind == .generatePCH)
    #expect(plannedJobs[1].kind == .compile)
    #expect(plannedJobs[1].inputs[0].file.extension == "swift")
    #expect(plannedJobs[1].inputs[1].file.extension == "pch")
  }

  @Test func cxxInteropOptions() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-cxx-interoperability-mode=swift-5.9", "foo.swift"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      let compileJob = plannedJobs[0]
      let linkJob = plannedJobs[1]
      expectJobInvocationMatches(compileJob, .flag("-cxx-interoperability-mode=swift-5.9"))
      if driver.targetTriple.isDarwin {
        expectJobInvocationMatches(linkJob, .flag("-lc++"))
      }
    }
  }

  @Test func embeddedSwiftOptions() async throws {
    var env = ProcessEnv.block
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-target", "arm64-apple-macosx10.13", "test.swift", "-enable-experimental-feature", "Embedded",
        "-parse-as-library", "-wmo", "-o", "a.out", "-module-name", "main",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let compileJob = plannedJobs[0]
      let linkJob = plannedJobs[1]
      expectJobInvocationMatches(compileJob, .flag("-disable-objc-interop"))
      #expect(!linkJob.commandLine.contains(.flag("-force_load")))
    }

    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-L",
          "/TestApp/.build/aarch64-none-none-elf/release",
          "-o",
          "/TestApp/.build/aarch64-none-none-elf/release/TestApp",
          "-module-name",
          "TestApp",
          "-emit-executable",
          "-Xlinker",
          "--gc-sections",
          "@/TestApp/.build/aarch64-none-none-elf/release/TestApp.product/Objects.LinkFileList",
          "-target",
          "aarch64-none-none-elf",
          "-enable-experimental-feature", "Embedded",
          "-Xfrontend",
          "-function-sections",
          "-Xfrontend",
          "-disable-stack-protector",
          "-use-ld=lld",
          "-tools-directory",
          "/Tools/swift.xctoolchain/usr/bin",
        ],
        env: env
      )

      let jobs = try await driver.planBuild()
      let linkJob = try jobs.findJob(.link)
      let invalidPath = try VirtualPath(path: "/Tools/swift.xctoolchain/usr/lib/swift")
      let invalid = linkJob.commandLine.contains(.responseFilePath(invalidPath))
      #expect(!invalid)  // ensure the driver does not emit invalid responseFilePaths to the clang invocation
      #expect(!linkJob.commandLine.joinedUnresolvedArguments.contains("swiftrt.o"))
    }

    // Printing target info needs to pass through the experimental flag.
    do {
      var driver = try TestDriver(
        args: [
          "swiftc",
          "-target",
          "aarch64-none-none-elf",
          "-enable-experimental-feature", "Embedded",
          "-print-target-info",
        ],
        env: env
      )

      let jobs = try await driver.planBuild()
      let targetInfoJob = try jobs.findJob(.printTargetInfo)
      #expect(targetInfoJob.commandLine.contains(.flag("Embedded")))
    }

    // Embedded Wasm compile job
    do {
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "wasm32-none-none-wasm", "test.swift", "-enable-experimental-feature", "Embedded",
          "-wmo", "-o", "a.wasm",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let compileJob = plannedJobs[0]
      let linkJob = plannedJobs[1]
      expectJobInvocationMatches(compileJob, .flag("-disable-objc-interop"))
      #expect(!linkJob.commandLine.contains(.flag("-force_load")))
      #expect(!linkJob.commandLine.contains(.flag("-rpath")))
      #expect(!linkJob.commandLine.contains(.flag("-lswiftCore")))
    }

    // Embedded Wasm link job
    do {
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "wasm32-none-none-wasm", "test.o", "-enable-experimental-feature", "Embedded", "-wmo",
          "-o", "a.wasm",
        ],
        env: env
      )
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let linkJob = plannedJobs[0]
      #expect(!linkJob.commandLine.contains(.flag("-force_load")))
      #expect(!linkJob.commandLine.contains(.flag("-rpath")))
      #expect(!linkJob.commandLine.contains(.flag("-lswiftCore")))
      #expect(!linkJob.commandLine.joinedUnresolvedArguments.contains("swiftrt.o"))
    }

    // Embedded WASI link job
    do {
      for tripleEnv in ["wasi", "wasi-wasm", "wasip1", "wasip1-wasm", "wasip1-threads"] {
        var driver = try TestDriver(
          args: [
            "swiftc", "-target", "wasm32-unknown-\(tripleEnv)",
            "-resource-dir", "/usr/lib/swift",
            "-enable-experimental-feature", "Embedded", "-wmo",
            "test.o", "-o", "a.wasm",
          ],
          env: env
        )
        let plannedJobs = try await driver.planBuild()
        #expect(plannedJobs.count == 1)
        let linkJob = plannedJobs[0]
        #expect(!linkJob.commandLine.contains(.flag("-force_load")))
        #expect(!linkJob.commandLine.contains(.flag("-rpath")))
        #expect(!linkJob.commandLine.contains(.flag("-lswiftCore")))
        #expect(!linkJob.commandLine.joinedUnresolvedArguments.contains("swiftrt.o"))
        #expect(
          linkJob.commandLine.contains(
            .joinedOptionAndPath("-L", try .init(path: "/usr/lib/swift/embedded/wasm32-unknown-\(tripleEnv)"))
          )
        )
      }
    }

    // 32-bit iOS jobs under Embedded should be allowed regardless of OS version
    do {
      let _ = try TestDriver(args: [
        "swiftc", "-c", "-target", "armv7-apple-ios8", "-enable-experimental-feature", "Embedded", "foo.swift",
      ])
      let _ = try TestDriver(args: [
        "swiftc", "-c", "-target", "armv7-apple-ios12.1", "-enable-experimental-feature", "Embedded", "foo.swift",
      ])
      let _ = try TestDriver(args: [
        "swiftc", "-c", "-target", "armv7-apple-ios16", "-enable-experimental-feature", "Embedded", "foo.swift",
      ])
    }

    do {
      let diags = DiagnosticsEngine()
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "arm64-apple-macosx10.13", "test.swift", "-enable-experimental-feature", "Embedded",
          "-parse-as-library", "-wmo", "-o", "a.out", "-module-name", "main", "-enable-library-evolution",
        ],
        diagnosticsEngine: diags
      )
      _ = try await driver.planBuild()
      expectEqual(diags.diagnostics.first!.message.text, Diagnostic.Message.error_no_library_evolution_embedded.text)
    } catch _ {}
    do {
      let diags = DiagnosticsEngine()
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "arm64-apple-macosx10.13", "test.swift", "-enable-experimental-feature", "Embedded",
          "-parse-as-library", "-o", "a.out", "-module-name", "main",
        ],
        diagnosticsEngine: diags
      )
      _ = try await driver.planBuild()
      expectEqual(diags.diagnostics.first!.message.text, Diagnostic.Message.error_need_wmo_embedded.text)
    } catch _ {}
    do {
      var environment = ProcessEnv.block
      environment["SDKROOT"] = nil

      // Indexing embedded Swift code should not require WMO
      let diags = DiagnosticsEngine()
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "arm64-apple-macosx10.13", "test.swift", "-index-file", "-index-file-path", "test.swift",
          "-enable-experimental-feature", "Embedded", "-parse-as-library", "-o", "a.out", "-module-name", "main",
        ],
        env: env,
        diagnosticsEngine: diags
      )
      _ = try await driver.planBuild()
      expectEqual(diags.diagnostics.count, 0)
    }
    do {
      let diags = DiagnosticsEngine()
      var driver = try TestDriver(
        args: [
          "swiftc", "-target", "arm64-apple-macosx10.13", "test.swift", "-enable-experimental-feature", "Embedded",
          "-parse-as-library", "-wmo", "-o", "a.out", "-module-name", "main", "-enable-objc-interop",
        ],
        diagnosticsEngine: diags
      )
      _ = try await driver.planBuild()
      expectEqual(diags.diagnostics.first!.message.text, Diagnostic.Message.error_no_objc_interop_embedded.text)
    } catch _ {}
  }

  @Test func dashDashPassingDownInput() async throws {
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-module-name=ThisModule", "-wmo", "-num-threads", "4", "-emit-module", "-o", "test.swiftmodule",
        "--", "main.swift", "multi-threaded.swift",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(!driver.diagnosticEngine.hasErrors)
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      expectEqual(plannedJobs[0].inputs.count, 2)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("main.swift"))
      try expectEqual(plannedJobs[0].inputs[1].file, try toPath("multi-threaded.swift"))
      #expect(plannedJobs[0].outputs.count == (driver.targetTriple.isDarwin ? 4 : 3))
      #expect(try plannedJobs[0].outputs[0].file == toPath("test.swiftmodule"))
    }
  }

  @Test func dashDashImmediateInput() async throws {
    do {
      var driver = try TestDriver(args: ["swift", "--", "main.swift"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(!driver.diagnosticEngine.hasErrors)
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .interpret)
      expectEqual(plannedJobs[0].inputs.count, 1)
      try expectEqual(plannedJobs[0].inputs[0].file, try toPath("main.swift"))
    }
  }

  @Test func emitModuleEmittingDependencies() async throws {
    var driver1 = try TestDriver(args: [
      "swiftc", "foo.swift", "bar.swift", "-module-name", "Foo", "-emit-dependencies", "-emit-module",
      "-serialize-diagnostics", "-driver-filelist-threshold=9999", "-experimental-emit-module-separately",
    ])
    let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 3)
    #expect(plannedJobs[0].kind == .emitModule)
    // TODO: This check is disabled as per rdar://85253406
    // expectJobInvocationMatches(plannedJobs[0], .flag("-emit-dependencies-path"))
    expectJobInvocationMatches(plannedJobs[0], .flag("-serialize-diagnostics-path"))
  }

  @Test func emitConstValues() async throws {
    do {  // Just single files
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "baz.swift",
        "-const-gather-protocols-list", "protocols.json",
        "-module-name", "Foo", "-emit-const-values",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 4)

      #expect(plannedJobs[0].kind == .compile)
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-const-values-path"))
      expectJobInvocationMatches(plannedJobs[0], .flag("-const-gather-protocols-file"))
      #expect(plannedJobs[0].outputs.contains(where: { $0.type == .swiftConstValues }))

      #expect(plannedJobs[1].kind == .compile)
      expectJobInvocationMatches(plannedJobs[1], .flag("-emit-const-values-path"))
      expectJobInvocationMatches(plannedJobs[0], .flag("-const-gather-protocols-file"))
      #expect(plannedJobs[1].outputs.contains(where: { $0.type == .swiftConstValues }))

      #expect(plannedJobs[2].kind == .compile)
      expectJobInvocationMatches(plannedJobs[2], .flag("-emit-const-values-path"))
      expectJobInvocationMatches(plannedJobs[0], .flag("-const-gather-protocols-file"))
      #expect(plannedJobs[2].outputs.contains(where: { $0.type == .swiftConstValues }))

      #expect(plannedJobs[3].kind == .link)
    }

    do {  // Just single files with emit-module
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "baz.swift", "-emit-module",
        "-module-name", "Foo", "-emit-const-values",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 4)

      #expect(plannedJobs[0].kind == .emitModule)
      // Ensure the emit-module job does *not* contain this flag
      #expect(!plannedJobs[0].commandLine.contains("-emit-const-values-path"))

      #expect(plannedJobs[1].kind == .compile)
      expectJobInvocationMatches(plannedJobs[1], .flag("-emit-const-values-path"))
      #expect(plannedJobs[1].outputs.contains(where: { $0.type == .swiftConstValues }))

      #expect(plannedJobs[2].kind == .compile)
      expectJobInvocationMatches(plannedJobs[2], .flag("-emit-const-values-path"))
      #expect(plannedJobs[2].outputs.contains(where: { $0.type == .swiftConstValues }))

      #expect(plannedJobs[3].kind == .compile)
      expectJobInvocationMatches(plannedJobs[3], .flag("-emit-const-values-path"))
      #expect(plannedJobs[3].outputs.contains(where: { $0.type == .swiftConstValues }))
    }

    do {  // Batch
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "baz.swift",
        "-enable-batch-mode", "-driver-batch-size-limit", "2",
        "-module-name", "Foo", "-emit-const-values",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)

      #expect(plannedJobs[0].kind == .compile)
      #expect(plannedJobs[0].primaryInputs.map { $0.file.description }.elementsEqual(["foo.swift", "bar.swift"]))
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-const-values-path"))
      expectEqual(plannedJobs[0].outputs.filter({ $0.type == .swiftConstValues }).count, 2)

      #expect(plannedJobs[1].kind == .compile)
      #expect(plannedJobs[1].primaryInputs.map { $0.file.description }.elementsEqual(["baz.swift"]))
      expectJobInvocationMatches(plannedJobs[1], .flag("-emit-const-values-path"))
      expectEqual(plannedJobs[1].outputs.filter({ $0.type == .swiftConstValues }).count, 1)

      #expect(plannedJobs[2].kind == .link)
    }

    try await withTemporaryDirectory { dir in  // Batch with output-file-map
      let fileMapFile = dir.appending(component: "file-map-file")
      let outputMapContents: ByteString = """
        {
          "foo.swift": {
            "object": "/tmp/foo.build/foo.swift.o",
            "const-values": "/tmp/foo.build/foo.swiftconstvalues"
          },
          "bar.swift": {
            "object": "/tmp/foo.build/bar.swift.o",
            "const-values": "/tmp/foo.build/bar.swiftconstvalues"
          },
          "baz.swift": {
            "object": "/tmp/foo.build/baz.swift.o",
            "const-values": "/tmp/foo.build/baz.swiftconstvalues"
          }
        }
        """
      try localFileSystem.writeFileContents(fileMapFile, bytes: outputMapContents)
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "baz.swift",
        "-enable-batch-mode", "-driver-batch-size-limit", "2",
        "-module-name", "Foo", "-emit-const-values",
        "-output-file-map", fileMapFile.description,
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 3)

      #expect(plannedJobs[0].kind == .compile)
      #expect(plannedJobs[0].primaryInputs.map { $0.file.description }.elementsEqual(["foo.swift", "bar.swift"]))
      try expectJobInvocationMatches(
        plannedJobs[0],
        .flag("-emit-const-values-path"),
        .path(.absolute(.init(validating: "/tmp/foo.build/foo.swiftconstvalues")))
      )
      try expectJobInvocationMatches(
        plannedJobs[0],
        .flag("-emit-const-values-path"),
        .path(.absolute(.init(validating: "/tmp/foo.build/bar.swiftconstvalues")))
      )
      expectEqual(plannedJobs[0].outputs.filter({ $0.type == .swiftConstValues }).count, 2)

      #expect(plannedJobs[1].kind == .compile)
      #expect(plannedJobs[1].primaryInputs.map { $0.file.description }.elementsEqual(["baz.swift"]))
      try expectJobInvocationMatches(
        plannedJobs[1],
        .flag("-emit-const-values-path"),
        .path(.absolute(.init(validating: "/tmp/foo.build/baz.swiftconstvalues")))
      )
      expectEqual(plannedJobs[1].outputs.filter({ $0.type == .swiftConstValues }).count, 1)

      #expect(plannedJobs[2].kind == .link)
    }

    do {  // WMO
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "baz.swift",
        "-whole-module-optimization",
        "-module-name", "Foo", "-emit-const-values",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)
      expectEqual(plannedJobs[0].outputs.filter({ $0.type == .swiftConstValues }).count, 1)
      #expect(plannedJobs[1].kind == .link)
    }

    try await withTemporaryDirectory { dir in  // WMO with output-file-map
      let fileMapFile = dir.appending(component: "file-map-file")
      let outputMapContents: ByteString = """
        {
          "": {
            "const-values": "/tmp/foo.build/foo.main.swiftconstvalues"
          },
          "foo.swift": {
            "object": "/tmp/foo.build/foo.swift.o",
            "const-values": "/tmp/foo.build/foo.swiftconstvalues"
          },
          "bar.swift": {
            "object": "/tmp/foo.build/bar.swift.o",
            "const-values": "/tmp/foo.build/bar.swiftconstvalues"
          },
          "baz.swift": {
            "object": "/tmp/foo.build/baz.swift.o",
            "const-values": "/tmp/foo.build/baz.swiftconstvalues"
          }
        }
        """
      try localFileSystem.writeFileContents(fileMapFile, bytes: outputMapContents)
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "baz.swift",
        "-whole-module-optimization",
        "-module-name", "Foo", "-emit-const-values",
        "-output-file-map", fileMapFile.description,
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)
      try expectEqual(
        plannedJobs[0].outputs.first(where: { $0.type == .swiftConstValues })?.file,
        .absolute(try .init(validating: "/tmp/foo.build/foo.main.swiftconstvalues"))
      )
      #expect(plannedJobs[1].kind == .link)
    }
  }

  @Test func emitModuleSepratelyEmittingDiagnosticsWithOutputFileMap() async throws {
    try await withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      try localFileSystem.writeFileContents(
        outputFileMap,
        bytes: """
          {
            "": {
              "emit-module-diagnostics": "/build/Foo-test.dia"
            }
          }
          """
      )
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Foo", "-emit-module",
        "-serialize-diagnostics", "-experimental-emit-module-separately",
        "-output-file-map", outputFileMap.description,
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      #expect(plannedJobs.count == 3)
      #expect(plannedJobs[0].kind == .emitModule)
      try expectJobInvocationMatches(
        plannedJobs[0],
        .flag("-serialize-diagnostics-path"),
        .path(.absolute(.init(validating: "/build/Foo-test.dia")))
      )
    }
  }

  @Test func emitPCHWithOutputFileMap() async throws {
    try await withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      try localFileSystem.writeFileContents(
        outputFileMap,
        bytes: """
          {
            "": {
              "pch": "/build/Foo-bridging-header.pch"
            }
          }
          """
      )
      var driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Foo", "-emit-module",
        "-serialize-diagnostics", "-experimental-emit-module-separately",
        "-import-objc-header", "bridging.h", "-enable-bridging-pch",
        "-output-file-map", outputFileMap.description,
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(driver.diagnosticEngine.diagnostics.isEmpty)

      // Test the output path is correct for GeneratePCH job.
      #expect(plannedJobs.count == 4)
      #expect(plannedJobs[0].kind == .generatePCH)
      try expectJobInvocationMatches(
        plannedJobs[0],
        .flag("-o"),
        .path(.absolute(.init(validating: "/build/Foo-bridging-header.pch")))
      )

      // Plan a build with no bridging header and make sure no diagnostics is emitted (pch in output file map is still accepted)
      driver = try TestDriver(args: [
        "swiftc", "foo.swift", "bar.swift", "-module-name", "Foo", "-emit-module",
        "-serialize-diagnostics", "-experimental-emit-module-separately",
        "-output-file-map", outputFileMap.description,
      ])
      let _ = try await driver.planBuild()
      #expect(driver.diagnosticEngine.diagnostics.isEmpty)
    }
  }
}
