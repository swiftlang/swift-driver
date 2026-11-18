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

import SwiftDriver
import SwiftOptions

#if canImport(Darwin)
import Darwin
#endif
import class Foundation.FileManager

import struct TSCBasic.AbsolutePath
import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.DiagnosticData
import class TSCBasic.Process
import typealias TSCBasic.ProcessEnvironmentBlock
import struct TSCBasic.ProcessEnvironmentKey
import func TSCBasic.resolveSymlinks

/// `swift-cache` is a compiler launcher (e.g. `CMAKE_Swift_COMPILER_LAUNCHER`)
/// for compilation caching. It is invoked as
/// `/path/to/swift-cache /path/to/swiftc <args>`, and adds the caching options
/// configured by environment variables. Each `SWIFT_CACHE_<NAME>` variable
/// takes precedence over the `LLVM_CACHE_<NAME>` variable it shares with
/// `clang-cache`:
///
/// - `CAS_PATH`: `-cas-path`, defaulting to the default CAS of `clang-cache`
/// - `PLUGIN_PATH`: `-cas-plugin-path`
/// - `PLUGIN_OPTIONS`: `:`-separated `-cas-plugin-option`s
/// - `REMOTE_SERVICE_SOCKET_PATH`: the `remote-service-path` plugin option
/// - `PREFIX_MAPS`: `;`-separated `-scanner-prefix-map`s
///
/// `SWIFT_CACHE_DISABLE_MCCAS` (or `CLANG_CACHE_DISABLE_MCCAS`) disables the
/// CAS backend for object files, which is otherwise used for Darwin targets
/// unless a remote caching service is used.
///
/// When `swiftc` is the same driver as `swift-cache`, the compilation runs in
/// the `swift-cache` process. Otherwise, the command is executed unchanged.
enum CacheLauncher {
  static let name = "swift-cache"

  enum Invocation {
    /// Run the wrapped `swiftc` command in this process.
    case runInProcess([String])
    /// Execute the wrapped command, which is not this driver, as is.
    case forward([String])
  }

  enum Error: Swift.Error, DiagnosticData {
    case missingCompilerCommand
    case cannotFindCompiler(String)

    var description: String {
      switch self {
      case .missingCompilerCommand:
        return "missing compiler command for swift-cache"
      case .cannotFindCompiler(let compiler):
        return "swift-cache cannot find compiler binary '\(compiler)'"
      }
    }
  }

  static func isLauncher(_ programPath: String) throws -> Bool {
    try VirtualPath(path: programPath).basenameWithoutExt == name
  }

  /// Drops the `swift-cache` program from `args` and determines how to run the
  /// wrapped compiler command.
  static func resolve(_ args: [String],
                      diagnosticsEngine: DiagnosticsEngine) throws -> Invocation {
    guard args.count > 1 else {
      throw Error.missingCompilerCommand
    }
    guard let compilerPath = Process.findExecutable(args[1]) else {
      throw Error.cannotFindCompiler(args[1])
    }
    let compilerArgs = [compilerPath.pathString] + args[2...]

    // The toolchain is located relative to this executable, so only a `swiftc`
    // from the same toolchain can run in this process.
    guard let launcherPath = Process.findExecutable(args[0]),
          isSameProgram(launcherPath, compilerPath) else {
      diagnosticsEngine.emit(.warning(
        "caching disabled because swift-cache invokes a different swiftc than itself"))
      return .forward(compilerArgs)
    }
    return .runInProcess(compilerArgs)
  }

