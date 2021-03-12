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

  /// Help Xcode place the errors in the right places
  let file: StaticString
  let line: UInt

  /// Copy with the passed values
  func with(file: StaticString, line: UInt) -> Self {
    Self(rootDir: rootDir, incrementalImports: incrementalImports, verbose: verbose,
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
  func outputFileMapPath(for module: Module) -> AbsolutePath {
    derivedDataPath(for: module).appending(component: "OFM.json")
  }
  func swiftmodulePath(for module: Module) -> AbsolutePath {
    derivedDataPath(for: module).appending(component: "\(module.name).swiftmodule")
  }

  var description: String {
    "Incremental imports \(incrementalImports)"
  }
}
