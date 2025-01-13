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
struct Context {
  /// The root directory for the whole test
  let rootDir: AbsolutePath

  /// Set to true for debugging by passing `verbose: true` to `IncrementalTest.perform`.
  let verbose: Bool

  /// Helpful for debugging
  let stepIndex: Int

  /// Help Xcode place the errors in the right places
  let file: StaticString
  let line: UInt

  /// Copy with the passed values
  func with(stepIndex: Int, file: StaticString, line: UInt) -> Self {
    Self(rootDir: rootDir, verbose: verbose,
         stepIndex: stepIndex,
         file: file, line: line)
  }

  func failMessage(_ step: Step) -> String {
    "in step \(stepIndex), \(step.whatIsBuilt)"
  }

  func fail(_ msg: String, _ step: Step) {
    XCTFail("\(msg) \(failMessage(step))")
  }
}

// MARK: Paths

extension Context {
  /// Computes the directory containing the given module's build products.
  ///
  /// - Parameter module: The module.
  /// - Returns: An absolute path to the build root - relative to the root
  ///            directory of this test context.
  func buildRoot(for module: Module) -> AbsolutePath {
    self.rootDir.appending(component: "\(module.name)-buildroot")
  }

  /// Computes the directory containing the given module's source files.
  ///
  /// - Parameter module: The module.
  /// - Returns: An absolute path to the build root - relative to the root
  ///            directory of this test context.
  func sourceRoot(for module: Module) -> AbsolutePath {
    self.rootDir.appending(component: "\(module.name)-srcroot")
  }

  /// Computes the path to the output file map for the given module.
  ///
  /// - Parameter module: The module.
  /// - Returns: An absolute path to the output file map - relative to the root
  ///            directory of this test context.
  func outputFileMapPath(for module: Module) -> AbsolutePath {
    self.buildRoot(for: module).appending(component: "OFM")
  }

  /// Computes the path to the `.swiftmodule` file for the given module.
  ///
  /// - Parameter module: The module.
  /// - Returns: An absolute path to the swiftmodule file - relative to the root
  ///            directory of this test context.
  func swiftmodulePath(for module: Module) -> AbsolutePath {
    self.buildRoot(for: module).appending(component: "\(module.name).swiftmodule")
  }

  /// Computes the path to the `.swift` file for the given module.
  ///
  /// - Parameter source: The name of the swift file.
  /// - Parameter module: The module.
  /// - Returns: An absolute path to the swift file - relative to the root
  ///            directory of this test context.
  func swiftFilePath(for source: Source, in module: Module) -> AbsolutePath {
    self.sourceRoot(for: module).appending(component: "\(source.name).swift")
  }

  /// Computes the path to the `.o` file for the given module.
  ///
  /// - Parameter source: The name of the swift file.
  /// - Parameter module: The module.
  /// - Returns: An absolute path to the object file - relative to the root
  ///            directory of this test context.
  func objectFilePath(for source: Source, in module: Module) -> AbsolutePath {
    self.buildRoot(for: module).appending(component: "\(source.name).o")
  }

  /// Computes the path to the executable file for the given module.
  ///
  /// - Parameter module: The module.
  /// - Returns: An absolute path to the executable file - relative to the root
  ///            directory of this test context.
  func executablePath(for module: Module) -> AbsolutePath {
    #if os(Windows)
    return self.buildRoot(for: module).appending(component: "a.exe")
    #else
    return self.buildRoot(for: module).appending(component: "a.out")
    #endif
  }
}


