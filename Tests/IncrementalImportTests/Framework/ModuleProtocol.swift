//===------- IncrementalImportTestFramework.swift - Swift Testing ---------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities


/// Each test must implement an enum that conforms and describes the modules in the test.
protocol ModuleProtocol: TestPartProtocol {
  associatedtype Source: SourceProtocol

  /// Returns the source paths in the module
  var sources: [Source] {get}

  /// Returns the imported modules (if any) in the module
  var imports: [Self] {get}

  /// Returns true iff the module is a library, vs an app
  var isLibrary: Bool {get}
}

extension ModuleProtocol {
 /// The name of the module, as appears in the `import` statement
  var name: String { rawValue }

  static var allSources: [Source] {
    allCases.flatMap {$0.sources}
  }

  /// Arguments used for every build
  func arguments(
    in testDir: AbsolutePath,
    compiling inputs: [Source],
    withIncrementalImports: Bool) -> [String] {
    var libraryArgs: [String] {
      ["-parse-as-library",
       "-emit-module-path", swiftmodulePath(in: testDir).pathString]
    }
    var appArgs: [String] {
      let swiftModules = imports .map {
        $0.swiftmodulePath(in: testDir).parentDirectory.pathString
      }
      return swiftModules.flatMap { ["-I", $0, "-F", $0] }
    }
    return Array(
    [
      [
        "swiftc",
        "-no-color-diagnostics",
        "-incremental",
        "-driver-show-incremental",
        "-driver-show-job-lifecycle",
        "-c",
        "-module-name", name,
        "-output-file-map", outputFileMapPath(in: testDir).pathString,
        "-\(withIncrementalImports ? "en" : "dis")able-incremental-imports"
      ],
      isLibrary ? libraryArgs : appArgs,
      inputs.map {$0.sourcePath(in: testDir).pathString}
    ].joined())
  }

  func createDerivedDataAndOFM(in testDir: AbsolutePath) {
    try! localFileSystem.createDirectory(derivedDataPath(in: testDir))
    writeOFM(in: testDir)
  }

  private func writeOFM(in testDir: AbsolutePath) {
    OutputFileMapCreator.write(
      module: name,
      inputPaths: sources.map {$0.sourcePath(in: testDir)},
      derivedData: derivedDataPath(in: testDir),
      to: outputFileMapPath(in: testDir))
  }

  func derivedDataPath(in testDir: AbsolutePath) -> AbsolutePath {
    testDir.appending(component: "\(name)DD")
  }
  func outputFileMapPath(in testDir: AbsolutePath) -> AbsolutePath {
    derivedDataPath(in: testDir).appending(component: "OFM")
  }
  func swiftmodulePath(in testDir: AbsolutePath) -> AbsolutePath {
    derivedDataPath(in: testDir).appending(component: "\(name).swiftmodule")
  }
}
