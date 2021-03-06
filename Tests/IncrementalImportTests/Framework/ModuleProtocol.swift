//===--------------- ModuleProtocol.swift - Swift Testing -----------------===//
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

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities


/// Each test must implement an enum that conforms and describes the modules in the test.
/// (See `TestProtocol`.)
protocol ModuleProtocol: TestPartProtocol {
  /// The type of the Source (versions)
  associatedtype Source: SourceProtocol

  /// The modules imported by this module, if any.
  var imports: [Self] {get}

  /// Returns true iff the module is a library, vs an app
  var isLibrary: Bool {get}
}

extension ModuleProtocol {
  /// The name of the module, as appears in the `import` statement
  var name: String { rawValue }

  func createDerivedDataDir(_ context: TestContext) {
    try! localFileSystem.createDirectory(derivedDataPath(context))
  }

  func derivedDataPath(_ context: TestContext) -> AbsolutePath {
    context.rootDir.appending(component: "\(name)DD")
  }
  func outputFileMapPath(_ context: TestContext) -> AbsolutePath {
    derivedDataPath(context).appending(component: "OFM")
  }
  func swiftmodulePath(_ context: TestContext) -> AbsolutePath {
    derivedDataPath(context).appending(component: "\(name).swiftmodule")
  }
}
