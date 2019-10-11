//===--------------- DarwinToolchain.swift - Swift Darwin Toolchain -------===//
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
import TSCBasic

fileprivate func envVarName(forExecutable toolName: String) -> String {
  return "SWIFT_DRIVER_\(toolName.uppercased())_EXEC"
}

/// Toolchain for Darwin-based platforms, such as macOS and iOS.
///
/// FIXME: This class is not thread-safe.
public final class DarwinToolchain: Toolchain {
  public let env: [String: String]

  func xcrunFind(exec: String) throws -> AbsolutePath {
    if let overrideString = env[envVarName(forExecutable: exec)] {
      return try AbsolutePath(validating: overrideString)
    }

  #if os(macOS)
    let path = try Process.checkNonZeroExit(
      arguments: ["xcrun", "-sdk", "macosx", "--find", exec],
      environment: env
    ).spm_chomp()
    return AbsolutePath(path)
  #else
    // This is a hack so our tests work on linux. We need a better way for looking up tools in general.
    return AbsolutePath("/usr/bin/" + exec)
  #endif
  }

  /// Retrieve the absolute path for a given tool.
  public func getToolPath(_ tool: Tool) throws -> AbsolutePath {
    switch tool {
    case .swiftCompiler:
      return try xcrunFind(exec: "swift")

    case .dynamicLinker:
      return try xcrunFind(exec: "ld")

    case .staticLinker:
      return try xcrunFind(exec: "libtool")

    case .dsymutil:
      return try xcrunFind(exec: "dsymutil")

    case .clang:
      let result = try Process.checkNonZeroExit(
        arguments: ["xcrun", "-toolchain", "default", "-f", "clang"],
        environment: env
      ).spm_chomp()
      return AbsolutePath(result)
    case .swiftAutolinkExtract:
      return try xcrunFind(exec: "swift-autolink-extract")
    }
  }

  /// Swift compiler path.
  public lazy var swiftCompiler: Result<AbsolutePath, Swift.Error> = Result {
    try xcrunFind(exec: "swift")
  }

  /// SDK path.
  public lazy var sdk: Result<AbsolutePath, Swift.Error> = Result {
    let result = try Process.checkNonZeroExit(
      arguments: ["xcrun", "-sdk", "macosx", "--show-sdk-path"],
      environment: env
    ).spm_chomp()
    return AbsolutePath(result)
  }

  /// Path to the StdLib inside the SDK.
  public func sdkStdlib(sdk: AbsolutePath) -> AbsolutePath {
    sdk.appending(RelativePath("usr/lib/swift"))
  }

  public var resourcesDirectory: Result<AbsolutePath, Swift.Error> {
    // FIXME: This will need to take -resource-dir and target triple into account.
    return swiftCompiler.map{ $0.appending(RelativePath("../../lib/swift/macosx")) }
  }

  
  public init(env: [String: String]) {
    self.env = env
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return moduleName
    case .dynamicLibrary: return "lib\(moduleName).dylib"
    case .staticLibrary: return "lib\(moduleName).a"
    }
  }

  public var compatibility50: Result<AbsolutePath, Error> {
    resourcesDirectory.map{ $0.appending(component: "libswiftCompatibility50.a") }
  }

  public var compatibilityDynamicReplacements: Result<AbsolutePath, Error> {
    resourcesDirectory.map{ $0.appending(component: "libswiftCompatibilityDynamicReplacements.a") }
  }

  public var clangRT: Result<AbsolutePath, Error> {
    resourcesDirectory.map{ $0.appending(RelativePath("../clang/lib/darwin/libclang_rt.osx.a")) }
  }

  public func defaultSDKPath() throws -> AbsolutePath? {
    let result = try Process.checkNonZeroExit(
      arguments: ["xcrun", "-sdk", "macosx", "--show-sdk-path"],
      environment: env
    ).spm_chomp()
    return AbsolutePath(result)
  }

  public var shouldStoreInvocationInDebugInfo: Bool {
    // This matches the behavior in Clang.
    !(env["RC_DEBUG_OPTIONS"]?.isEmpty ?? false)
  }

  public func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String {
    return """
    libclang_rt.\(sanitizer.libraryName)_\
    \(targetTriple.darwinPlatform!.libraryNameSuffix)\
    \(isShared ? "_dynamic.dylib" : ".a")
    """
  }
}
