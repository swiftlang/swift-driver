//===--------------- Toolchain.swift - Swift Toolchain Abstraction --------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import TSCBasic

public enum Tool {
  case swiftCompiler
  case staticLinker
  case dynamicLinker
  case clang
  case swiftAutolinkExtract
  case dsymutil
}

/// Describes a toolchain, which includes information about compilers, linkers
/// and other tools required to build Swift code.
public protocol Toolchain {
  init(env: [String: String])
  
  var env: [String: String] { get }
  
  /// Retrieve the absolute path to a particular tool.
  func getToolPath(_ tool: Tool) throws -> AbsolutePath

  /// Returns path of the default SDK, if there is one.
  func defaultSDKPath() throws -> AbsolutePath?

  /// When the compiler invocation should be stored in debug information.
  var shouldStoreInvocationInDebugInfo: Bool { get }

  /// Constructs a proper output file name for a linker product.
  func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String

  /// Adds platform-specific linker flags to the provided command line
  func addPlatformSpecificLinkerArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    linkerOutputType: LinkOutputType,
    inputs: [TypedVirtualPath],
    outputFile: VirtualPath,
    sdkPath: String?,
    sanitizers: Set<Sanitizer>,
    targetTriple: Triple
  ) throws -> AbsolutePath

  func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String
}

extension Toolchain {
  public func swiftCompilerVersion() throws -> String {
    try Process.checkNonZeroExit(
      args: getToolPath(.swiftCompiler).pathString, "-version",
      environment: env
    ).split(separator: "\n").first.map(String.init) ?? ""
  }
  
  /// Returns the target triple string for the current host.
  public func hostTargetTriple() throws -> Triple {
    let triple = try Process.checkNonZeroExit(
      args: getToolPath(.clang).pathString, "-print-target-triple",
      environment: env
    ).spm_chomp()
    return Triple(triple)
  }
  
  /// Returns the `executablePath`'s directory.
  public var executableDir: AbsolutePath {
    guard let path = Bundle.main.executablePath else {
      fatalError("Could not find executable path.")
    }
    return AbsolutePath(path).parentDirectory
  }
}
