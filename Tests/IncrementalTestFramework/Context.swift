//===-------------- Context.swift - Swift Testing ----------- ---------===//
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
import TSCBasic
import XCTest

/// Bundles up (incidental) values to be passed down to the various functions.
///
/// - seealso: Test
struct Context: CustomStringConvertible {
  enum IncrementalImports: String, CustomStringConvertible {
    case enabled, disabled
    var description: String { rawValue }
  }
  /// The root directory for the whole test
  let rootDir: AbsolutePath

  let incrementalImports: IncrementalImports

  /// Set to true for debugging by passing `verbose: true` to `IncrementalTest.perform`.
  let verbose: Bool

  /// Helpful for debugging
  let stepIndex: Int

  /// Help Xcode place the errors in the right places
  let file: StaticString
  let line: UInt

  /// Copy with the passed values
  func with(stepIndex: Int, file: StaticString, line: UInt) -> Self {
    Self(rootDir: rootDir, incrementalImports: incrementalImports, verbose: verbose,
         stepIndex: stepIndex,
         file: file, line: line)
  }

  /// Each module has its own directory under the root
  private func modulePath(for module: Module) -> AbsolutePath {
    rootDir.appending(component: module.name)
  }
  func derivedDataPath(for module: Module) -> AbsolutePath {
    modulePath(for: module).appending(component: "\(module.name)DD")
  }
  func sourceDir(for module: Module) -> AbsolutePath {
    modulePath(for: module)
  }
  func swiftFilePath(for source: Source, in module: Module) -> AbsolutePath {
    sourceDir(for: module).appending(component: "\(source.name).swift")
  }
  func objFilePath(for source: Source, in module: Module) -> AbsolutePath {
    derivedDataPath(for: module).appending(component: "\(source.name).o")
  }
  func allObjFilePaths(in module: Module) -> [AbsolutePath] {
    module.sources.map {objFilePath(for: $0, in: module)}
  }
  func allImportedObjFilePaths(in module: Module) -> [AbsolutePath] {
    module.imports.flatMap(allObjFilePaths(in:))
  }
  func outputFileMapPath(for module: Module) -> AbsolutePath {
    derivedDataPath(for: module).appending(component: "OFM.json")
  }
  func swiftmodulePath(for module: Module) -> AbsolutePath {
    derivedDataPath(for: module).appending(component: "\(module.name).swiftmodule")
  }
  func executablePath(for module: Module) -> AbsolutePath {
    derivedDataPath(for: module).appending(component: "a.out")
  }

  var description: String {
    "Incremental imports \(incrementalImports)"
  }

  func failMessage(_ step: Step) -> String {
    "\(description), in step \(stepIndex), \(step.whatIsBuilt)"
  }

  func fail(_ msg: String, _ step: Step) {
    XCTFail("\(msg) \(failMessage(step))")
  }
}
