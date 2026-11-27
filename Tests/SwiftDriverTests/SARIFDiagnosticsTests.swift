//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
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
import TestUtilities
import Testing

@Suite struct SARIFDiagnosticsTests {
  /// Each primary gets its own SARIF log, and the format travels with the path.
  @Test func sarifFormatSelectsSARIFOutputs() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-typecheck", "foo.swift", "bar.swift",
      "-serialize-diagnostics=sarif",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let compileJobs = plannedJobs.filter { $0.kind == .compile }
    #expect(compileJobs.count == 2)

    for job in compileJobs {
      #expect(job.outputs.contains { $0.type == .sarifDiagnostics })
      #expect(!job.outputs.contains { $0.type == .diagnostics })
      #expect(job.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
      #expect(job.commandLine.contains(.flag("-serialize-diagnostics-path")))
    }
  }

  /// Without a format, diagnostics stay in the binary format and no format flag
  /// is passed to any job.
  @Test func bareFlagKeepsBinaryFormatAndPassesNoFormat() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-typecheck", "foo.swift", "bar.swift", "-serialize-diagnostics",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let compileJobs = plannedJobs.filter { $0.kind == .compile }
    #expect(compileJobs.count == 2)

    for job in compileJobs {
      #expect(job.outputs.contains { $0.type == .diagnostics })
      #expect(!job.outputs.contains { $0.type == .sarifDiagnostics })
      #expect(!job.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
      #expect(!job.commandLine.contains(.flag("-serialize-diagnostics=dia")))
    }
  }

  /// The format flag reaches only jobs that have a SARIF output. It turns
  /// serialization on by itself, so a job without one would otherwise start
  /// writing a log the driver knows nothing about.
  @Test func formatDoesNotReachJobsWithoutSARIFOutputs() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-emit-library", "-emit-module", "-module-name", "Test",
      "foo.swift", "bar.swift", "-serialize-diagnostics=sarif",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.contains { $0.kind == .link })

    for job in plannedJobs where job.kind != .compile && job.kind != .emitModule {
      #expect(!job.commandLine.contains(.flag("-serialize-diagnostics=sarif")), "\(job.kind)")
      #expect(!job.outputs.contains { $0.type == .sarifDiagnostics }, "\(job.kind)")
      #expect(!job.outputs.contains { $0.type == .emitModuleSARIFDiagnostics }, "\(job.kind)")
    }
  }

  /// The emit-module job's diagnostics follow the requested format, like the
  /// compile jobs'. Without this a SARIF build would drop them, where a binary
  /// build keeps them.
  @Test func emitModuleJobFollowsRequestedFormat() async throws {
    for (format, expectedType) in [
      ("-serialize-diagnostics=sarif", FileType.emitModuleSARIFDiagnostics),
      ("-serialize-diagnostics", .emitModuleDiagnostics),
      ("-serialize-diagnostics=dia", .emitModuleDiagnostics),
    ] {
      var driver = try TestDriver(args: [
        "swiftc", "-emit-module", "-module-name", "Test", "foo.swift", "bar.swift", format,
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let emitModuleJob = try #require(plannedJobs.first { $0.kind == .emitModule }, "\(format)")
      let diagnostics = emitModuleJob.outputs.filter {
        $0.type == .emitModuleDiagnostics || $0.type == .emitModuleSARIFDiagnostics
      }
      #expect(diagnostics.map(\.type) == [expectedType], "\(format)")
      #expect(diagnostics.first?.file.name.hasSuffix(".\(expectedType.rawValue)") == true, "\(format)")
      #expect(
        emitModuleJob.commandLine.contains(.flag("-serialize-diagnostics=sarif"))
          == (expectedType == .emitModuleSARIFDiagnostics), "\(format)")
    }
  }

  /// The emit-module job's SARIF log takes its path from the output file map's
  /// 'emit-module-sarif-diagnostics' entry, which is a single output for the
  /// whole module.
  @Test func emitModuleUsesOutputFileMapEntry() async throws {
    try await withTemporaryDirectory { path in
      let ofmPath = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofmPath) {
        $0.send(
          """
          {
            "": {
              "emit-module-sarif-diagnostics": "/out/module-from-map.emit-module.sarif",
              "emit-module-diagnostics": "/out/module-from-map.emit-module.dia"
            }
          }
          """
        )
      }
      var driver = try TestDriver(args: [
        "swiftc", "-emit-module", "-module-name", "Test", "foo.swift", "bar.swift",
        "-serialize-diagnostics=sarif", "-output-file-map", ofmPath.pathString,
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let emitModuleJob = try #require(plannedJobs.first { $0.kind == .emitModule })
      let diagnostics = emitModuleJob.outputs.filter { $0.type == .emitModuleSARIFDiagnostics }
      #expect(diagnostics.map(\.file) == [.absolute(try .init(validating: "/out/module-from-map.emit-module.sarif"))])
    }
  }

  /// An explicit emit-module diagnostics path is used for the SARIF log.
  @Test func emitModuleExplicitPathHoldsSARIFLog() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-emit-module", "-module-name", "Test", "foo.swift", "bar.swift",
      "-serialize-diagnostics=sarif",
      "-emit-module-serialize-diagnostics-path", "/out/explicit.sarif",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let emitModuleJob = try #require(plannedJobs.first { $0.kind == .emitModule })
    let diagnostics = emitModuleJob.outputs.filter { $0.type == .emitModuleSARIFDiagnostics }
    #expect(diagnostics.map(\.file) == [.absolute(try .init(validating: "/out/explicit.sarif"))])
    #expect(emitModuleJob.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
  }

  /// Paths passed in a supplementary output file map still come with the
  /// format, which the map does not carry.
  @Test func formatAccompaniesSupplementaryOutputFileMap() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-c", "foo.swift", "bar.swift",
      "-serialize-diagnostics=sarif", "-driver-filelist-threshold=0",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let compileJobs = plannedJobs.filter { $0.kind == .compile }
    #expect(compileJobs.count == 2)

    for job in compileJobs {
      #expect(job.commandLine.contains(.flag("-supplementary-output-file-map")))
      #expect(!job.commandLine.contains(.flag("-serialize-diagnostics-path")))
      #expect(job.outputs.contains { $0.type == .sarifDiagnostics })
      #expect(job.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
    }
  }

  /// A PCH job serializes its diagnostics in the requested format, like every
  /// other job. Diagnostics raised inside the bridging header are reported only
  /// by the job that builds the PCH, so a binary PCH log would hide them from a
  /// client reading SARIF.
  @Test func pchFollowsRequestedFormat() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-typecheck", "foo.swift",
      "-import-objc-header", "header.h", "-pch-output-dir", "/tmp/pch",
      "-emit-module-path", "/tmp/main.swiftmodule",
      "-serialize-diagnostics=sarif",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

    let pchJobs = plannedJobs.filter { $0.kind == .generatePCH }
    #expect(pchJobs.count == 1)
    for job in pchJobs {
      let diagnostics = job.outputs.filter { $0.type == .sarifDiagnostics }
      #expect(diagnostics.count == 1)
      let log = try #require(diagnostics.first)
      #expect(log.file.parentDirectory == .absolute(try .init(validating: "/tmp/pch")))
      #expect(log.file.basename.hasPrefix("header-"))
      #expect(diagnostics.first?.file.extension == "sarif")
      #expect(!job.outputs.contains { $0.type == .diagnostics })
      #expect(job.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
    }

    // The compile job serializes to SARIF too.
    let compileJobs = plannedJobs.filter { $0.kind == .compile }
    #expect(compileJobs.count == 1)
    for job in compileJobs {
      #expect(job.outputs.contains { $0.type == .sarifDiagnostics })
      #expect(job.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
    }
  }

  /// Without a format, a PCH job keeps the binary format.
  @Test func pchKeepsBinaryFormatByDefault() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-typecheck", "foo.swift",
      "-import-objc-header", "header.h", "-pch-output-dir", "/tmp/pch",
      "-serialize-diagnostics",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

    let pchJobs = plannedJobs.filter { $0.kind == .generatePCH }
    #expect(pchJobs.count == 1)
    for job in pchJobs {
      #expect(job.outputs.contains { $0.type == .diagnostics })
      #expect(!job.outputs.contains { $0.type == .sarifDiagnostics })
      #expect(!job.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
    }
  }

  /// An unknown format is an error wherever it appears.
  @Test func unknownFormatIsRejected() throws {
    for formats in [
      ["-serialize-diagnostics=bogus"],
      ["-serialize-diagnostics=sarif", "-serialize-diagnostics=bogus"],
      ["-serialize-diagnostics=bogus", "-serialize-diagnostics=sarif"],
      ["-serialize-diagnostics=bogus", "-serialize-diagnostics"],
    ] {
      let diagnosticEngine = DiagnosticsEngine()
      _ = try TestDriver(
        args: ["swiftc", "-typecheck", "foo.swift"] + formats,
        diagnosticsEngine: diagnosticEngine)
      #expect(diagnosticEngine.hasErrors, "\(formats)")
      #expect(
        diagnosticEngine.diagnostics.first?.message.data.description
          == "unsupported argument 'bogus' to option '-serialize-diagnostics='", "\(formats)")
    }
  }

  /// Asking for the binary format by name is the same as not naming one.
  @Test func explicitDiaFormatMatchesDefault() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-typecheck", "foo.swift", "-serialize-diagnostics=dia",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let compileJobs = plannedJobs.filter { $0.kind == .compile }
    #expect(compileJobs.count == 1)

    for job in compileJobs {
      #expect(job.outputs.contains { $0.type == .diagnostics })
      #expect(!job.outputs.contains { $0.type == .sarifDiagnostics })
      #expect(!job.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
      #expect(!job.commandLine.contains(.flag("-serialize-diagnostics=dia")))
    }
  }

  /// The last of the bare flag, which means 'dia', and a format wins.
  @Test func lastFormatArgumentWins() async throws {
    for (args, expected) in [
      (["-serialize-diagnostics=sarif", "-serialize-diagnostics=dia"], FileType.diagnostics),
      (["-serialize-diagnostics=dia", "-serialize-diagnostics=sarif"], .sarifDiagnostics),
      (["-serialize-diagnostics", "-serialize-diagnostics=sarif"], .sarifDiagnostics),
      (["-serialize-diagnostics=sarif", "-serialize-diagnostics"], .diagnostics),
    ] {
      var driver = try TestDriver(args: ["swiftc", "-typecheck", "foo.swift"] + args)
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let compileJobs = plannedJobs.filter { $0.kind == .compile }
      #expect(compileJobs.count == 1)

      for job in compileJobs {
        #expect(job.outputs.contains { $0.type == expected }, "\(args)")
        #expect(
          job.commandLine.contains(.flag("-serialize-diagnostics=sarif"))
            == (expected == .sarifDiagnostics), "\(args)")
      }
    }
  }

  /// An output file map's 'sarif-diagnostics' entry names the SARIF log, and
  /// its 'diagnostics' entry names the binary one; each is used only for its
  /// own format.
  @Test func outputFileMapNamesEachFormat() async throws {
    try await withTemporaryDirectory { path in
      let foo = path.appending(component: "foo.swift")
      let ofmPath = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofmPath) {
        $0.send(
          """
          {
            "\(foo.nativePathString(escaped: true))": {
              "sarif-diagnostics": "/out/foo-from-map.sarif",
              "diagnostics": "/out/foo-from-map.dia"
            }
          }
          """
        )
      }

      for (format, expectedType, expectedPath) in [
        ("-serialize-diagnostics=sarif", FileType.sarifDiagnostics, "/out/foo-from-map.sarif"),
        ("-serialize-diagnostics", .diagnostics, "/out/foo-from-map.dia"),
      ] {
        var driver = try TestDriver(args: [
          "swiftc", "-typecheck", foo.pathString, format,
          "-output-file-map", ofmPath.pathString,
        ])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let compileJob = try #require(plannedJobs.first { $0.kind == .compile })
        let diagnostics = compileJob.outputs.filter { $0.type == expectedType }
        #expect(diagnostics.map(\.file) == [.absolute(try .init(validating: expectedPath))], "\(format)")
        #expect(
          compileJob.commandLine.contains(
            .path(.absolute(try .init(validating: expectedPath)))), "\(format)")
      }
    }
  }

  /// In whole-module mode the single compile job takes its log path from the
  /// output file map's module-wide entry for the requested format.
  @Test func wholeModuleUsesModuleEntryForEachFormat() async throws {
    try await withTemporaryDirectory { path in
      let ofmPath = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofmPath) {
        $0.send(
          """
          {
            "": {
              "sarif-diagnostics": "/out/module-from-map.sarif",
              "diagnostics": "/out/module-from-map.dia"
            }
          }
          """
        )
      }

      for (format, expectedType, expectedPath) in [
        ("-serialize-diagnostics=sarif", FileType.sarifDiagnostics, "/out/module-from-map.sarif"),
        ("-serialize-diagnostics", .diagnostics, "/out/module-from-map.dia"),
      ] {
        var driver = try TestDriver(args: [
          "swiftc", "-typecheck", "-wmo", "-module-name", "Test", "foo.swift", "bar.swift",
          format, "-output-file-map", ofmPath.pathString,
        ])
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let compileJobs = plannedJobs.filter { $0.kind == .compile }
        #expect(compileJobs.count == 1, "\(format)")
        let compileJob = try #require(compileJobs.first, "\(format)")
        let diagnostics = compileJob.outputs.filter {
          $0.type == .diagnostics || $0.type == .sarifDiagnostics
        }
        #expect(diagnostics.map(\.type) == [expectedType], "\(format)")
        #expect(diagnostics.map(\.file) == [.absolute(try .init(validating: expectedPath))], "\(format)")
        #expect(
          compileJob.commandLine.contains(.flag("-serialize-diagnostics=sarif"))
            == (expectedType == .sarifDiagnostics), "\(format)")
      }
    }
  }

  /// A PCH job also takes its SARIF log path from the output file map.
  @Test func pchUsesOutputFileMapEntry() async throws {
    try await withTemporaryDirectory { path in
      let header = path.appending(component: "header.h")
      let ofmPath = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofmPath) {
        $0.send(
          """
          {
            "\(header.nativePathString(escaped: true))": {
              "sarif-diagnostics": "/out/header-from-map.sarif",
              "diagnostics": "/out/header-from-map.dia"
            }
          }
          """
        )
      }
      var driver = try TestDriver(args: [
        "swiftc", "-typecheck", "foo.swift",
        "-import-objc-header", header.pathString, "-pch-output-dir", "/tmp/pch",
        "-output-file-map", ofmPath.pathString,
        "-serialize-diagnostics=sarif",
      ])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let pchJob = try #require(plannedJobs.first { $0.kind == .generatePCH })
      let diagnostics = pchJob.outputs.filter { $0.type == .sarifDiagnostics }
      #expect(diagnostics.map(\.file) == [.absolute(try .init(validating: "/out/header-from-map.sarif"))])
      #expect(pchJob.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
    }
  }

  /// Without a module path to derive a name from, a persistent PCH's SARIF log
  /// is a temporary file.
  @Test func pchWithoutModulePathUsesTemporarySARIFFile() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-typecheck", "foo.swift",
      "-import-objc-header", "header.h", "-pch-output-dir", "/tmp/pch",
      "-serialize-diagnostics=sarif",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let pchJob = try #require(plannedJobs.first { $0.kind == .generatePCH })
    let diagnostics = pchJob.outputs.filter { $0.type == .sarifDiagnostics }
    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.file.isTemporary == true)
    #expect(diagnostics.first?.file.extension == "sarif")
    #expect(pchJob.commandLine.contains(.flag("-serialize-diagnostics=sarif")))
  }

  /// A SARIF log is named after the primary output it accompanies.
  @Test func sarifLogSitsBesideObjectFile() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-c", "foo.swift", "bar.swift", "-serialize-diagnostics=sarif",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let compileJobs = plannedJobs.filter { $0.kind == .compile }
    #expect(compileJobs.count == 2)

    for job in compileJobs {
      let object = try #require(job.outputs.first { $0.type == .object })
      let diagnostics = try #require(job.outputs.first { $0.type == .sarifDiagnostics })
      #expect(!diagnostics.file.isTemporary)
      #expect(diagnostics.file.basenameWithoutExt == object.file.basenameWithoutExt)
      #expect(diagnostics.file.extension == "sarif")
    }
  }

  /// A batch job with several primaries carries one SARIF log per primary and
  /// passes the format once.
  @Test func batchModeJobCarriesFormat() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-c", "foo.swift", "bar.swift", "-enable-batch-mode",
      "-driver-batch-count", "1", "-serialize-diagnostics=sarif",
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    let compileJobs = plannedJobs.filter { $0.kind == .compile }
    #expect(compileJobs.count == 1)

    for job in compileJobs {
      #expect(job.outputs.filter { $0.type == .sarifDiagnostics }.count == 2)
      #expect(
        job.commandLine.filter { $0 == .flag("-serialize-diagnostics=sarif") }.count == 1)
    }
  }

  /// swiftc chooses log paths itself, so it rejects an explicit one either way.
  @Test func explicitDiagnosticsPathIsRejected() throws {
    for format in ["-serialize-diagnostics=sarif", "-serialize-diagnostics"] {
      #expect(throws: OptionParseError.self, "\(format)") {
        _ = try TestDriver(args: [
          "swiftc", "-typecheck", "foo.swift", format,
          "-serialize-diagnostics-path", "/tmp/explicit.out",
        ])
      }
    }
  }

  /// The dependency scan's diagnostics follow the requested format. An import
  /// that cannot be resolved is reported by the scan, before any compile job
  /// runs, so a SARIF build would otherwise have no log of it at all.
  @Test func dependencyScanFollowsRequestedFormat() throws {
    for (format, expectedExtension) in [
      ("-serialize-diagnostics=sarif", FileType.dependencyScanSARIFDiagnostics.rawValue),
      ("-serialize-diagnostics", FileType.dependencyScanDiagnostics.rawValue),
      ("-serialize-diagnostics=dia", FileType.dependencyScanDiagnostics.rawValue),
    ] {
      var driver = try TestDriver(args: [
        "swiftc", "-explicit-module-build", "-module-name", "Test", "foo.swift", format,
      ])
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let scannerCommand = try driver.dependencyScannerInvocationCommand().1.map {
        try resolver.resolve($0)
      }
      let pathIndex = try #require(
        scannerCommand.firstIndex(of: "-serialize-diagnostics-path"), "\(format)")
      #expect(scannerCommand[pathIndex + 1].hasSuffix("Test.\(expectedExtension)"), "\(format)")
      #expect(
        scannerCommand.contains("-serialize-diagnostics=sarif")
          == (expectedExtension == FileType.dependencyScanSARIFDiagnostics.rawValue),
        "\(format)")
    }
  }

  /// An explicit dependency-scan diagnostics path is used for the SARIF log.
  @Test func dependencyScanExplicitPathHoldsSARIFLog() throws {
    var driver = try TestDriver(args: [
      "swiftc", "-explicit-module-build", "-module-name", "Test", "foo.swift",
      "-serialize-diagnostics=sarif",
      "-dependency-scan-serialize-diagnostics-path", "/out/scan.sarif",
    ])
    let resolver = try ArgsResolver(fileSystem: localFileSystem)
    let scannerCommand = try driver.dependencyScannerInvocationCommand().1.map {
      try resolver.resolve($0)
    }
    #expect(scannerCommand.contains(
      subsequence: [
        "-serialize-diagnostics-path", try AbsolutePath(validating: "/out/scan.sarif").pathString,
      ]))
    #expect(scannerCommand.contains("-serialize-diagnostics=sarif"))
  }

  /// In whole-module mode the dependency scan takes its log path from the
  /// output file map's module-wide entry for the requested format.
  @Test func dependencyScanUsesModuleEntryForEachFormat() throws {
    try withTemporaryDirectory { path in
      let ofmPath = path.appending(component: "ofm.json")
      try localFileSystem.writeFileContents(ofmPath) {
        $0.send(
          """
          {
            "": {
              "dependency-scan-sarif-diagnostics": "/out/scan-from-map.sarif",
              "dependency-scan-diagnostics": "/out/scan-from-map.dia"
            }
          }
          """
        )
      }

      for (format, expectedPath) in [
        ("-serialize-diagnostics=sarif", "/out/scan-from-map.sarif"),
        ("-serialize-diagnostics", "/out/scan-from-map.dia"),
      ] {
        var driver = try TestDriver(args: [
          "swiftc", "-explicit-module-build", "-wmo", "-module-name", "Test", "foo.swift",
          format, "-output-file-map", ofmPath.pathString,
        ])
        let resolver = try ArgsResolver(fileSystem: localFileSystem)
        let scannerCommand = try driver.dependencyScannerInvocationCommand().1.map {
          try resolver.resolve($0)
        }
        #expect(
          scannerCommand.contains(
            subsequence: [
              "-serialize-diagnostics-path", try AbsolutePath(validating: expectedPath).pathString,
            ]),
          "\(format)")
        #expect(
          scannerCommand.contains("-serialize-diagnostics=sarif")
            == expectedPath.hasSuffix(".sarif"), "\(format)")
      }
    }
  }

  /// The new file type's public properties.
  @Test func sarifDiagnosticsFileType() {
    #expect(FileType.sarifDiagnostics.rawValue == "sarif")
    #expect(FileType.sarifDiagnostics.description == "sarif-diagnostics")
    #expect(!FileType.sarifDiagnostics.isPartOfSwiftCompilation)
    #expect(FileType.emitModuleSARIFDiagnostics.rawValue == "emit-module.sarif")
    #expect(FileType.emitModuleSARIFDiagnostics.description == "emit-module-sarif-diagnostics")
    #expect(!FileType.emitModuleSARIFDiagnostics.isPartOfSwiftCompilation)
    #expect(FileType.dependencyScanSARIFDiagnostics.rawValue == "dependency-scan.sarif")
    #expect(FileType.dependencyScanSARIFDiagnostics.description == "dependency-scan-sarif-diagnostics")
    #expect(!FileType.dependencyScanSARIFDiagnostics.isPartOfSwiftCompilation)
  }
}