  /// Adds the caching options to the wrapped compiler command `args`, whose
  /// response files have been expanded.
  static func addCachingArguments(to args: [String],
                                  env: ProcessEnvironmentBlock,
                                  diagnosticsEngine: DiagnosticsEngine) throws -> [String] {
    var driverName = try VirtualPath(path: args[0]).basenameWithoutExt
    var driverArgs = args.dropFirst()
    let driverModeOption = "--driver-mode="
    if let firstArg = driverArgs.first, firstArg.hasPrefix(driverModeOption) {
      driverName = String(firstArg.dropFirst(driverModeOption.count))
      driverArgs = driverArgs.dropFirst()
    }
    guard driverName == DriverKind.batch.rawValue else {
      diagnosticsEngine.emit(.warning(
        "caching disabled because swift-cache only supports 'swiftc' invocations"))
      return args
    }
    if case .subcommand = try Driver.invocationRunMode(forArgs: args).mode {
      diagnosticsEngine.emit(.warning(
        "caching disabled because swift-cache does not support frontend invocations"))
      return args
    }

    /// The value of `SWIFT_CACHE_<name>`, or else of `LLVM_CACHE_<name>`.
    func value(_ name: String) -> String? {
      for prefix in ["SWIFT_CACHE_", "LLVM_CACHE_"] {
        if let value = env[ProcessEnvironmentKey(prefix + name)], !value.isEmpty {
          return value
        }
      }
      return nil
    }

    var cachingArgs = ["-explicit-module-build", "-cache-compile-job"]
    if let casPath = value("CAS_PATH") ?? defaultCASPath(env: env)?.pathString {
      cachingArgs += ["-cas-path", casPath]
    }
    if let pluginPath = value("PLUGIN_PATH") {
      cachingArgs += ["-cas-plugin-path", pluginPath]
    }

    let remoteServiceOption = "remote-service-path="
    var pluginOptions = value("PLUGIN_OPTIONS")?.split(separator: ":").map(String.init) ?? []
    if let servicePath = value("REMOTE_SERVICE_SOCKET_PATH"),
       !pluginOptions.contains(where: { $0.hasPrefix(remoteServiceOption) }) {
      pluginOptions.append(remoteServiceOption + servicePath)
    }
    for option in pluginOptions {
      cachingArgs += ["-cas-plugin-option", option]
    }

    let prefixMaps = value("PREFIX_MAPS")?.split(separator: ";").map(String.init) ?? []
    if !prefixMaps.isEmpty {
      cachingArgs += ["-scanner-prefix-map-sdk", "/^sdk",
                      "-scanner-prefix-map-toolchain", "/^toolchain"]
      for prefixMap in prefixMaps {
        cachingArgs += ["-scanner-prefix-map", prefixMap]
      }
    }

    // The CAS backend only supports Mach-O object files, and isn't used with a
    // remote caching service.
    let usesRemoteService = pluginOptions.contains { $0.hasPrefix(remoteServiceOption) }
    let mccasDisabled = env["SWIFT_CACHE_DISABLE_MCCAS"] != nil ||
                        env["CLANG_CACHE_DISABLE_MCCAS"] != nil
    if !usesRemoteService && !mccasDisabled && isDarwinTarget(driverArgs) {
      cachingArgs += ["-Xfrontend", "-cas-backend",
                      "-Xllvm", "-cas-friendly-debug-info"]
    }

    // Insert before the end of options marker, if any.
    var result = args
    result.insert(contentsOf: cachingArgs, at: args.firstIndex(of: "--") ?? args.endIndex)
    return result
  }

  /// The default CAS of `clang-cache` (`llvm::cas::getDefaultOnDiskCASPath`).
  private static func defaultCASPath(env: ProcessEnvironmentBlock) -> AbsolutePath? {
    userCacheDirectory(env: env)?.appending(components: "llvm.cas.builtin.default", "cas")
  }

  /// The user cache directory, as determined by `llvm::sys::path::cache_directory`.
  private static func userCacheDirectory(env: ProcessEnvironmentBlock) -> AbsolutePath? {
    #if os(Windows)
    return env["LOCALAPPDATA"].flatMap { try? AbsolutePath(validating: $0) }
    #else
    #if canImport(Darwin)
    let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
    if length > 0 {
      var buffer = [CChar](repeating: 0, count: length)
      if confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length) == length,
         let path = try? AbsolutePath(validating: String(cString: buffer)) {
        return path
      }
    }
    #else
    if let cacheHome = env["XDG_CACHE_HOME"],
       let path = try? AbsolutePath(validating: cacheHome) {
      return path
    }
    #endif
    let home = env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
    return (try? AbsolutePath(validating: home))?.appending(component: ".cache")
    #endif
  }

  private static func isSameProgram(_ launcherPath: AbsolutePath,
                                    _ compilerPath: AbsolutePath) -> Bool {
    // Fast path for the toolchain layout, where `swift-cache` and `swiftc` are
    // adjacent links to (or, on Windows, copies of) `swift-driver`.
    if launcherPath.parentDirectory == compilerPath.parentDirectory {
      return true
    }
    guard let resolvedLauncherPath = try? resolveSymlinks(launcherPath),
          let resolvedCompilerPath = try? resolveSymlinks(compilerPath) else {
      return false
    }
    return resolvedLauncherPath == resolvedCompilerPath
  }

  private static func isDarwinTarget(_ driverArgs: ArraySlice<String>) -> Bool {
    // Driver errors are diagnosed when the driver parses the arguments again.
    if var parsedOptions = try? OptionTable().parse(Array(driverArgs), for: .batch,
                                                    delayThrows: true),
       let target = parsedOptions.getLastArgument(.target)?.asSingle {
      return Triple(target).isDarwin
    }
    #if canImport(Darwin)
    return true
    #else
    return false
    #endif
  }
}
