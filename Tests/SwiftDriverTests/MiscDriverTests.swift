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

@Suite struct MiscDriverTests {

  private var ld: AbsolutePath { get throws { try makeLdStub() } }

  @Test func moduleAliasingWithImplicitBuild() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Car=Bar",
      "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule",
    ])

    let plannedJobs = try await driver.planBuild()

    let moduleJob = try plannedJobs.findJob(.emitModule)
    expectJobInvocationMatches(moduleJob, .flag("-module-alias"), .flag("Car=Bar"))
    try expectEqual(moduleJob.outputs[0].file, .absolute(try .init(validating: "/tmp/dir/Foo.swiftmodule")))
    #expect(driver.moduleOutputInfo.name == "Foo")
    #expect(driver.moduleOutputInfo.aliases != nil)
    expectEqual(driver.moduleOutputInfo.aliases!.count, 1)
    expectEqual(driver.moduleOutputInfo.aliases!["Car"], "Bar")
  }

  @Test func invalidModuleAliasing() async throws {
    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "CarBar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("invalid format \"CarBar\"; use the format '-module-alias alias_name=underlying_name'"))
    }

    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Foo=Bar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("module alias \"Foo\" should be different from the module name \"Foo\""))
    }

    // A module alias is allowed to be a valid raw identifier, not just a regular Swift identifier.
    try await assertNoDriverDiagnostics(
      args: "swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "//car/far:par=Bar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"
    )
    // The alias target (an actual module name), however, may not be a raw identifier.
    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Bar=C-ar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("module name \"C-ar\" is not a valid identifier"))
    }
    // We should still diagnose names that are not valid raw identifiers.
    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "C`ar=Bar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("module name \"C`ar\" is not a valid identifier"))
    }

    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Car=Bar", "-module-alias", "Train=Car", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("the name \"Car\" is already used for a module alias or an underlying name"))
    }

    try await assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Car=Bar", "-module-alias", "Car=Bus", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("the name \"Car\" is already used for a module alias or an underlying name"))
    }
  }

  @Test func privateInterfacePathImplicit() async throws {
    var driver1 = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                   "foo", "-emit-module-interface",
                                   "-enable-library-evolution"])

    let plannedJobs = try await driver1.planBuild()
    #expect(plannedJobs.count == 3)

    let emitInterfaceJob = try plannedJobs.findJob(.emitModule)
    expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-module-interface-path"))
    expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-private-module-interface-path"))
  }

  @Test func packageInterfacePathImplicit() async throws {
    let envVars = ProcessEnv.block

    // A .package.swiftinterface should only be generated if package-name is passed.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name", "foo",
                                     "-package-name", "mypkg", "-library-level", "api",
                                     "-emit-module-interface", "-enable-library-evolution"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      let emitInterfaceJob = plannedJobs[0]
      expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-module-interface-path"))
      expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-private-module-interface-path"))
      expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-package-module-interface-path"))
    }

    // package-name is not passed, so package interface should not be generated.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name", "foo", "-library-level", "api",
                                     "-emit-module-interface", "-enable-library-evolution"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      let emitInterfaceJob = plannedJobs[0]
      expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-module-interface-path"))
      expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-private-module-interface-path"))
      #expect(!emitInterfaceJob.commandLine.contains(.flag("-emit-package-module-interface-path")))
    }

    // package-name is not passed, so specifying emit-package-module-interface-path should be a no-op.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name", "foo",
                                     "-emit-module-interface", "-library-level", "api",
                                     "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                     "-enable-library-evolution"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      let emitInterfaceJob = plannedJobs[0]
      expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-module-interface-path"))
      expectJobInvocationMatches(emitInterfaceJob, .flag("-emit-private-module-interface-path"))
      #expect(!emitInterfaceJob.commandLine.contains(.flag("-emit-package-module-interface-path")))
    }
  }

  @Test func profileArgValidation() async throws {
    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-profile-generate", "-profile-use=profile.profdata"]) {
      $1.expect(.error(Driver.Error.conflictingOptions(.profileGenerate, .profileUse)))
      $1.expect(.error(Driver.Error.missingProfilingData(try toPath("profile.profdata").name)))
    }

    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-profile-sample-use=profile1.profdata", "-profile-use=profile2.profdata"]) {
      $1.expect(.error(Driver.Error.conflictingOptions(.profileUse, .profileSampleUse)))
      $1.expect(.error(Driver.Error.missingProfilingData(try toPath("profile1.profdata").name)))
      $1.expect(.error(Driver.Error.missingProfilingData(try toPath("profile2.profdata").name)))
    }

    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-profile-use=profile.profdata"]) {
      $1.expect(.error(Driver.Error.missingProfilingData(try toPath("profile.profdata").name)))
    }

    try await withTemporaryDirectory { path in
      try localFileSystem.writeFileContents(path.appending(component: "profile.profdata"), bytes: .init())
      try await assertNoDriverDiagnostics(args: "swiftc", "-working-directory", path.pathString, "foo.swift", "-profile-use=profile.profdata")
      try await assertNoDriverDiagnostics(args: "swiftc", "-working-directory", path.pathString, "foo.swift", "-profile-sample-use=profile.profdata")
    }

    try await withTemporaryDirectory { path in
      try localFileSystem.writeFileContents(path.appending(component: "profile.profdata"), bytes: .init())
      try await assertDriverDiagnostics(args: ["swiftc", "-working-directory", path.pathString, "foo.swift",
                                         "-profile-use=profile.profdata,profile2.profdata"]) {
        $1.expect(.error(Driver.Error.missingProfilingData(path.appending(component: "profile2.profdata").pathString)))
      }
      // -profile-sample-use does not accept more than one path, so commas are not split.
      try await assertDriverDiagnostics(args: ["swiftc", "-working-directory", path.pathString, "foo.swift",
                                         "-profile-sample-use=profile.profdata,profile2.profdata"]) {
        $1.expect(.error(Driver.Error.missingProfilingData(path.appending(component: "profile.profdata,profile2.profdata").pathString)))
      }
    }
  }

  @Test func profileSampleUseFrontendFlags() async throws {
    // Check that the LLVM option for 'profi' is inferred and passed to frontend
    // in addition to the usual flag.
    try await withTemporaryDirectory { path in
      let completePath: AbsolutePath = path.appending(component: "profile.profdata")

      try localFileSystem.writeFileContents(completePath, bytes: .init())
      var driver = try TestDriver(args: ["swiftc", "foo.swift",
        "-working-directory", path.pathString,
        "-profile-sample-use=profile.profdata"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      let job: Job = plannedJobs[0]
      let command: [Job.ArgTemplate] = job.commandLine

      #expect(command.contains(
        .joinedOptionAndPath("-profile-sample-use=", .absolute(completePath))))

      // assuming it's preceded by -Xllvm, or else it wouldn't work anyway.
      #expect(command.contains(.flag("-sample-profile-use-profi")))
    }
  }

  @Test func debugInfoForProfilingFlag() async throws {
    // Check that the '-debug-info-for-profiling' flag is passed to frontend.
    var driver = try TestDriver(args: ["swiftc", "-g", "-debug-info-for-profiling", "foo.swift"])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
    #expect(plannedJobs.count == 4)
    #expect(plannedJobs[0].kind == .emitModule)
    let job = plannedJobs[0]
    #expect(job.commandLine.contains(.flag("-debug-info-for-profiling")))
  }

  @Test func profileLinkerArgs() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", "x86_64-apple-macosx10.9", "test.swift"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", "x86_64-apple-ios7.1-simulator", "test.swift"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", "arm64-apple-ios7.1", "test.swift"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", "x86_64-apple-tvos9.0-simulator", "test.swift"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", "arm64-apple-tvos9.0", "test.swift"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", "i386-apple-watchos2.0-simulator", "test.swift"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", "armv7k-apple-watchos2.0", "test.swift"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      #expect(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    // FIXME: This will fail when run on macOS, because
    // swift-autolink-extract is not present
    #if os(Linux) || os(Android) || os(Windows)
    for triple in ["aarch64-unknown-linux-android", "x86_64-unknown-linux-gnu"] {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-target", triple, "test.swift"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)
      if triple == "aarch64-unknown-linux-android" {
        #expect(plannedJobs[1].commandLine.containsPathWithBasename("libclang_rt.profile-aarch64-android.a"))
      } else {
        #expect(plannedJobs[1].commandLine.containsPathWithBasename("libclang_rt.profile-x86_64.a"))
      }
      #expect(plannedJobs[1].commandLine.contains { $0 == .flag("-u__llvm_profile_runtime") })
    }
    #endif

    // -profile-generate should add libclang_rt.profile for WebAssembly targets
    try await withTemporaryDirectory { resourceDir in
      try localFileSystem.writeFileContents(resourceDir.appending(components: "wasi", "static-executable-args.lnk")) {
        $0.send("garbage")
      }

      var env = ProcessEnv.block
      env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "//bin/swift-autolink-extract"

      for triple in ["wasm32-unknown-wasi", "wasm32-unknown-wasip1-threads"] {
        var driver = try TestDriver(args: [
          "swiftc", "-profile-generate", "-target", triple, "test.swift",
          "-resource-dir", resourceDir.pathString
        ], env: env)
        let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

        #expect(plannedJobs.count == 2)
        #expect(plannedJobs[0].kind == .compile)

        #expect(plannedJobs[1].kind == .link)
        #expect(plannedJobs[1].commandLine.containsPathWithBasename("libclang_rt.profile-wasm32.a"))
      }
    }

    for explicitUseLd in [true, false] {
      var args = ["swiftc", "-profile-generate", "-target", "x86_64-unknown-windows-msvc", "test.swift"]
      if explicitUseLd {
        // Explicitly passing '-use-ld=lld' should still result in '-lld-allow-duplicate-weak'.
        args.append("-use-ld=lld")
      }
      var driver = try TestDriver(args: args)
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)

      let linkCmds = plannedJobs[1].commandLine

      // rdar://131295678 - Make sure we force the use of lld and pass
      // '-lld-allow-duplicate-weak'.
      #expect(linkCmds.contains(.flag("-fuse-ld=lld")))
      #expect(linkCmds.contains([.flag("-Xlinker"), .flag("-lld-allow-duplicate-weak")]))
    }

    // rdar://131295678 - Make sure we force the use of lld and pass
    // '-lld-allow-duplicate-weak' even if the user requests something else.
    do {
      var driver = try TestDriver(args: ["swiftc", "-profile-generate", "-use-ld=link", "-target", "x86_64-unknown-windows-msvc", "test.swift"])
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)

      let linkCmds = plannedJobs[1].commandLine

      #expect(!linkCmds.contains(.flag("-fuse-ld=link")))
      #expect(linkCmds.contains(.flag("-fuse-ld=lld")))
      #expect(linkCmds.contains(.flag("-lld-allow-duplicate-weak")))
    }

    do {
      // If we're not building for profiling, don't add '-lld-allow-duplicate-weak'.
      var driver = try TestDriver(args: ["swiftc", "-use-ld=lld", "-target", "x86_64-unknown-windows-msvc", "test.swift"])
      let plannedJobs = try await driver.planBuild()

      #expect(plannedJobs.count == 2)
      #expect(plannedJobs[0].kind == .compile)

      #expect(plannedJobs[1].kind == .link)

      let linkCmds = plannedJobs[1].commandLine
      #expect(linkCmds.contains(.flag("-fuse-ld=lld")))
      #expect(!linkCmds.contains(.flag("-lld-allow-duplicate-weak")))
    }
  }

  @Test func conditionalCompilationArgValidation() async throws {
    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-DFOO=BAR"]) {
      $1.expect(.warning("conditional compilation flags do not have values in Swift; they are either present or absent (rather than 'FOO=BAR')"))
    }

    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-D-DFOO"]) {
      $1.expect(.error(Driver.Error.conditionalCompilationFlagHasRedundantPrefix("-DFOO")))
    }

    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-Dnot-an-identifier"]) {
      $1.expect(.error(Driver.Error.conditionalCompilationFlagIsNotValidIdentifier("not-an-identifier")))
    }

    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-DFOO")
  }

  @Test func frameworkSearchPathArgValidation() async throws {
    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-F/some/dir/xyz.framework"]) {
      $1.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
    }

    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-F/some/dir/xyz.framework/"]) {
      $1.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
    }

    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-Fsystem", "/some/dir/xyz.framework"]) {
      $1.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
    }

   try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-Fsystem", "/some/dir/")
  }

  @Test func multipleValidationFailures() async throws {
    try await assertDiagnostics { engine, verifier in
      verifier.expect(.error(Driver.Error.conditionalCompilationFlagIsNotValidIdentifier("not-an-identifier")))
      verifier.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
      _ = try TestDriver(args: ["swiftc", "foo.swift", "-Dnot-an-identifier", "-F/some/dir/xyz.framework"], diagnosticsEngine: engine)
    }
  }

  @Test func dotFileEmission() async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-emit-executable", "test.swift", "-emit-module", "-avoid-emit-module-source-info", "-experimental-emit-module-separately", "-working-directory", localFileSystem.currentWorkingDirectory!.description
    ])
    let plannedJobs = try await driver.planBuild()

    // Extract actual temp file names from planned jobs (counter-independent).
    let compileJob = try #require(plannedJobs.first { $0.kind == .compile })
    let objName = compileJob.outputs[0].file.basename
    let autolinkJob = plannedJobs.first { $0.kind == .autolinkExtract }
    let autolinkName = autolinkJob?.outputs[0].file.basename

    var serializer = DOTJobGraphSerializer(jobs: plannedJobs)
    var output = ""
    serializer.writeDOT(to: &output)

    let linkerDriver = executableName("clang")
    if driver.targetTriple.objectFormat == .elf {
        let autolinkName = try #require(autolinkName)
        expectEqual(output,
        """
        digraph Jobs {
          "emitModule (\(executableName("swift-frontend")))" [style=bold];
          "\(rebase("test.swift"))" [fontsize=12];
          "\(rebase("test.swift"))" -> "emitModule (\(executableName("swift-frontend")))" [color=blue];
          "\(rebase("test.swiftmodule"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftmodule"))" [color=green];
          "\(rebase("test.swiftdoc"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftdoc"))" [color=green];
          "compile (\(executableName("swift-frontend")))" [style=bold];
          "\(rebase("test.swift"))" -> "compile (\(executableName("swift-frontend")))" [color=blue];
          "\(objName)" [fontsize=12];
          "compile (\(executableName("swift-frontend")))" -> "\(objName)" [color=green];
          "autolinkExtract (\(executableName("swift-autolink-extract")))" [style=bold];
          "\(objName)" -> "autolinkExtract (\(executableName("swift-autolink-extract")))" [color=blue];
          "\(autolinkName)" [fontsize=12];
          "autolinkExtract (\(executableName("swift-autolink-extract")))" -> "\(autolinkName)" [color=green];
          "link (\(executableName("clang")))" [style=bold];
          "\(objName)" -> "link (\(executableName("clang")))" [color=blue];
          "\(autolinkName)" -> "link (\(executableName("clang")))" [color=blue];
          "\(rebase(executableName("test")))" [fontsize=12];
          "link (\(linkerDriver))" -> "\(rebase(executableName("test")))" [color=green];
        }

        """)
    } else if driver.targetTriple.objectFormat == .macho {
        expectEqual(output,
        """
        digraph Jobs {
          "emitModule (\(executableName("swift-frontend")))" [style=bold];
          "\(rebase("test.swift"))" [fontsize=12];
          "\(rebase("test.swift"))" -> "emitModule (\(executableName("swift-frontend")))" [color=blue];
          "\(rebase("test.swiftmodule"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftmodule"))" [color=green];
          "\(rebase("test.swiftdoc"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftdoc"))" [color=green];
          "\(rebase("test.abi.json"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.abi.json"))" [color=green];
          "compile (\(executableName("swift-frontend")))" [style=bold];
          "\(rebase("test.swift"))" -> "compile (\(executableName("swift-frontend")))" [color=blue];
          "\(objName)" [fontsize=12];
          "compile (\(executableName("swift-frontend")))" -> "\(objName)" [color=green];
          "link (\(linkerDriver))" [style=bold];
          "\(objName)" -> "link (\(linkerDriver))" [color=blue];
          "\(rebase(executableName("test")))" [fontsize=12];
          "link (\(linkerDriver))" -> "\(rebase(executableName("test")))" [color=green];
        }

        """)
    } else {
      expectEqual(output,
      """
      digraph Jobs {
        "emitModule (\(executableName("swift-frontend")))" [style=bold];
        "\(rebase("test.swift"))" [fontsize=12];
        "\(rebase("test.swift"))" -> "emitModule (\(executableName("swift-frontend")))" [color=blue];
        "\(rebase("test.swiftmodule"))" [fontsize=12];
        "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftmodule"))" [color=green];
        "\(rebase("test.swiftdoc"))" [fontsize=12];
        "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftdoc"))" [color=green];
        "compile (\(executableName("swift-frontend")))" [style=bold];
        "\(rebase("test.swift"))" -> "compile (\(executableName("swift-frontend")))" [color=blue];
        "\(objName)" [fontsize=12];
        "compile (\(executableName("swift-frontend")))" -> "\(objName)" [color=green];
        "link (\(linkerDriver))" [style=bold];
        "\(objName)" -> "link (\(linkerDriver))" [color=blue];
        "\(rebase(executableName("test")))" [fontsize=12];
        "link (\(linkerDriver))" -> "\(rebase(executableName("test")))" [color=green];
      }

      """)
    }
  }

  @Test func regressions() async throws {
    var driverWithEmptySDK = try TestDriver(args: ["swiftc", "-sdk", "", "file.swift"])
    _ = try await driverWithEmptySDK.planBuild()

    var driver = try TestDriver(args: ["swiftc", "foo.swift", "-sdk", "/"])
    let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

    try expectJobInvocationMatches(plannedJobs[0], .flag("-sdk"), .path(.absolute(.init(validating: "/"))))

    if !driver.targetTriple.isDarwin {
      #expect(!plannedJobs[1].commandLine.contains(subsequence: ["-L", .path(.absolute(try .init(validating: "/usr/lib/swift")))]))
    }
  }

  @Test func diagnosticOptions() async throws {
    do {
      var driver = try TestDriver(args: ["swift", "-no-warnings-as-errors", "-warnings-as-errors", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-no-warnings-as-errors"), .flag("-warnings-as-errors"))
    }

    do {
      var driver = try TestDriver(args: ["swift", "-warnings-as-errors", "-no-warnings-as-errors", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-warnings-as-errors"), .flag("-no-warnings-as-errors"))
    }

    do {
      var driver = try TestDriver(args: ["swift", "-warnings-as-errors", "-no-warnings-as-errors", "-suppress-warnings", "-suppress-remarks", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-warnings-as-errors"), .flag("-no-warnings-as-errors"))
      expectJobInvocationMatches(job, .flag("-suppress-warnings"))
      expectJobInvocationMatches(job, .flag("-suppress-remarks"))
    }

    do {
      var driver = try TestDriver(args: [
        "swift",
        "-warnings-as-errors",
        "-no-warnings-as-errors",
        "-Werror", "A",
        "-Wwarning", "B",
        "-Werror", "C",
        "-Wwarning", "C",
        "foo.swift",
      ])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-warnings-as-errors"), .flag("-no-warnings-as-errors"), .flag("-Werror"), .flag("A"), .flag("-Wwarning"), .flag("B"), .flag("-Werror"), .flag("C"), .flag("-Wwarning"), .flag("C"))
    }

    do {
      try await assertDriverDiagnostics(args: ["swift", "-no-warnings-as-errors", "-warnings-as-errors", "-suppress-warnings", "foo.swift"]) {
        $1.expect(.error(Driver.Error.conflictingOptions(.warningsAsErrors, .suppressWarnings)))
      }
    }

    do {
      try await assertDriverDiagnostics(args: ["swift", "-Wwarning", "test", "-suppress-warnings", "foo.swift"]) {
        $1.expect(.error(Driver.Error.conflictingOptions(.Wwarning, .suppressWarnings)))
      }
    }

    do {
      try await assertDriverDiagnostics(args: ["swift", "-Werror", "test", "-suppress-warnings", "foo.swift"]) {
        $1.expect(.error(Driver.Error.conflictingOptions(.Werror, .suppressWarnings)))
      }
    }

    do {
      var driver = try TestDriver(args: ["swift", "-print-educational-notes", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      expectJobInvocationMatches(plannedJobs[0], .flag("-print-educational-notes"))
    }

    do {
      var driver = try TestDriver(args: ["swift", "-debug-diagnostic-names", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      expectJobInvocationMatches(plannedJobs[0], .flag("-debug-diagnostic-names"))
    }

    do {
      var driver = try TestDriver(args: ["swift", "-print-diagnostic-groups", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      expectJobInvocationMatches(plannedJobs[0], .flag("-print-diagnostic-groups"))
    }
  }

  @Test func numThreads() async throws {
    try expectEqual(try TestDriver(args: ["swiftc"]).numThreads, 0)

    try expectEqual(try TestDriver(args: ["swiftc", "-num-threads", "4"]).numThreads, 4)

    try expectEqual(try TestDriver(args: ["swiftc", "-num-threads", "0"]).numThreads, 0)

    try await assertDriverDiagnostics(args: ["swift", "-num-threads", "-1"]) { driver, verify in
      verify.expect(.error("invalid value '-1' in '-num-threads'"))
      expectEqual(driver.numThreads, 0)
    }

    try await assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-num-threads", "4") { driver, verify in
      verify.expect(.warning("ignoring -num-threads argument; cannot multithread batch mode"))
      expectEqual(driver.numThreads, 0)
    }
  }

  @Test func deterministicCheck() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-enable-deterministic-check", "foo.swift",
                                     "-import-objc-header", "foo.h", "-enable-bridging-pch"])
      let plannedJobs = try await driver.planBuild()
      // Check bridging header compilation command and main module command.
      expectJobInvocationMatches(plannedJobs[0], .flag("-enable-deterministic-check"), .flag("-always-compile-output-files"))
      expectJobInvocationMatches(plannedJobs[1], .flag("-enable-deterministic-check"), .flag("-always-compile-output-files"))
    }
  }

  @Test func warnConcurrency() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-warn-concurrency", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      expectJobInvocationMatches(plannedJobs[0], .flag("-warn-concurrency"))
    }
  }

  @Test func libraryLevel() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-library-level", "spi", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      expectJobInvocationMatches(plannedJobs[0], .flag("-library-level"), .flag("spi"))
    }
  }

  @Test func prebuiltModuleCacheFlags() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    let mockSDKPath: String =
        try testInputsPath.appending(component: "mock-sdk.sdk").nativePathString(escaped: false)

    do {
      let resourceDirPath: String = try testInputsPath.appending(components: "PrebuiltModules-macOS10.15.xctoolchain", "usr", "lib", "swift").nativePathString(escaped: false)

      var driver = try TestDriver(args: ["swiftc", "-target", "x86_64-apple-ios13.1-macabi", "foo.swift", "-sdk", mockSDKPath, "-resource-dir", resourceDirPath],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-prebuilt-module-cache-path"))
      #expect(job.commandLine.contains { arg in
        if case .path(let curPath) = arg {
          if curPath.basename == "10.15" && curPath.parentDirectory.basename == "prebuilt-modules" && curPath.parentDirectory.parentDirectory.basename == "macosx" {
              return true
          }
        }
        return false
      })
    }

    do {
      let resourceDirPath: String = try testInputsPath.appending(components: "PrebuiltModules-macOSUnversioned.xctoolchain", "usr", "lib", "swift").nativePathString(escaped: false)

      var driver = try TestDriver(args: ["swiftc", "-target", "x86_64-apple-ios13.1-macabi", "foo.swift", "-sdk", mockSDKPath, "-resource-dir", resourceDirPath],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-prebuilt-module-cache-path"))
      #expect(job.commandLine.contains { arg in
        if case .path(let curPath) = arg {
          if curPath.basename == "prebuilt-modules" && curPath.parentDirectory.basename == "macosx" {
              return true
          }
        }
        return false
      })
    }
  }

  @Test func relativeInputs() async throws {
    do {
      // Inputs with relative paths with no -working-directory flag should remain relative
      var driver = try TestDriver(args: ["swiftc",
                                     "-target", "arm64-apple-ios13.1",
                                     "-resource-dir", "relresourcepath",
                                     "-sdk", "relsdkpath",
                                     "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let compileJob = plannedJobs[0]
      expectEqual(compileJob.kind, .compile)
      try expectJobInvocationMatches(compileJob, .flag("-primary-file"), toPathOption("foo.swift", isRelative: true))
      try expectJobInvocationMatches(compileJob, .flag("-resource-dir"), toPathOption("relresourcepath", isRelative: true))
      try expectJobInvocationMatches(compileJob, .flag("-sdk"), toPathOption("relsdkpath", isRelative: true))
    }

    do {
      let workingDirectory = try AbsolutePath(validating: "/foo/bar")

      // Inputs with relative paths with -working-directory flag should prefix all inputs
      var driver = try TestDriver(args: ["swiftc",
                                     "-target", "arm64-apple-ios13.1",
                                     "-resource-dir", "relresourcepath",
                                     "-sdk", "relsdkpath",
                                     "foo.swift",
                                     "-working-directory", workingDirectory.nativePathString(escaped: false)])
      let plannedJobs = try await driver.planBuild()
      let compileJob = plannedJobs[0]
      expectEqual(compileJob.kind, .compile)
      expectJobInvocationMatches(compileJob, .flag("-primary-file"), .path(.absolute(workingDirectory.appending(component: "foo.swift"))))
      expectJobInvocationMatches(compileJob, .flag("-resource-dir"), .path(.absolute(workingDirectory.appending(component: "relresourcepath"))))
      expectJobInvocationMatches(compileJob, .flag("-sdk"), .path(.absolute(workingDirectory.appending(component: "relsdkpath"))))
    }

    try await withTemporaryDirectory { dir in
      let fileMapFile = dir.appending(component: "file-map-file")
      let outputMapContents: ByteString = """
      {
        "": {
          "diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.dia",
          "emit-module-diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.dia"
        },
        "foo.swift": {
          "object": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.o"
        }
      }
      """
      try localFileSystem.writeFileContents(fileMapFile, bytes: outputMapContents)

      // Inputs with relative paths should be found in output file maps
      var driver = try TestDriver(args: ["swiftc",
                                     "-target", "arm64-apple-ios13.1",
                                     "foo.swift",
                                     "-output-file-map", fileMapFile.description])
      let plannedJobs = try await driver.planBuild()
      let compileJob = plannedJobs[0]
      expectEqual(compileJob.kind, .compile)
      try expectJobInvocationMatches(compileJob, .flag("-o"), .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.o"))))
    }

    try await withTemporaryDirectory { dir in
      let fileMapFile = dir.appending(component: "file-map-file")
      let outputMapContents: ByteString = .init(encodingAsUTF8: """
      {
        "": {
          "diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.dia",
          "emit-module-diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.emit-module.dia"
        },
        "\(try AbsolutePath(validating: "/some/workingdir/foo.swift").nativePathString(escaped: true))": {
          "object": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.o"
        }
      }
      """)
      try localFileSystem.writeFileContents(fileMapFile, bytes: outputMapContents)

      // Inputs with relative paths and working-dir should use absolute paths in output file maps
      var driver = try TestDriver(args: ["swiftc",
                                     "-target", "arm64-apple-ios13.1",
                                     "foo.swift",
                                     "-working-directory", try AbsolutePath(validating: "/some/workingdir").nativePathString(escaped: false),
                                     "-output-file-map", fileMapFile.description])
      let plannedJobs = try await driver.planBuild()
      let compileJob = plannedJobs[0]
      expectEqual(compileJob.kind, .compile)
      try expectJobInvocationMatches(compileJob, .flag("-o"), .path(.absolute(.init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.o"))))
    }
  }

  @Test func sysrootHandling() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-sysroot", "/path/to/sysroot", "-c", "input.swift"])
      let jobs = try await driver.planBuild()

      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .compile)
      try expectJobInvocationMatches(jobs[0], .flag("-sysroot"), .path(.absolute(.init(validating: "/path/to/sysroot"))))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-sdk", "/path/to/sdk", "-sysroot", "/path/to/sysroot", "-c", "input.swift"])
      let jobs = try await driver.planBuild()

      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .compile)
      try expectJobInvocationMatches(jobs[0], .flag("-sysroot"), .path(.absolute(.init(validating: "/path/to/sysroot"))))
    }
  }

  @Test func adopterConfigFile() throws {
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes:
        #"""
        [
          {
            "key": "SkipFeature1",
            "moduleNames": ["foo", "bar"]
          }
        ]
        """#
      )
      let configs = Driver.parseAdopterConfigs(file)
      expectEqual(configs.count, 1)
      expectEqual(configs[0].key, "SkipFeature1")
      expectEqual(configs[0].moduleNames, ["foo", "bar"])
      let modules = Driver.getAllConfiguredModules(withKey: "SkipFeature1", configs)
      #expect(modules.contains("foo"))
      #expect(modules.contains("bar"))
      #expect(Driver.getAllConfiguredModules(withKey: "SkipFeature2", configs).isEmpty)
    }
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes: "][ malformed }{")
      let configs = Driver.parseAdopterConfigs(file)
      expectEqual(configs.count, 0)
    }
    do {
      let configs = Driver.parseAdopterConfigs(try AbsolutePath(validating: "/abc/c/a.json"))
      expectEqual(configs.count, 0)
    }
  }

  @Test func extractPackageName() throws {
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes:
        """
        // swift-module-flags: -target arm64e-apple-macos12.0
        // swift-module-flags-ignorable: -library-level api\
        // swift-module-flags-ignorable-private: -package-name myPkg
        """
      )
      let flags = try getAllModuleFlags(VirtualPath.absolute(file))
      let idx = flags.firstIndex(of: "-package-name")
      #expect(idx != nil)
      #expect(idx! + 1 < flags.count)
      expectEqual(flags[idx! + 1], "myPkg")
    }
  }

  @Test func extractLibraryLevel() throws {
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes: "// swift-module-flags: -library-level api")
      let flags = try getAllModuleFlags(VirtualPath.absolute(file))
      try expectEqual(try getLibraryLevel(flags), .api)
    }
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes:
        """
        // swift-module-flags: -target arm64e-apple-macos12.0
        // swift-module-flags-ignorable: -library-level spi
        """
      )
      let flags = try getAllModuleFlags(VirtualPath.absolute(file))
      try expectEqual(try getLibraryLevel(flags), .spi)
    }
    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try localFileSystem.writeFileContents(file, bytes:
        "// swift-module-flags: -target arm64e-apple-macos12.0"
      )
      let flags = try getAllModuleFlags(VirtualPath.absolute(file))
      try expectEqual(try getLibraryLevel(flags), nil)
    }
  }

  @Test func supportedFeatureJson() throws {
    let driver = try TestDriver(args: ["swiftc", "-emit-module", "foo.swift"])
    #expect(!driver.supportedFrontendFeatures.isEmpty)
    #expect(driver.supportedFrontendFeatures.contains("experimental-skip-all-function-bodies"))
  }

  @Test func saveUnkownDriverFlags() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-typecheck", "a.swift", "b.swift", "-unlikely-flag-for-testing"])
      let plannedJobs = try await driver.planBuild()
      expectJobInvocationMatches(plannedJobs[0], .flag("-unlikely-flag-for-testing"))
    }
  }

  @Test func emitClangHeaderPath() async throws {
      var driver = try TestDriver(args: [
        "swiftc", "-emit-clang-header-path", "path/to/header", "-typecheck", "test.swift"
      ])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 2)
      try expectJobInvocationMatches(jobs[0], .flag("-emit-objc-header-path"), toPathOption("path/to/header"))
  }

  @Test func clangModuleValidateOnce() async throws {
    let flagTest = try TestDriver(args: ["swiftc", "-typecheck", "foo.swift"])
    guard flagTest.isFrontendArgSupported(.clangBuildSessionFile),
          flagTest.isFrontendArgSupported(.validateClangModulesOnce) else {
      return
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-typecheck", "foo.swift"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let job = jobs.first!
      #expect(!job.commandLine.contains(.flag("-validate-clang-modules-once")))
      #expect(!job.commandLine.contains(.flag("-clang-build-session-file")))
    }

    do {
      try await assertDriverDiagnostics(args: ["swiftc", "-validate-clang-modules-once",
                                         "foo.swift"]) {
        $1.expect(.error("'-validate-clang-modules-once' cannot be specified if '-clang-build-session-file' is not present"))
      }
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-validate-clang-modules-once",
                                     "-clang-build-session-file", "testClangModuleValidateOnce.session",
                                     "foo.swift"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      let job = jobs.first!
      expectJobInvocationMatches(job, .flag("-validate-clang-modules-once"))
      expectJobInvocationMatches(job, .flag("-clang-build-session-file"))
    }
  }

  @Test func webAssemblyUnsupportedFeatures() async throws {
    var env = ProcessEnv.block
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    do {
      var driver = try TestDriver(args: ["swift", "-target", "wasm32-unknown-wasi", "foo.swift"], env: env)
      await #expect {
        try await driver.planBuild()
      } throws: { error in
        guard case WebAssemblyToolchain.Error.interactiveModeUnsupportedForTarget("wasm32-unknown-wasi") = error else {
          return false
        }
        return true
      }
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-target", "wasm32-unknown-wasi", "-emit-library", "foo.swift"], env: env)
      await #expect {
        try await driver.planBuild()
      } throws: { error in
        guard case WebAssemblyToolchain.Error.dynamicLibrariesUnsupportedForTarget("wasm32-unknown-wasi") = error else {
          return false
        }
        return true
      }
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-target", "wasm32-unknown-wasi", "-no-static-executable", "foo.swift"], env: env)
      await #expect {
        try await driver.planBuild()
      } throws: { error in
        guard case WebAssemblyToolchain.Error.dynamicLibrariesUnsupportedForTarget("wasm32-unknown-wasi") = error else {
          return false
        }
        return true
      }
    }

    do {
      #expect {
        try TestDriver(args: ["swiftc", "-target", "wasm32-unknown-wasi", "foo.swift", "-sanitize=thread"], env: env)
      } throws: { error in
        guard case WebAssemblyToolchain.Error.sanitizersUnsupportedForTarget("wasm32-unknown-wasi") = error else {
          return false
        }
        return true
      }
    }
  }

  @Test func scanDependenciesOption() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-scan-dependencies", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      expectJobInvocationMatches(plannedJobs[0], .flag("-scan-dependencies"))
    }

    // Test .d output
    do {
      var driver = try TestDriver(args: ["swiftc", "-scan-dependencies",
                                     "-emit-dependencies", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let job = plannedJobs[0]
      expectJobInvocationMatches(job, .flag("-scan-dependencies"))
      expectJobInvocationMatches(job, .flag("-emit-dependencies-path"))
      #expect(commandContainsTemporaryPath(job.commandLine, "foo.d"))
    }
  }

  @Test func experimentalPerformanceAnnotations() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-experimental-performance-annotations",
                                     "-emit-sil", "-o", "foo.sil"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let emitModuleJob = plannedJobs[0]
      expectEqual(emitModuleJob.kind, .compile)
      expectJobInvocationMatches(emitModuleJob, .flag("-experimental-performance-annotations"))
    }
  }

  @Test func verifyEmittedInterfaceJob() async throws {
    // Evolution enabled
    var envVars = ProcessEnv.block
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-emit-private-module-interface-path", "foo.private.swiftinterface",
                                     "-verify-emitted-module-interface",
                                     "-enable-library-evolution"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 4)

      // Emit-module should emit both module interface files
      let emitJob = try plannedJobs.findJob(.emitModule)
      let publicModuleInterface = emitJob.outputs.filter { $0.type == .swiftInterface }
      expectEqual(publicModuleInterface.count, 1)
      let privateModuleInterface = emitJob.outputs.filter { $0.type == .privateSwiftInterface }
      expectEqual(privateModuleInterface.count, 1)

      // Each verify job should either check the public or the private module interface, not both.
      let verifyJobs = plannedJobs.filter { $0.kind == .verifyModuleInterface }
      expectEqual(verifyJobs.count, 2)
      for verifyJob in verifyJobs {
        let publicVerify = verifyJob.inputs.contains(try #require(publicModuleInterface.first))
        let privateVerify = verifyJob.inputs.contains(try #require(privateModuleInterface.first))
        #expect(publicVerify != privateVerify)
        #expect(!verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
      }
    }

    // No Evolution
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface", "-verify-emitted-module-interface"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      #expect(!plannedJobs.containsJob(.verifyModuleInterface))
    }

    // Explicitly disabled
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-no-verify-emitted-module-interface"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      #expect(!plannedJobs.containsJob(.verifyModuleInterface))
      let emitJob = try plannedJobs.findJob(.emitModule)
      if driver.isFrontendArgSupported(.noVerifyEmittedModuleInterface) {
        expectJobInvocationMatches(emitJob, .flag("-no-verify-emitted-module-interface"))
      }
    }

    // Emit-module separately
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-experimental-emit-module-separately"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)
      let emitJob = try plannedJobs.findJob(.emitModule)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      let emitInterfaceOutput = emitJob.outputs.filter { $0.type == .swiftInterface }
      expectEqual(emitInterfaceOutput.count, 1,
                    "Emit module job should only have one swiftinterface output")
      expectEqual(verifyJob.inputs.count, 1)
      expectEqual(verifyJob.inputs[0], emitInterfaceOutput[0])
      expectJobInvocationMatches(verifyJob, .path(emitInterfaceOutput[0].file))
      #expect(!verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
      #expect(!emitJob.commandLine.contains("-no-verify-emitted-module-interface"))
      #expect(!emitJob.commandLine.contains("-verify-emitted-module-interface"))
    }

    // Whole-module
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let emitJob = plannedJobs[0]
      let verifyJob = plannedJobs[1]
      expectEqual(emitJob.kind, .compile)
      let emitInterfaceOutput = emitJob.outputs.filter { $0.type == .swiftInterface }
      expectEqual(emitInterfaceOutput.count, 1,
                    "Emit module job should only have one swiftinterface output")
      expectEqual(verifyJob.kind, .verifyModuleInterface)
      expectEqual(verifyJob.inputs.count, 1)
      expectEqual(verifyJob.inputs[0], emitInterfaceOutput[0])
      expectJobInvocationMatches(verifyJob, .path(emitInterfaceOutput[0].file))
      #expect(!verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Test the `-no-verify-emitted-module-interface` flag with whole-module
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-no-verify-emitted-module-interface"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      let compileJob = try plannedJobs.findJob(.compile)
      if driver.isFrontendArgSupported(.noVerifyEmittedModuleInterface) {
        expectJobInvocationMatches(compileJob, .flag("-no-verify-emitted-module-interface"))
      }
    }

    // Enabled by default when the library-level is api.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-library-level", "api"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      #expect(!verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Enabled by default when the library-level is spi.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-library-level", "spi"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      #expect(!verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Errors downgraded to a warning when a module is blocklisted.
    try await assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                       "TestBlocklistedModule", "-emit-module-interface",
                                       "-enable-library-evolution",
                                       "-whole-module-optimization",
                                       "-library-level", "api"]) { driver, verify in
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      if driver.isFrontendArgSupported(.downgradeTypecheckInterfaceError) {
        expectJobInvocationMatches(verifyJob, .flag("-downgrade-typecheck-interface-error"))
      }

      verify.expect(.remark("Verification of module interfaces for 'TestBlocklistedModule' set to warning only by blocklist"))
    }

    // Don't downgrade to error blocklisted modules when the env var is set.
    do {
      envVars["ENABLE_DEFAULT_INTERFACE_VERIFIER"] = "YES"
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "TestBlocklistedModule", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization"], env: envVars)
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      #expect(!verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Don't downgrade to error blocklisted modules if the verify flag is set.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "TestBlocklistedModule", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-verify-emitted-module-interface"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      #expect(!verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // The flag -check-api-availability-only is not passed down to the verify job.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-verify-emitted-module-interface",
                                     "-enable-library-evolution",
                                     "-check-api-availability-only"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 3)

      let emitJob = try plannedJobs.findJob(.emitModule)
      expectJobInvocationMatches(emitJob, .flag("-check-api-availability-only"))

      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      #expect(!verifyJob.commandLine.contains(.flag("-check-api-availability-only")))
    }

    // Do verify modules with compatibility headers.
    do {
      var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution", "-emit-objc-header-path", "foo-Swift.h"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()
      expectEqual(plannedJobs.filter( { job in job.kind == .verifyModuleInterface}).count, 1)
    }
  }

  @Test func verifyEmittedPackageInterface() async throws {
      // Evolution enabled
      do {
        var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module",
                                       "-module-name", "foo",
                                       "-package-name", "foopkg",
                                       "-emit-module-interface",
                                       "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                       "-verify-emitted-module-interface",
                                       "-enable-library-evolution"])

        let plannedJobs = try await driver.planBuild()
        #expect(plannedJobs.count == 4)
        let emitJob = try plannedJobs.findJob(.emitModule)
        let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
        let packageOutputs = emitJob.outputs.filter { $0.type == .packageSwiftInterface }
        let publicOutputs = emitJob.outputs.filter { $0.type == .swiftInterface }
        expectEqual(packageOutputs.count, 1,
                       "There should be one package swiftinterface output")
        expectEqual(publicOutputs.count, 1,
                       "There should be one public swiftinterface output")
        expectEqual(verifyJob.inputs.count, 1)
        expectEqual(verifyJob.inputs[0], publicOutputs[0])
        #expect(verifyJob.outputs.isEmpty)
      }

      // Explicitly disabled
      do {
        var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module",
                                       "-module-name",  "foo",
                                       "-package-name", "foopkg",
                                       "-emit-module-interface",
                                       "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                       "-enable-library-evolution",
                                       "-no-verify-emitted-module-interface"])
        let plannedJobs = try await driver.planBuild()
        #expect(plannedJobs.count == 2)
      }

      // Emit-module separately
      do {
        var driver = try TestDriver(args: ["swiftc", "foo.swift", "-emit-module",
                                       "-module-name",  "foo",
                                       "-package-name", "foopkg",
                                       "-emit-module-interface",
                                       "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                       "-enable-library-evolution",
                                       "-experimental-emit-module-separately"])
        let plannedJobs = try await driver.planBuild()
        #expect(plannedJobs.count == 4)
        let emitJob = try plannedJobs.findJob(.emitModule)
        let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
        let packageOutputs = emitJob.outputs.filter { $0.type == .packageSwiftInterface }
        let publicOutputs = emitJob.outputs.filter { $0.type == .swiftInterface }
        expectEqual(packageOutputs.count, 1,
                       "There should be one package swiftinterface output")
        expectEqual(publicOutputs.count, 1,
                       "There should be one public swiftinterface output")
        expectEqual(verifyJob.inputs.count, 1)
        expectEqual(verifyJob.inputs[0], publicOutputs[0])
        #expect(verifyJob.outputs.isEmpty)
      }
  }

  @Test func loadPackageInterface() async throws {
    try await withTemporaryDirectory { path in
      let envVars = ProcessEnv.block
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import Foo;")
      }
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "testLoadPackageInterface")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try TestDriver(args: ["swiftc", main.nativePathString(escaped: false),
                                     "-typecheck",
                                     "-package-name", "foopkg",
                                     "-experimental-package-interface-load",
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: false),
                                     "-enable-library-evolution"] + sdkArgumentsForTesting,
                              env: envVars)

      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      expectJobInvocationMatches(plannedJobs[0], .flag("-experimental-package-interface-load"))
    }
  }

  @Test func vfsOverlay() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-c", "-vfsoverlay", "overlay.yaml", "foo.swift"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      try expectJobInvocationMatches(plannedJobs[0], .flag("-vfsoverlay"), toPathOption("overlay.yaml"))
    }

    // Verify that the overlays are passed to the frontend in the same order.
    do {
      var driver = try TestDriver(args: ["swiftc", "-c", "-vfsoverlay", "overlay1.yaml", "-vfsoverlay", "overlay2.yaml", "-vfsoverlay", "overlay3.yaml", "foo.swift"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      try expectJobInvocationMatches(plannedJobs[0], .flag("-vfsoverlay"), toPathOption("overlay1.yaml"), .flag("-vfsoverlay"), toPathOption("overlay2.yaml"), .flag("-vfsoverlay"), toPathOption("overlay3.yaml"))
    }
  }

  @Test func cachingBuildOptions() async throws {
    try await assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-cache-compile-job") {
      $1.expect(.warning("-cache-compile-job cannot be used without explicit module build, turn off caching"))
    }
    try await assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-cache-compile-job", "-explicit-module-build")
  }

  @Test func enableFeatures() async throws {
    do {
      let featureArgs = [
        "-enable-upcoming-feature", "MemberImportVisibility",
        "-enable-experimental-feature", "ParserValidation",
        "-enable-upcoming-feature", "ConcisePoundFile",
      ]
      var driver = try TestDriver(args: ["swiftc", "file.swift"] + featureArgs)
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 2)

      // Verify that the order of both upcoming and experimental features is preserved.
      #expect(jobs[0].commandLine.contains(subsequence: featureArgs.map { Job.ArgTemplate.flag($0) }))
    }
  }

  @Test func emitAPIDescriptorEmitModule() async throws {
    try await withTemporaryDirectory { path in
      do {
        let apiDescriptorPath = path.appending(component: "api.json").nativePathString(escaped: false)
        var driver = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                       "-emit-module", "-module-name", "Test",
                                       "-emit-api-descriptor-path", apiDescriptorPath])

        let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try jobs.findJob(.emitModule)
        #expect(emitModuleJob.commandLine.contains(.flag("-emit-api-descriptor-path")))
      }

      do {
        var env = ProcessEnv.block
        env["TAPI_SDKDB_OUTPUT_PATH"] = path.appending(component: "SDKDB").nativePathString(escaped: false)
        var driver = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                       "-emit-module", "-module-name", "Test"], env: env)
        let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try jobs.findJob(.emitModule)
        #expect(emitModuleJob.commandLine.contains(subsequence: [
          .flag("-emit-api-descriptor-path"),
          .path(.absolute(path.appending(components: "SDKDB", "Test.\(driver.frontendTargetInfo.target.moduleTriple.triple).swift.sdkdb"))),
        ]))
      }

      do {
        var env = ProcessEnv.block
        env["LD_TRACE_FILE"] = path.appending(component: ".LD_TRACE").nativePathString(escaped: false)
        var driver = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                       "-emit-module", "-module-name", "Test"], env: env)
        let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try jobs.findJob(.emitModule)
        #expect(emitModuleJob.commandLine.contains(subsequence: [
          .flag("-emit-api-descriptor-path"),
          .path(.absolute(path.appending(components: "SDKDB", "Test.\(driver.frontendTargetInfo.target.moduleTriple.triple).swift.sdkdb"))),
        ]))
      }
    }
  }

  @Test func emitAPIDescriptorWholeModuleOptimization() async throws {
    try await withTemporaryDirectory { path in
      do {
        let apiDescriptorPath = path.appending(component: "api.json").nativePathString(escaped: false)
        var driver = try TestDriver(args: ["swiftc", "-whole-module-optimization",
                                       "-driver-filelist-threshold=0",
                                       "foo.swift", "bar.swift", "baz.swift",
                                       "-module-name", "Test", "-emit-module",
                                       "-emit-api-descriptor-path", apiDescriptorPath])

        let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let compileJob = try jobs.findJob(.compile)
        let supplementaryOutputs = try compileJob.commandLine.supplementaryOutputFilemap
        #expect(supplementaryOutputs.entries.values.first?[.jsonAPIDescriptor] != nil)
      }

      do {
        var env = ProcessEnv.block
        env["TAPI_SDKDB_OUTPUT_PATH"] = path.appending(component: "SDKDB").nativePathString(escaped: false)
        var driver = try TestDriver(args: ["swiftc", "-whole-module-optimization",
                                       "-driver-filelist-threshold=0",
                                       "foo.swift", "bar.swift", "baz.swift",
                                       "-module-name", "Test", "-emit-module"], env: env)

        let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let compileJob = try jobs.findJob(.compile)
        let supplementaryOutputs = try compileJob.commandLine.supplementaryOutputFilemap
        #expect(supplementaryOutputs.entries.values.first?[.jsonAPIDescriptor] != nil)
      }

      do {
        var env = ProcessEnv.block
        env["LD_TRACE_FILE"] = path.appending(component: ".LD_TRACE").nativePathString(escaped: false)
        var driver = try TestDriver(args: ["swiftc", "-whole-module-optimization",
                                       "-driver-filelist-threshold=0",
                                       "foo.swift", "bar.swift", "baz.swift",
                                       "-module-name", "Test", "-emit-module"], env: env)

        let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
        let compileJob = try jobs.findJob(.compile)
        let supplementaryOutputs = try compileJob.commandLine.supplementaryOutputFilemap
        #expect(supplementaryOutputs.entries.values.first?[.jsonAPIDescriptor] != nil)
      }
    }
  }

  @Test(.requireHostOS(.macosx, comment: "ABI descriptor is only emitted on Darwin platforms")) func emitABIDescriptor() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-module-name=ThisModule", "-wmo", "main.swift", "multi-threaded.swift", "-emit-module", "-o", "test.swiftmodule"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      #expect(plannedJobs.count == 1)

      #expect(plannedJobs[0].kind == .compile)
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-abi-descriptor-path"))
    }
    do {
      var driver = try TestDriver(args: ["swiftc", "-module-name=ThisModule", "main.swift", "multi-threaded.swift", "-emit-module", "-o", "test.swiftmodule", "-experimental-emit-module-separately"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      #expect(plannedJobs.count == 3)

      #expect(plannedJobs[0].kind == .emitModule)
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-abi-descriptor-path"))
    }
  }
}
