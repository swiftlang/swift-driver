//===--------------- CacheLauncherTests.swift - swift-cache Tests ---------===//
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
import TSCBasic
import TestUtilities
import Testing

// These tests run copies of the built driver and shell script stubs.
#if !os(Windows)

#if os(macOS)
private final class TestBundleLocator {}
#endif

/// Copies the built driver to `swiftc` in `dir`, and links `swift-cache` to it.
private func makeDriverCopies(
  in dir: AbsolutePath
) throws -> (swiftCache: AbsolutePath, swiftc: AbsolutePath) {
  #if os(macOS)
  let binDir = try AbsolutePath(validating: Bundle(for: TestBundleLocator.self).bundlePath).parentDirectory
  #else
  let binDir = try AbsolutePath(validating: CommandLine.arguments[0]).parentDirectory
  #endif
  // Copy the driver because subcommand lookup resolves executable symlinks.
  let swiftc = dir.appending(component: "swiftc")
  try localFileSystem.copy(from: binDir.appending(component: "swift-driver"), to: swiftc)
  let swiftCache = dir.appending(component: "swift-cache")
  try localFileSystem.createSymbolicLink(swiftCache, pointingAt: swiftc, relative: true)
  return (swiftCache, swiftc)
}

/// Writes a script to `path` that prints `name` and its arguments, one per line.
private func makeStub(_ path: AbsolutePath, printing name: String) throws {
  try localFileSystem.writeFileContents(
    path, bytes: ByteString(encodingAsUTF8: "#!/bin/sh\nprintf '%s\\n' \(name) \"$@\"\n"))
  try localFileSystem.chmod(.executable, path: path)
}

/// The test environment with `settings` as the only caching configuration.
private func environment(_ settings: [String: String] = [:]) -> ProcessEnvironmentBlock {
  var env = ProcessEnv.block.filter { key, _ in
    !["LLVM_CACHE_", "SWIFT_CACHE_", "CLANG_CACHE_"].contains { key.value.hasPrefix($0) }
  }
  for (key, value) in settings {
    env[ProcessEnvironmentKey(key)] = value
  }
  return env
}

