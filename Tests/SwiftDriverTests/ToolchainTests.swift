//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable @_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TSCBasic
import Testing
import TestUtilities
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#endif

@Suite struct ToolchainTests {

  private var ld: AbsolutePath { get throws { try makeLdStub() } }

  @Test func toolchainClangPath() throws {
    // Overriding the swift executable to a specific location breaks this.
    guard ProcessEnv.block["SWIFT_DRIVER_SWIFT_EXEC"] == nil,
          ProcessEnv.block["SWIFT_DRIVER_SWIFT_FRONTEND_EXEC"] == nil else {
      return
    }
    // TODO: remove this conditional check once DarwinToolchain does not requires xcrun to look for clang.
    var toolchain: Toolchain
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.block)
    #if os(macOS)
    toolchain = DarwinToolchain(env: ProcessEnv.block, executor: executor)
    #elseif os(Windows)
    toolchain = WindowsToolchain(env: ProcessEnv.block, executor: executor)
    #else
    toolchain = GenericUnixToolchain(env: ProcessEnv.block, executor: executor)
    #endif

    expectEqual(
      try? toolchain.getToolPath(.swiftCompiler).parentDirectory,
      try? toolchain.getToolPath(.clang).parentDirectory
    )
  }

  @Test func executableFallbackPath() throws {
    var env = ProcessEnv.block
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    let driver = try TestDriver(args: ["swift", "main.swift"], env: env)
    #expect(throws: Never.self) { try driver.toolchain.getToolPath(.dsymutil) }
  }

  @Test func swiftHelpOverride() async throws {
    // FIXME: On Linux, we might not have any Clang in the path. We need a
    // better override.
    var env = ProcessEnv.block
    let swiftHelp: AbsolutePath = try AbsolutePath(validating: "/usr/bin/nonexistent-swift-help")
    env["SWIFT_DRIVER_SWIFT_HELP_EXEC"] = swiftHelp.pathString
    env["SWIFT_DRIVER_CLANG_EXEC"] = "/usr/bin/clang"
    var driver = try TestDriver(
      args: ["swiftc", "-help"],
      env: env)
    let jobs = try await driver.planBuild()
    #expect(jobs.count == 1)
    expectEqual(jobs.first!.tool.name, swiftHelp.pathString)
  }

  @Test func swiftClangOverride() async throws {
    var env = ProcessEnv.block
    let swiftClang = try AbsolutePath(validating: "/A/Path/swift-clang")
    env["SWIFT_DRIVER_CLANG_EXEC"] = swiftClang.pathString

    var driver = try TestDriver(
      args: ["swiftc", "-emit-library", "foo.swift", "bar.o", "-o", "foo.l"],
      env: env)
    let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(jobs.count == 2)
    let linkJob = jobs[1]
    expectEqual(linkJob.tool.name, swiftClang.pathString)
  }

  @Test(.skipHostOS(.darwin, comment: "Darwin always uses `clang` to link")) func swiftClangxxOverride() async throws {
    var env = ProcessEnv.block
    let swiftClang = try AbsolutePath(validating: "/A/Path/swift-clang")
    let swiftClangxx = try AbsolutePath(validating: "/A/Path/swift-clang++")
    env["SWIFT_DRIVER_CLANG_EXEC"] = swiftClang.pathString
    env["SWIFT_DRIVER_CLANGXX_EXEC"] = swiftClangxx.pathString

    var driver = try TestDriver(
      args: ["swiftc", "-cxx-interoperability-mode=swift-6", "-emit-library",
             "foo.swift", "bar.o", "-o", "foo.l"],
      env: env)

    let jobs = try await driver.planBuild()
    let linkJob = jobs.last!
    expectEqual(linkJob.tool.name, swiftClangxx.pathString)
  }

  @Test func toolsDirectory() async throws {
    try await withTemporaryDirectory { tmpDir in
      let ld = tmpDir.appending(component: executableName("clang"))
      // tiny PE binary from: https://archive.is/w01DO
      let contents: ByteString = [
          0x4d, 0x5a, 0x00, 0x00, 0x50, 0x45, 0x00, 0x00, 0x4c, 0x01, 0x01, 0x00,
          0x6a, 0x2a, 0x58, 0xc3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x04, 0x00, 0x03, 0x01, 0x0b, 0x01, 0x08, 0x00, 0x04, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00,
          0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
          0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x68, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x02
      ]
      try localFileSystem.writeFileContents(ld, bytes: contents)
      try localFileSystem.chmod(.executable, path: try AbsolutePath(validating: ld.pathString))

      // Drop SWIFT_DRIVER_CLANG_EXEC from the environment so it doesn't
      // interfere with tool lookup.
      var env = ProcessEnv.block
      env.removeValue(forKey: "SWIFT_DRIVER_CLANG_EXEC")

      var driver = try TestDriver(args: ["swiftc",
                                     "-tools-directory", tmpDir.pathString,
                                     "foo.swift"],
                              env: env)
      let frontendJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      expectEqual(frontendJobs.count, 2)
      expectEqual(frontendJobs[1].kind, .link)
      expectEqual(frontendJobs[1].tool.absolutePath!.pathString, ld.pathString)

      // WASI toolchain
      do {
        var env = ProcessEnv.block
        env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "//bin/swift-autolink-extract"

        try await withTemporaryDirectory { resourceDir in
          try localFileSystem.writeFileContents(resourceDir.appending(components: "wasi", "static-executable-args.lnk")) {
            $0.send("garbage")
          }
          var driver = try TestDriver(args: ["swiftc",
                                         "-target", "wasm32-unknown-wasi",
                                         "-resource-dir", resourceDir.pathString,
                                         "-tools-directory", tmpDir.pathString,
                                         "foo.swift"],
                                  env: env)
          let frontendJobs = try await driver.planBuild().removingAutolinkExtractJobs()
          expectEqual(frontendJobs.count, 2)
          expectJobInvocationMatches(frontendJobs[1], .flag("-B"), .path(.absolute(tmpDir)))
        }
      }
    }
  }

  @Test func toolSearching() async throws {
#if os(Windows)
    let PATH = ProcessEnvironmentKey("Path")
#else
    let PATH = ProcessEnvironmentKey("PATH")
#endif
    let SWIFT_FRONTEND_EXEC = ProcessEnvironmentKey("SWIFT_DRIVER_SWIFT_FRONTEND_EXEC")
    let SWIFT_SCANNER_LIB = ProcessEnvironmentKey("SWIFT_DRIVER_SWIFTSCAN_LIB")
    var baseEnv = ProcessEnv.block
    baseEnv.removeValue(forKey: SWIFT_FRONTEND_EXEC)
    baseEnv.removeValue(forKey: SWIFT_SCANNER_LIB)
#if os(Windows)
    let separator = ";"
#else
    let separator = ":"
#endif

    var driver = try TestDriver(args: ["swiftc", "-print-target-info"], env: baseEnv)
    let jobs = try await driver.planBuild()
    #expect(jobs.count == 1)
    let defaultSwiftFrontend = jobs.first!.tool.absolutePath!

    try await withTemporaryDirectory { toolsDirectory in
      let customSwiftFrontend = toolsDirectory.appending(component: executableName("swift-frontend"))
      let customSwiftScan = toolsDirectory.appending(component: sharedLibraryName("_InternalSwiftScan"))
      try localFileSystem.createSymbolicLink(customSwiftFrontend, pointingAt: defaultSwiftFrontend, relative: false)

      try await withTemporaryDirectory { tempDirectory in
        let fs = TestLocalFileSystem(cwd: tempDirectory)
        let anotherSwiftFrontend = tempDirectory.appending(component: executableName("swift-frontend"))
        try fs.createSymbolicLink(anotherSwiftFrontend, pointingAt: defaultSwiftFrontend, relative: false)

        // test if SWIFT_DRIVER_TOOLNAME_EXEC is respected
        await #expect(throws: Never.self) {
          var env = baseEnv
          env[SWIFT_FRONTEND_EXEC] = customSwiftFrontend.pathString
          env[SWIFT_SCANNER_LIB] = customSwiftScan.pathString
          var driver = try TestDriver(args: ["swiftc", "-print-target-info"],
                                  env: env, fileSystem: fs)
          let jobs = try await driver.planBuild()
          #expect(jobs.count == 1)
          expectEqual(jobs.first!.tool.name, customSwiftFrontend.pathString)
        }

        // test if tools directory is respected
        await #expect(throws: Never.self) {
          var env = baseEnv
          env[SWIFT_SCANNER_LIB] = customSwiftScan.pathString
          var driver = try TestDriver(args: ["swiftc", "-print-target-info", "-tools-directory", toolsDirectory.pathString],
                                  env: env, fileSystem: fs)
          let jobs = try await driver.planBuild()
          #expect(jobs.count == 1)
          expectEqual(jobs.first!.tool.name, customSwiftFrontend.pathString)
        }

        // test if current working directory is searched before PATH
        await #expect(throws: Never.self) {
          var env = baseEnv
          env[PATH] = [toolsDirectory.pathString, ProcessEnv.path!].joined(separator: separator)
          env[SWIFT_SCANNER_LIB] = customSwiftScan.pathString
          var driver = try TestDriver(args: ["swiftc", "-print-target-info"],
                                  env: env, fileSystem: fs)
          let jobs = try await driver.planBuild()
          #expect(jobs.count == 1)
          expectEqual(jobs.first!.tool.name, anotherSwiftFrontend.pathString)
        }
      }
    }
  }

  @Test func registrarLookup() async throws {
#if os(Windows)
    let SDKROOT: AbsolutePath = localFileSystem.currentWorkingDirectory!.appending(components: "SDKROOT")
    let resourceDir: AbsolutePath = localFileSystem.currentWorkingDirectory!.appending(components: "swift", "resources")

    let platform: String = "windows"
#if arch(x86_64)
    let arch: String = "x86_64"
#elseif arch(arm64)
    let arch: String = "aarch64"
#else
#error("unsupported build architecture")
#endif

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj", "-resource-dir", resourceDir.nativePathString(escaped: false),
      ])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)
      let job = jobs.first!
      expectEqual(job.kind, .link)
      expectJobInvocationMatches(job, .path(.absolute(resourceDir.appending(components: platform, arch, "swiftrt.obj"))))
    }

    do {
      var driver = try TestDriver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj", "-sdk", SDKROOT.nativePathString(escaped: false),
      ])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)
      let job = jobs.first!
      expectEqual(job.kind, .link)
      expectJobInvocationMatches(job, .path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj"))))
    }

    do {
      var env = ProcessEnv.block
      env["SDKROOT"] = SDKROOT.nativePathString(escaped: false)

      var driver = try TestDriver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj"
      ], env: env)
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)
      let job = jobs.first!
      expectEqual(job.kind, .link)
      expectJobInvocationMatches(job, .path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj"))))
    }

    do {
      var env = ProcessEnv.block
      env["SDKROOT"] = SDKROOT.nativePathString(escaped: false)

      var driver = try TestDriver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj", "-static-stdlib",
      ], env: env)
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)
      let job = jobs.first!
      expectEqual(job.kind, .link)
      expectJobInvocationMatches(job, .path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrtT.obj"))))
      #expect(!job.commandLine.contains(.path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj")))))
    }

    do {
      var env = ProcessEnv.block
      env["SDKROOT"] = SDKROOT.nativePathString(escaped: false)

      var driver = try TestDriver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj", "-nostartfiles",
      ], env: env)
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)
      let job = jobs.first!
      expectEqual(job.kind, .link)
      #expect(!job.commandLine.contains(.path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj")))))
    }

    // Cannot test this due to `SDKROOT` escaping from the execution environment
    // into the `-print-target-info` step, which then resets the
    // `runtimeResourcePath` to be the SDK relative path rahter than the
    // toolchain relative path.
