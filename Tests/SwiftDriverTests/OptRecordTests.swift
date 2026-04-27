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

@Suite struct OptRecordTests {

  @Test func optimizationRecordFileInSupplementaryOutputFileMap() async throws {
    func checkSupplementaryOutputFileMap(format: String, _ fileType: FileType) async throws {
      var driver1 = try TestDriver(args: [
        "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
        "-save-optimization-record=\(format)", "-driver-filelist-threshold=0",
      ])
      let plannedJobs = try await driver1.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      let outFileMap = try plannedJobs[0].commandLine.supplementaryOutputFilemap
      expectEqual(outFileMap.entries.values.first?.keys.first, fileType)
    }

    try await checkSupplementaryOutputFileMap(format: "yaml", .yamlOptimizationRecord)
    try await checkSupplementaryOutputFileMap(format: "bitstream", .bitstreamOptimizationRecord)
  }

  @Test func optimizationRecordWithOutputFileMap() async throws {
    try await withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      let file1 = path.appending(component: "file1.swift")
      let file2 = path.appending(component: "file2.swift")
      let optRecord1 = path.appending(component: "file1.opt.yaml")
      let optRecord2 = path.appending(component: "file2.opt.yaml")

      let ofm = OutputFileMap(entries: [
        try VirtualPath.intern(path: file1.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file1.o").pathString),
          .yamlOptimizationRecord: try VirtualPath.intern(path: optRecord1.pathString),
        ],
        try VirtualPath.intern(path: file2.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file2.o").pathString),
          .yamlOptimizationRecord: try VirtualPath.intern(path: optRecord2.pathString),
        ],
      ])
      try ofm.store(fileSystem: localFileSystem, file: outputFileMap)

      try localFileSystem.writeFileContents(file1) { $0.send("func foo() {}") }
      try localFileSystem.writeFileContents(file2) { $0.send("func bar() {}") }

      // Test primary file mode with output file map containing optimization record entries
      var driver = try TestDriver(args: [
        "swiftc", "-save-optimization-record",
        "-output-file-map", outputFileMap.pathString,
        "-c", file1.pathString, file2.pathString,
      ])
      let plannedJobs = try await driver.planBuild()
      let compileJobs = plannedJobs.filter { $0.kind == .compile }

      expectEqual(compileJobs.count, 2, "Should have two compile jobs in primary file mode")

      for (index, compileJob) in compileJobs.enumerated() {
        #expect(
          compileJob.commandLine.contains(.flag("-save-optimization-record-path")),
          "Compile job \(index) should have -save-optimization-record-path flag"
        )

        if let primaryFileIndex = compileJob.commandLine.firstIndex(of: .flag("-primary-file")),
          primaryFileIndex + 1 < compileJob.commandLine.count
        {
          let primaryFile = compileJob.commandLine[primaryFileIndex + 1]

          if let optRecordIndex = compileJob.commandLine.firstIndex(of: .flag("-save-optimization-record-path")),
            optRecordIndex + 1 < compileJob.commandLine.count
          {
            let optRecordPath = compileJob.commandLine[optRecordIndex + 1]

            if case .path(let primaryPath) = primaryFile, case .path(let optPath) = optRecordPath {
              if primaryPath == .absolute(file1) {
                expectEqual(
                  optPath,
                  .absolute(optRecord1),
                  "Compile job with file1.swift as primary should use file1.opt.yaml from output file map"
                )
              } else if primaryPath == .absolute(file2) {
                expectEqual(
                  optPath,
                  .absolute(optRecord2),
                  "Compile job with file2.swift as primary should use file2.opt.yaml from output file map"
                )
              }
            }
          }
        }
      }
    }
  }

  @Test func optimizationRecordPartialFileMapCoverage() async throws {
    try await withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      let file1 = path.appending(component: "file1.swift")
      let file2 = path.appending(component: "file2.swift")
      let optRecord1 = path.appending(component: "file1.opt.yaml")

      let ofm = OutputFileMap(entries: [
        try VirtualPath.intern(path: file1.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file1.o").pathString),
          .yamlOptimizationRecord: try VirtualPath.intern(path: optRecord1.pathString),
        ],
        try VirtualPath.intern(path: file2.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file2.o").pathString)
        ],
      ])
      try ofm.store(fileSystem: localFileSystem, file: outputFileMap)

      try localFileSystem.writeFileContents(file1) { $0.send("func foo() {}") }
      try localFileSystem.writeFileContents(file2) { $0.send("func bar() {}") }

      // Test primary file mode with partial file map coverage
      var driver = try TestDriver(args: [
        "swiftc", "-save-optimization-record",
        "-output-file-map", outputFileMap.pathString,
        "-c", file1.pathString, file2.pathString,
      ])
      let plannedJobs = try await driver.planBuild()
      let compileJobs = plannedJobs.filter { $0.kind == .compile }

      expectEqual(compileJobs.count, 2, "Should have two compile jobs in primary file mode")

      // file1 should use the path from the file map, file2 should use a derived path
      for compileJob in compileJobs {
        if let primaryFileIndex = compileJob.commandLine.firstIndex(of: .flag("-primary-file")),
          primaryFileIndex + 1 < compileJob.commandLine.count
        {
          let primaryFile = compileJob.commandLine[primaryFileIndex + 1]

          if case .path(let primaryPath) = primaryFile {
            if primaryPath == .absolute(file1) {
              #expect(
                compileJob.commandLine.contains(.flag("-save-optimization-record-path")),
                "file1 compile job should have -save-optimization-record-path flag"
              )
              if let optRecordIndex = compileJob.commandLine.firstIndex(of: .flag("-save-optimization-record-path")),
                optRecordIndex + 1 < compileJob.commandLine.count,
                case .path(let optPath) = compileJob.commandLine[optRecordIndex + 1]
              {
                expectEqual(
                  optPath,
                  .absolute(optRecord1),
                  "file1 should use the optimization record path from the file map"
                )
              }
            } else if primaryPath == .absolute(file2) {
              #expect(
                compileJob.commandLine.contains(.flag("-save-optimization-record-path")),
                "file2 compile job should have -save-optimization-record-path flag"
              )
              if let optRecordIndex = compileJob.commandLine.firstIndex(of: .flag("-save-optimization-record-path")),
                optRecordIndex + 1 < compileJob.commandLine.count,
                case .path(let optPath) = compileJob.commandLine[optRecordIndex + 1]
              {
                #expect(
                  optPath != .absolute(optRecord1),
                  "file2 should not use file1's optimization record path"
                )
              }
            }
          }
        }
      }
    }
  }

  @Test func optimizationRecordPathUserProvidedPath() async throws {
    // Test single file with explicit path (primary file mode)
    do {
      var driver = try TestDriver(args: [
        "swiftc", "-save-optimization-record", "-save-optimization-record-path", "/tmp/test.opt.yaml",
        "-c", "test.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      let compileJob = try #require(plannedJobs.first { $0.kind == .compile })

      #expect(
        compileJob.commandLine.contains(.path(VirtualPath.absolute(try AbsolutePath(validating: "/tmp/test.opt.yaml"))))
      )
      #expect(compileJob.commandLine.contains(.flag("-save-optimization-record-path")))
    }
  }

  @Test func optimizationRecordMultiThreadedWMOInsufficientPaths() async throws {
    // Test error when multi-threaded WMO has insufficient explicit paths
    var driver = try TestDriver(args: [
      "swiftc", "-wmo", "-num-threads", "2", "-save-optimization-record",
      "-save-optimization-record-path", "/tmp/single.opt.yaml",
      "-c", "file1.swift", "file2.swift",
    ])

    await #expect(throws: (any Error).self) { try await driver.planBuild() }

    #expect(
      driver.diagnosticEngine.diagnostics.contains(where: {
        $0.message.text.contains(
          "multi-threaded whole-module optimization requires one '-save-optimization-record-path' per source file"
        )
      })
    )
  }

  @Test func optimizationRecordMultiThreadedWMOWithExplicitPaths() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-wmo", "-num-threads", "2", "-save-optimization-record",
      "-save-optimization-record-path", "/tmp/file1.opt.yaml",
      "-save-optimization-record-path", "/tmp/file2.opt.yaml",
      "-c", "file1.swift", "file2.swift",
    ])

    let plannedJobs = try await driver.planBuild()
    let compileJob = try #require(plannedJobs.first { $0.kind == .compile })

    #expect(
      compileJob.commandLine.contains(.path(VirtualPath.absolute(try AbsolutePath(validating: "/tmp/file1.opt.yaml")))),
      "Command line should contain file1.opt.yaml path"
    )
    #expect(
      compileJob.commandLine.contains(.path(VirtualPath.absolute(try AbsolutePath(validating: "/tmp/file2.opt.yaml")))),
      "Command line should contain file2.opt.yaml path"
    )
  }

  @Test func optimizationRecordMultiThreadedWMODerivedPaths() async throws {
    // Test optimization record paths for multi-threaded WMO when
    // -save-optimization-record is specified without explicit paths or file map entries
    var driver = try TestDriver(args: [
      "swiftc", "-wmo", "-num-threads", "2", "-save-optimization-record",
      "-c", "file1.swift", "file2.swift",
    ])

    let plannedJobs = try await driver.planBuild()
    let compileJob = try #require(plannedJobs.first { $0.kind == .compile })

    // With multiple optimization records, the driver uses a supplementary output file map
    #expect(
      compileJob.commandLine.contains(.flag("-supplementary-output-file-map")),
      "Should use supplementary output file map for derived per-file optimization record paths"
    )

    let outFileMap = try compileJob.commandLine.supplementaryOutputFilemap

    var hasFile1OptRecord = false
    var hasFile2OptRecord = false

    for (inputHandle, outputs) in outFileMap.entries {
      let inputPath = VirtualPath.lookup(inputHandle).name
      if inputPath.contains("file1.swift") {
        hasFile1OptRecord = outputs.keys.contains { $0.isOptimizationRecord }
      }
      if inputPath.contains("file2.swift") {
        hasFile2OptRecord = outputs.keys.contains { $0.isOptimizationRecord }
      }
    }

    #expect(hasFile1OptRecord, "Should derive optimization record path for file1.swift")
    #expect(hasFile2OptRecord, "Should derive optimization record path for file2.swift")
  }

  @Test func optimizationRecordMultiThreadedWMOWithCompleteFileMap() async throws {
    // Test that multi-threaded WMO with complete file map coverage works
    try await withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      let file1 = path.appending(component: "file1.swift")
      let file2 = path.appending(component: "file2.swift")
      let optRecord1 = path.appending(component: "file1.opt.yaml")
      let optRecord2 = path.appending(component: "file2.opt.yaml")

      let ofm = OutputFileMap(entries: [
        try VirtualPath.intern(path: file1.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file1.o").pathString),
          .yamlOptimizationRecord: try VirtualPath.intern(path: optRecord1.pathString),
        ],
        try VirtualPath.intern(path: file2.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file2.o").pathString),
          .yamlOptimizationRecord: try VirtualPath.intern(path: optRecord2.pathString),
        ],
      ])
      try ofm.store(fileSystem: localFileSystem, file: outputFileMap)

      try localFileSystem.writeFileContents(file1) { $0.send("func foo() {}") }
      try localFileSystem.writeFileContents(file2) { $0.send("func bar() {}") }

      var driver = try TestDriver(args: [
        "swiftc", "-wmo", "-num-threads", "2", "-save-optimization-record",
        "-output-file-map", outputFileMap.pathString,
        "-c", file1.pathString, file2.pathString,
      ])

      let plannedJobs = try await driver.planBuild()
      let compileJob = try #require(plannedJobs.first { $0.kind == .compile })

      #expect(
        compileJob.commandLine.contains(.flag("-supplementary-output-file-map")),
        "Should use supplementary output file map for file map entries"
      )
    }
  }

  @Test func optimizationRecordSingleThreadedWMOModuleLevelEntry() async throws {
    // Test module-level entry for single-threaded WMO
    try await withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      let file1 = path.appending(component: "file1.swift")
      let file2 = path.appending(component: "file2.swift")
      let moduleLevelOptRecord = path.appending(component: "module.opt.yaml")

      // Output file map with module-level entry (empty path key)
      let ofm = OutputFileMap(entries: [
        try VirtualPath.intern(path: ""): [
          .yamlOptimizationRecord: try VirtualPath.intern(path: moduleLevelOptRecord.pathString)
        ],
        try VirtualPath.intern(path: file1.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file1.o").pathString)
        ],
        try VirtualPath.intern(path: file2.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file2.o").pathString)
        ],
      ])
      try ofm.store(fileSystem: localFileSystem, file: outputFileMap)

      try localFileSystem.writeFileContents(file1) { $0.send("func foo() {}") }
      try localFileSystem.writeFileContents(file2) { $0.send("func bar() {}") }

      var driver = try TestDriver(args: [
        "swiftc", "-wmo", "-save-optimization-record",
        "-output-file-map", outputFileMap.pathString,
        "-c", file1.pathString, file2.pathString,
      ])

      let plannedJobs = try await driver.planBuild()
      let compileJob = try #require(plannedJobs.first { $0.kind == .compile })

      #expect(
        compileJob.commandLine.contains(.path(VirtualPath.absolute(moduleLevelOptRecord))),
        "Should use module-level optimization record path for single-threaded WMO"
      )
    }
  }

  @Test func optimizationRecordSingleThreadedWMODerivedPath() async throws {
    // Test that single-threaded WMO with just -save-optimization-record derives a module-level path
    var driver = try TestDriver(args: [
      "swiftc", "-wmo", "-save-optimization-record",
      "-c", "file1.swift", "file2.swift",
    ])

    let plannedJobs = try await driver.planBuild()
    let compileJob = try #require(plannedJobs.first { $0.kind == .compile })

    // Should have -save-optimization-record-path flag with auto-generated path
    #expect(
      compileJob.commandLine.contains(.flag("-save-optimization-record-path")),
      "Should have -save-optimization-record-path flag"
    )

    if let flagIndex = compileJob.commandLine.firstIndex(of: .flag("-save-optimization-record-path")),
      flagIndex + 1 < compileJob.commandLine.count
    {
      switch compileJob.commandLine[flagIndex + 1] {
      case .path:
        break
      default:
        Issue.record("Expected path argument after -save-optimization-record-path flag")
      }
    } else {
      Issue.record("Could not find -save-optimization-record-path flag and path")
    }
  }

  @Test func optimizationRecordWarningWithExplicitPathAndFileMap() async throws {
    // Test that warning is emitted when both explicit -save-optimization-record-path
    // and output file map entries exist for optimization records
    try await withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      let file1 = path.appending(component: "file1.swift")
      let file2 = path.appending(component: "file2.swift")

      let ofm = OutputFileMap(entries: [
        try VirtualPath.intern(path: file1.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file1.o").pathString),
          .yamlOptimizationRecord: try VirtualPath.intern(path: path.appending(component: "file1.opt.yaml").pathString),
        ],
        try VirtualPath.intern(path: file2.pathString): [
          .object: try VirtualPath.intern(path: path.appending(component: "file2.o").pathString),
          .yamlOptimizationRecord: try VirtualPath.intern(path: path.appending(component: "file2.opt.yaml").pathString),
        ],
      ])
      try ofm.store(fileSystem: localFileSystem, file: outputFileMap)

      try localFileSystem.writeFileContents(file1) { $0.send("func foo() {}") }
      try localFileSystem.writeFileContents(file2) { $0.send("func bar() {}") }

      var driver = try TestDriver(args: [
        "swiftc", "-save-optimization-record-path", "/tmp/explicit.opt.yaml",
        "-output-file-map", outputFileMap.pathString,
        "-c", file1.pathString, file2.pathString,
      ])

      _ = try await driver.planBuild()

      #expect(
        driver.diagnosticEngine.diagnostics.contains(where: {
          $0.message.text.contains(
            "ignoring '-save-optimization-record-path' because output file map contains optimization record entries"
          )
        }),
        "Should warn when both explicit path and file map entries exist"
      )
    }
  }
}