@Suite struct CacheLauncherTests {
  @Test func missingCompilerCommand() async throws {
    try await withTemporaryDirectory { path in
      let (swiftCache, _) = try makeDriverCopies(in: path)
      let result = try await Process.popen(arguments: [swiftCache.pathString],
                                           environmentBlock: environment())
      #expect(result.exitStatus == .terminated(code: 1))
      #expect(try result.utf8stderrOutput().contains(
        "error: missing compiler command for swift-cache"))
    }
  }

  @Test func cannotFindCompiler() async throws {
    try await withTemporaryDirectory { path in
      let (swiftCache, _) = try makeDriverCopies(in: path)
      let result = try await Process.popen(
        arguments: [swiftCache.pathString, "no-such-swiftc", "-c", "a.swift"],
        environmentBlock: environment())
      #expect(result.exitStatus == .terminated(code: 1))
      #expect(try result.utf8stderrOutput().contains(
        "error: swift-cache cannot find compiler binary 'no-such-swiftc'"))
    }
  }

  @Test func forwardsDifferentCompiler() async throws {
    try await withTemporaryDirectory { path in
      let (swiftCache, _) = try makeDriverCopies(in: path)
      let otherDir = path.appending(component: "other")
      try localFileSystem.createDirectory(otherDir)
      let otherSwiftc = otherDir.appending(component: "swiftc")
      try makeStub(otherSwiftc, printing: "other-swiftc")

      let result = try await Process.popen(
        arguments: [swiftCache.pathString, otherSwiftc.pathString, "-c", "a.swift"],
        environmentBlock: environment(["LLVM_CACHE_CAS_PATH": path.appending(component: "cas").pathString]))
      #expect(result.exitStatus == .terminated(code: 0))
      #expect(try result.utf8Output() == "other-swiftc\n-c\na.swift\n")
      #expect(try result.utf8stderrOutput().contains(
        "warning: caching disabled because swift-cache invokes a different swiftc than itself"))
    }
  }

  @Test func frontendInvocation() async throws {
    try await withTemporaryDirectory { path in
      let (swiftCache, swiftc) = try makeDriverCopies(in: path)
      try makeStub(path.appending(component: "swift-frontend"), printing: "frontend-dispatched")
      let responseFile = path.appending(component: "frontend.rsp")
      try localFileSystem.writeFileContents(responseFile, bytes: "-frontend\n-c\na.swift\n")

      for args in [["-frontend", "-c", "a.swift"], ["@" + responseFile.pathString]] {
        let result = try await Process.popen(
          arguments: [swiftCache.pathString, swiftc.pathString] + args,
          environmentBlock: environment(["LLVM_CACHE_CAS_PATH": path.appending(component: "cas").pathString]))
        #expect(result.exitStatus == .terminated(code: 0))
        #expect(try result.utf8Output() == "frontend-dispatched\n-c\na.swift\n")
        #expect(try result.utf8stderrOutput().contains(
          "warning: caching disabled because swift-cache does not support frontend invocations"))
      }
    }
  }

  @Test func interactiveDriver() async throws {
    try await withTemporaryDirectory { path in
      let (swiftCache, swiftc) = try makeDriverCopies(in: path)
      let swift = path.appending(component: "swift")
      try localFileSystem.createSymbolicLink(swift, pointingAt: swiftc, relative: true)
      try makeStub(path.appending(component: "swift-frontend"), printing: "frontend-dispatched")

      let result = try await Process.popen(
        arguments: [swiftCache.pathString, swift.pathString, "-frontend", "-c", "a.swift"],
        environmentBlock: environment())
      #expect(result.exitStatus == .terminated(code: 0))
      #expect(try result.utf8Output() == "frontend-dispatched\n-c\na.swift\n")
      #expect(try result.utf8stderrOutput().contains(
        "warning: caching disabled because swift-cache only supports 'swiftc' invocations"))
    }
  }

  @Test func launcherLinkedFromAnotherDirectory() async throws {
    try await withTemporaryDirectory { path in
      let binDir = path.appending(component: "bin")
      try localFileSystem.createDirectory(binDir)
      let (_, swiftc) = try makeDriverCopies(in: binDir)
      try makeStub(binDir.appending(component: "swift-frontend"), printing: "frontend-dispatched")
      let launcherDir = path.appending(component: "launcher")
      try localFileSystem.createDirectory(launcherDir)
      let swiftCache = launcherDir.appending(component: "swift-cache")
      try localFileSystem.createSymbolicLink(swiftCache, pointingAt: swiftc, relative: false)

      // `swiftc` resolves to the same driver, so it runs in the `swift-cache`
      // process instead of being forwarded.
      let result = try await Process.popen(
        arguments: [swiftCache.pathString, swiftc.pathString, "-frontend", "-c", "a.swift"],
        environmentBlock: environment())
      #expect(result.exitStatus == .terminated(code: 0))
      #expect(try result.utf8Output() == "frontend-dispatched\n-c\na.swift\n")
      #expect(try result.utf8stderrOutput().contains(
        "warning: caching disabled because swift-cache does not support frontend invocations"))
    }
  }
}