#if false
    do {
      var env = ProcessEnv.block
      env["SDKROOT"] = nil

      var driver = try TestDriver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj"
      ], env: env)
      driver.frontendTargetInfo.runtimeResourcePath = SDKROOT
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)
      let job = jobs.first!
      expectEqual(job.kind, .link)
      expectJobInvocationMatches(job, .path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj"))))
    }
#endif
#endif
  }

  @Test func findingBlockLists() throws {
    let execDir = try testInputsPath.appending(components: "Dummy.xctoolchain", "usr", "bin")
    let list = try Driver.findBlocklists(RelativeTo: execDir)
    expectEqual(list.count, 2)
    #expect(list.allSatisfy { $0.extension! == "yml" || $0.extension! == "yaml"})
  }

  @Test func findingBlockListVersion() throws {
    let execDir = try testInputsPath.appending(components: "Dummy.xctoolchain", "usr", "bin")
    let version = try Driver.findCompilerClientsConfigVersion(RelativeTo: execDir)
    expectEqual(version, "compilerClientsConfig-9999.99.9")
  }

  @Test func useStaticResourceDir() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      #expect(!job.commandLine.contains(.flag("-use-static-resource-dir")))
      expectEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift")
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-no-static-executable", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      #expect(!job.commandLine.contains(.flag("-use-static-resource-dir")))
      expectEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift")
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-no-static-stdlib", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      #expect(!job.commandLine.contains(.flag("-use-static-resource-dir")))
      expectEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift")
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-static-executable", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-use-static-resource-dir"))
      expectEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift_static")
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-static-stdlib", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-use-static-resource-dir"))
      expectEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift_static")
    }
  }

  @Test func relativeResourceDir() async throws {
    do {
      // Reset the environment to avoid 'SDKROOT' influencing the
      // linux driver paths and taking the priority over the resource directory.
      var env = ProcessEnv.block
      env["SDKROOT"] = nil
      var driver = try TestDriver(args: ["swiftc",
                                     "-target", "x86_64-unknown-linux", "-lto=llvm-thin",
                                     "foo.swift",
                                     "-resource-dir", "resource/dir"], env: env)
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      let compileJob = plannedJobs[0]
      expectEqual(compileJob.kind, .compile)
      try expectJobInvocationMatches(compileJob, .flag("-resource-dir"), toPathOption("resource/dir"))

      let linkJob = plannedJobs[1]
      #expect(linkJob.kind == .link)
      try expectJobInvocationMatches(linkJob, .flag("-Xlinker"), .flag("-rpath"), .flag("-Xlinker"), toPathOption("resource/dir/linux"))
      try expectJobInvocationMatches(linkJob, toPathOption("resource/dir/linux/x86_64/swiftrt.o"))
      try expectJobInvocationMatches(linkJob, .flag("-L"), toPathOption("resource/dir/linux"))
    }
  }

  @Test func sdkDirLinuxPrioritizedOverRelativeResourceDirForLinkingSwiftRT() async throws {
    do {
      let sdkRoot = try testInputsPath.appending(component: "mock-sdk.sdk")
      var env = ProcessEnv.block
      env["SDKROOT"] = sdkRoot.pathString
      var driver = try TestDriver(args: ["swiftc",
                                     "-target", "x86_64-unknown-linux", "-lto=llvm-thin",
                                     "foo.swift",
                                     "-resource-dir", "resource/dir"], env: env)
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let compileJob = plannedJobs[0]
      expectEqual(compileJob.kind, .compile)
      let linkJob = plannedJobs[1]
      #expect(linkJob.kind == .link)
      try expectJobInvocationMatches(linkJob, toPathOption(sdkRoot.pathString + "/usr/lib/swift/linux/x86_64/swiftrt.o", isRelative: false))
    }
  }

  @Test func frontendTargetInfoWithWorkingDirectory() async throws {
    do {
      let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "absolute", "path")

      var driver = try TestDriver(args: ["swiftc", "-typecheck", "foo.swift",
                                     "-resource-dir", "resource/dir",
                                     "-sdk", "sdk",
                                     "-working-directory", workingDirectory.pathString])
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      try expectJobInvocationMatches(job, .path(VirtualPath(path: rebase("resource", "dir", at: workingDirectory))))
      #expect(!job.commandLine.contains(.path(.relative(try .init(validating: "resource/dir")))))
      expectJobInvocationMatches(job, .path(try VirtualPath(path: rebase("sdk", at: workingDirectory))))
      #expect(!job.commandLine.contains(.path(.relative(try .init(validating: "sdk")))))
    }
  }

  @Test func pluginPaths() async throws {
    try await pluginPathTest(platform: "iPhoneOS", sdk: "iPhoneOS13.0", searchPlatform: "iPhoneOS")
    try await pluginPathTest(platform: "iPhoneSimulator", sdk: "iPhoneSimulator15.0", searchPlatform: "iPhoneOS")
  }

  func pluginPathTest(platform: String, sdk: String, searchPlatform: String) async throws {
    let sdkRoot = try testInputsPath.appending(
      components: ["Platform Checks", "\(platform).platform", "Developer", "SDKs", "\(sdk).sdk"])

    var env = ProcessEnv.block
    env["PLATFORM_DIR"] = "/tmp/PlatformDir/\(platform).platform"

    let workingDirectory = try AbsolutePath(validating: "/tmp")

    var driver = try TestDriver(
      args: ["swiftc", "-typecheck", "foo.swift", "-sdk", VirtualPath.absolute(sdkRoot).name, "-plugin-path", "PluginA", "-external-plugin-path", "Plugin~B#Bexe", "-load-plugin-library", "PluginB2", "-plugin-path", "PluginC", "-working-directory", workingDirectory.nativePathString(escaped: false)],
      env: env
    )
    guard driver.isFrontendArgSupported(.pluginPath) && driver.isFrontendArgSupported(.externalPluginPath) else {
      return
    }

    let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(jobs.count == 1)
    let job = jobs.first!

    // Check that the we have the plugin paths we expect, in the order we expect.
    let pluginAIndex = try #require(job.commandLine.firstIndex(of: .path(VirtualPath.absolute(workingDirectory.appending(component: "PluginA")))))

    let pluginBIndex = try #require(job.commandLine.firstIndex(of: .path(VirtualPath.absolute(workingDirectory.appending(component: "Plugin~B#Bexe")))))
    #expect(pluginAIndex < pluginBIndex)

    let pluginB2Index = try #require(job.commandLine.firstIndex(of: .path(VirtualPath.absolute(workingDirectory.appending(component: "PluginB2")))))
    #expect(pluginBIndex < pluginB2Index)

    let pluginCIndex = try #require(job.commandLine.firstIndex(of: .path(VirtualPath.absolute(workingDirectory.appending(component: "PluginC")))))
    #expect(pluginB2Index < pluginCIndex)

    #if os(macOS)
    let origPlatformPath =
      sdkRoot.parentDirectory.parentDirectory.parentDirectory.parentDirectory
        .appending(component: "\(searchPlatform).platform")

    let platformPath = origPlatformPath.appending(components: "Developer", "usr")
    let platformServerPath = platformPath.appending(components: "bin", "swift-plugin-server").pathString

    let platformPluginPath = platformPath.appending(components: "lib", "swift", "host", "plugins")
    let platformPluginPathIndex = try #require(job.commandLine.firstIndex(of: .flag("\(platformPluginPath)#\(platformServerPath)")))

    let platformLocalPluginPath = platformPath.appending(components: "local", "lib", "swift", "host", "plugins")
    let platformLocalPluginPathIndex = try #require(job.commandLine.firstIndex(of: .flag("\(platformLocalPluginPath)#\(platformServerPath)")))
    #expect(platformPluginPathIndex < platformLocalPluginPathIndex)

    // Plugin paths that come from the PLATFORM_DIR environment variable.
    let envOrigPlatformPath = try AbsolutePath(validating: "/tmp/PlatformDir/\(searchPlatform).platform")
    let envPlatformPath = envOrigPlatformPath.appending(components: "Developer", "usr")
    let envPlatformServerPath = envPlatformPath.appending(components: "bin", "swift-plugin-server").pathString
    let envPlatformPluginPath = envPlatformPath.appending(components: "lib", "swift", "host", "plugins")
    let envPlatformPluginPathIndex = try #require(job.commandLine.firstIndex(of: .flag("\(envPlatformPluginPath)#\(envPlatformServerPath)")))
    #expect(envPlatformPluginPathIndex < platformPluginPathIndex)

    let toolchainPluginPathIndex = try #require(job.commandLine.firstIndex(of: .path(.absolute(try driver.toolchain.executableDir.parentDirectory.appending(components: "lib", "swift", "host", "plugins")))))

    let toolchainStdlibPath = VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path)
      .appending(components: driver.frontendTargetInfo.target.triple.platformName() ?? "", "Swift.swiftmodule")
    let hasToolchainStdlib = try driver.fileSystem.exists(toolchainStdlibPath)
    if hasToolchainStdlib {
      #expect(platformLocalPluginPathIndex > toolchainPluginPathIndex)
    } else {
      #expect(platformLocalPluginPathIndex < toolchainPluginPathIndex)
    }
    #endif

#if os(Windows)
    try expectJobInvocationMatches(job, .flag("-plugin-path"), .path(.absolute(driver.toolchain.executableDir.parentDirectory.appending(components: "bin"))))
#else
    try expectJobInvocationMatches(job, .flag("-plugin-path"), .path(.absolute(driver.toolchain.executableDir.parentDirectory.appending(components: "lib", "swift", "host", "plugins"))))
    try expectJobInvocationMatches(job, .flag("-plugin-path"), .path(.absolute(driver.toolchain.executableDir.parentDirectory.appending(components: "local", "lib", "swift", "host", "plugins"))))
#endif
  }

  @Test func workingDirectoryForImplicitOutputs() async throws {
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "Foo", "Bar")

    var driver = try TestDriver(args: [
      "swiftc", "-working-directory", workingDirectory.pathString, "-emit-executable", "-c", "/tmp/main.swift"
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

    #expect(plannedJobs.count == 1)
    try expectJobInvocationMatches(plannedJobs[0], .flag("-o"), .path(VirtualPath(path: rebase("main.o", at: workingDirectory))))
  }

  @Test func workingDirectoryForImplicitModules() async throws {
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "Foo", "Bar")

    var driver = try TestDriver(args: [
      "swiftc", "-working-directory", workingDirectory.pathString, "-emit-module", "/tmp/main.swift"
    ])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

    #expect(plannedJobs.count == 2)
    try expectJobInvocationMatches(plannedJobs[0], .flag("-o"), .path(VirtualPath(path: rebase("main.swiftmodule", at: workingDirectory))))
    try expectJobInvocationMatches(plannedJobs[0], .flag("-emit-module-doc-path"), .path(VirtualPath(path: rebase("main.swiftdoc", at: workingDirectory))))
    try expectJobInvocationMatches(plannedJobs[0], .flag("-emit-module-source-info-path"), .path(VirtualPath(path: rebase("main.swiftsourceinfo", at: workingDirectory))))
  }
}