@Suite(.enabled(if: cachingFeatureSupported, "caching not supported"))
struct CacheLauncherCachingTests {
  /// Returns the job compiling `main.swift` planned by `swift-cache swiftc`
  /// with the caching configuration `settings`.
  private func compileJob(in path: AbsolutePath,
                          settings: [String: String]) async throws -> String {
    let (swiftCache, swiftc) = try makeDriverCopies(in: path)
    let source = path.appending(component: "main.swift")
    try localFileSystem.writeFileContents(source, bytes: "public func foo() {}\n")
    let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

    // The source after `--` checks that the caching options are inserted before it.
    let result = try await Process.popen(
      arguments: [swiftCache.pathString, swiftc.pathString, "-c", "-module-name", "Foo",
                  "-parse-as-library", "-driver-print-jobs"]
        + sdkArgumentsForTesting + ["--", source.pathString],
      environmentBlock: environment(settings))
    let stderr = try result.utf8stderrOutput()
    #expect(result.exitStatus == .terminated(code: 0), "\(stderr)")
    let job = try #require(try result.utf8Output().split(separator: "\n").first {
      $0.contains("-primary-file")
    })
    return String(job)
  }

  @Test func cachingArguments() async throws {
    try await withTemporaryDirectory { tmpDir in
      let path = try resolveSymlinks(tmpDir)
      let casPath = path.appending(component: "cas")
      let job = try await compileJob(in: path, settings: [
        "LLVM_CACHE_CAS_PATH": casPath.pathString,
        "LLVM_CACHE_PLUGIN_OPTIONS": "a=b:c=d",
        "LLVM_CACHE_PREFIX_MAPS": "\(path.pathString)=/^src;\(casPath.pathString)=/^cas",
      ])
      #expect(job.contains("-cache-compile-job"))
      #expect(job.contains("-cas-path \(casPath.pathString)"))
      #expect(job.contains("-cas-plugin-option a=b -cas-plugin-option c=d"))
      #expect(job.contains("/^src/main.swift"))
      #expect(job.contains("/^cas"))
      #expect(job.contains("/^toolchain"))
      #if canImport(Darwin)
      #expect(job.contains("-cas-backend"))
      #expect(job.contains("-cas-friendly-debug-info"))
      #else
      #expect(!job.contains("-cas-backend"))
      #endif
    }
  }

  @Test func swiftSettingsTakePrecedence() async throws {
    try await withTemporaryDirectory { tmpDir in
      let path = try resolveSymlinks(tmpDir)
      let casPath = path.appending(component: "cas")
      let job = try await compileJob(in: path, settings: [
        "LLVM_CACHE_CAS_PATH": "/llvm-cas",
        "SWIFT_CACHE_CAS_PATH": casPath.pathString,
        "LLVM_CACHE_PLUGIN_OPTIONS": "llvm=1",
        "SWIFT_CACHE_PLUGIN_OPTIONS": "swift=1",
        "LLVM_CACHE_REMOTE_SERVICE_SOCKET_PATH": "/tmp/llvm-service",
        "SWIFT_CACHE_REMOTE_SERVICE_SOCKET_PATH": "/tmp/swift-service",
        "LLVM_CACHE_PREFIX_MAPS": "\(path.pathString)=/^llvm",
        "SWIFT_CACHE_PREFIX_MAPS": "\(path.pathString)=/^swift",
      ])
      #expect(job.contains("-cas-path \(casPath.pathString)"))
      #expect(job.contains(
        "-cas-plugin-option swift=1 -cas-plugin-option remote-service-path=/tmp/swift-service"))
      #expect(job.contains("/^swift/main.swift"))
      for llvmValue in ["/llvm-cas", "llvm=1", "/tmp/llvm-service", "/^llvm"] {
        #expect(!job.contains(llvmValue))
      }
    }
  }

  @Test func defaultCASPath() async throws {
    try await withTemporaryDirectory { tmpDir in
      let path = try resolveSymlinks(tmpDir)
      #if canImport(Darwin)
      let job = try await compileJob(in: path, settings: [:])
      #expect(job.contains("/llvm.cas.builtin.default/cas "))
      #else
      let job = try await compileJob(in: path, settings: ["XDG_CACHE_HOME": path.pathString])
      #expect(job.contains("-cas-path \(path.pathString)/llvm.cas.builtin.default/cas "))
      #endif
    }
  }

  @Test(arguments: [
    ["SWIFT_CACHE_DISABLE_MCCAS": "1"],
    ["CLANG_CACHE_DISABLE_MCCAS": "1"],
    ["LLVM_CACHE_REMOTE_SERVICE_SOCKET_PATH": "/tmp/service"],
    ["LLVM_CACHE_PLUGIN_OPTIONS": "remote-service-path=/tmp/service"],
  ])
  func disabledCASBackend(settings: [String: String]) async throws {
    try await withTemporaryDirectory { path in
      let job = try await compileJob(in: path, settings: settings.merging(
        ["LLVM_CACHE_CAS_PATH": path.appending(component: "cas").pathString]) { $1 })
      #expect(job.contains("-cache-compile-job"))
      #expect(!job.contains("-cas-backend"))
    }
  }

  // A remote service in the plugin options takes precedence.
  @Test(arguments: [
    ([String: String](), "remote-service-path=/tmp/service"),
    (["LLVM_CACHE_PLUGIN_OPTIONS": "remote-service-path=/tmp/other"], "remote-service-path=/tmp/other"),
  ])
  func remoteServicePluginOption(settings: [String: String], pluginOption: String) async throws {
    try await withTemporaryDirectory { path in
      let job = try await compileJob(in: path, settings: settings.merging([
        "LLVM_CACHE_CAS_PATH": path.appending(component: "cas").pathString,
        "LLVM_CACHE_REMOTE_SERVICE_SOCKET_PATH": "/tmp/service",
      ]) { $1 })
      #expect(job.contains("-cas-plugin-option \(pluginOption)"))
      #expect(job.components(separatedBy: "remote-service-path=").count == 2)
    }
  }
}

#endif
