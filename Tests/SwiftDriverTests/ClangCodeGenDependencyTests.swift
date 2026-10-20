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

import Foundation
import TSCBasic
@_spi(Testing) @preconcurrency import SwiftDriver
import SwiftOptions
import TestUtilities
import Testing

@Suite struct ClangCodeGenDependencyTests {
  @Test func rootsExcludeObsoleteClangTransitiveDependencies() throws {
    let json = """
      {"mainModuleName":"Main","modules":[
        {"swift":"Main"},
        {"modulePath":"Main.swiftmodule",
         "directDependencies":[{"swift":"SDK"},{"clang":"Parent"}],
         "details":{"swift":{}}},
        {"swift":"SDK"},
        {"modulePath":"SDK.swiftmodule",
         "directDependencies":[{"clang":"Header"}],
         "details":{"swift":{}}},
        {"clang":"Parent"},
        {"modulePath":"Parent.pcm",
         "directDependencies":[{"clang":"HighOnlySupport"}],
         "details":{"clang":{"moduleMapPath":"module.modulemap","contextHash":"high","commandLine":[]}}},
        {"clang":"Header"},
        {"modulePath":"Header.pcm","directDependencies":[],
         "details":{"clang":{"moduleMapPath":"module.modulemap","contextHash":"header","commandLine":[]}}},
        {"clang":"HighOnlySupport"},
        {"modulePath":"HighOnlySupport.pcm","directDependencies":[],
         "details":{"clang":{"moduleMapPath":"module.modulemap","contextHash":"support","commandLine":[]}}},
        {"swift":"Unused"},
        {"modulePath":"Unused.swiftmodule",
         "directDependencies":[{"clang":"HighOnlySupport"}],
         "details":{"swift":{}}}
      ]}
      """
    let graph = try JSONDecoder().decode(
      InterModuleDependencyGraph.self, from: Data(json.utf8))
    let roots = try Driver.clangCodeGenDependencyRoots(in: graph)
    #expect(roots == ["Header", "Parent"])
    #expect(try Driver.clangCodeGenDependencyRoots(in: graph, from: .swift("SDK")) == ["Header"])
    let command = Driver.clangCodeGenScanCommand(
      [], target: "arm64-apple-macosx13.0", moduleNames: roots)
    #expect(!command.contains(.flag("HighOnlySupport")))
  }

  @Test func scanUsesDeploymentTargetAndDiscardsSemanticArtifacts() {
    let command: [Job.ArgTemplate] = [
      .flag("-frontend"), .flag("-scan-dependencies"),
      .flag("-target"), .flag("arm64-apple-macosx13.0"),
      .flag("-clang-target"), .flag("arm64-apple-macosx15.0"),
      .flag("-Xcc"), .flag("-DKEEP_THIS=1"),
      .flag("-Xcc"), .flag("-fmodule-file=Feature=semantic.pcm"),
      .flag("-Xcc"), .flag("-fmodule-file-cache-key"),
      .flag("-Xcc"), .flag("semantic.pcm"),
      .flag("-Xcc"), .flag("semantic-key"),
      .flag("-dependency-scan-cache-path"), .flag("semantic-cache"),
      .flag("-load-dependency-scan-cache"),
      .flag("-serialize-dependency-scan-cache"),
      .flag("-validate-prior-dependency-scan-cache"),
      .flag("-direct-clang-cc1-module-build"),
    ]
    let result = Driver.clangCodeGenScanCommand(
      command, target: "arm64-apple-macosx13.0",
      moduleNames: ["Base", "Feature"])
    #expect(result == [
      .flag("-frontend"), .flag("-scan-dependencies"),
      .flag("-target"), .flag("arm64-apple-macosx13.0"),
      .flag("-Xcc"), .flag("-DKEEP_THIS=1"),
      .flag("-clang-target"), .flag("arm64-apple-macosx13.0"),
      .flag("-experimental-clang-codegen-dependency"), .flag("Base"),
      .flag("-experimental-clang-codegen-dependency"), .flag("Feature"),
    ])
  }

  @Test func interfaceScanUsesAuthoritativeDescriptorAndRetainsImportOptions() throws {
    let command = [
      "-frontend", "-compile-module-from-interface",
      "-target", "arm64-apple-macosx13.0",
      "-clang-target", "arm64-apple-macosx15.0",
      "-I", "/headers", "-Xcc", "-DINTERFACE=1",
      "-target", "arm64-apple-macosx14.0",
      "-experimental-clang-target-context", "arm64-apple-macosx14.0",
      "-Xcc", "-experimental-clang-target-context", "-Xcc", "not-a-descriptor",
      "SDK.swiftinterface", "-module-name", "SDK",
      "-candidate-module-file", "old.swiftmodule", "-o", "SDK.swiftmodule",
      "-Xcc", "-fno-implicit-modules", "-Xcc", "-fno-implicit-module-maps",
      "-Xcc", "-fmodule-file=Header=high.pcm",
    ]
    let target = try #require(Driver.clangTargetContext(in: command))
    #expect(target == "arm64-apple-macosx14.0")
    let scan = Driver.clangCodeGenScanCommand(
      Driver.clangInterfaceScanCommand(command, interfacePath: "SDK.swiftinterface",
                                      sourceInputs: [.flag("main.swift")],
                                      rootScanCommand: [
                                        .flag("-module-cache-path"), .flag("/shared-cache"),
                                        .flag("-sdk-module-cache-path"), .flag("/sdk-cache"),
                                      ]),
      target: target, moduleNames: ["Header"])
    #expect(scan.contains(.flag("-scan-dependencies")))
    #expect(scan.contains(.flag("/headers")))
    #expect(scan.contains(.flag("-DINTERFACE=1")))
    #expect(scan.contains(.flag("main.swift")))
    #expect(scan.contains(.flag("/shared-cache")))
    #expect(scan.contains(.flag("/sdk-cache")))
    for discarded in ["-compile-module-from-interface", "SDK.swiftinterface", "-o",
                       "SDK.swiftmodule", "old.swiftmodule", "-candidate-module-file",
                       "-fno-implicit-modules", "-fno-implicit-module-maps",
                       "-fmodule-file=Header=high.pcm", "arm64-apple-macosx15.0"] {
      #expect(!scan.contains(.flag(discarded)))
    }
    let clangTargetIndex = try #require(scan.firstIndex(of: .flag("-clang-target")))
    #expect(scan[clangTargetIndex + 1] == .flag("arm64-apple-macosx14.0"))
  }

  @Test func binaryScanReplacesConsumerOptionsWithoutDuplicatingClangDefaults() throws {
    let native = ["-cc1", "-isysroot", "/producer-sdk", "-resource-dir", "/producer-resource",
                  "-x", "objective-c++", "-DPRODUCER=1", "-I/producer"]
    let scan = try Driver.clangBinaryScanCommand([
      .flag("-frontend"), .flag("-scan-dependencies"), .flag("main.swift"),
      .flag("-target"), .flag("arm64-apple-macosx13.0"),
      .flag("-I"), .flag("/consumer"), .flag("-F"), .flag("/consumer-frameworks"),
      .flag("-sdk"), .flag("/consumer-sdk"),
      .flag("-resource-dir"), .flag("/consumer-resource"),
      .flag("-Xcc"), .flag("-DCONSUMER=1"),
    ], contextArguments: native,
       target: "arm64-apple-macosx15.0||NATIVE", moduleNames: ["Header"],
       scannerModuleCachePath: "/scan-cache")
    let expected: [Job.ArgTemplate] = [
      .flag("-frontend"), .flag("-scan-dependencies"), .flag("main.swift"),
      .flag("-target"), .flag("arm64-apple-macosx13.0"),
    ] + native.flatMap { [.flag("-experimental-clang-context-argument"), .flag($0)] } + [
      .flag("-experimental-clang-context-argument"), .flag("-fimplicit-module-maps"),
      .flag("-experimental-clang-context-argument"), .flag("-fmodules-cache-path=/scan-cache"),
      .flag("-clang-target"), .flag("arm64-apple-macosx15.0"),
      .flag("-experimental-clang-codegen-dependency"), .flag("Header"),
    ]
    #expect(scan == expected)
    #expect(throws: PlanningError.self) {
      try Driver.clangBinaryScanCommand([], contextArguments: [],
        target: "arm64-apple-macosx15.0||NATIVE", moduleNames: ["Header"],
        scannerModuleCachePath: "/scan-cache")
    }
    #expect(throws: PlanningError.self) {
      try Driver.clangBinaryScanCommand([], contextArguments: ["-O3"],
        target: "arm64-apple-macosx15.0||NATIVE", moduleNames: ["Header"],
        scannerModuleCachePath: "/scan-cache")
    }
  }

  @Test func binaryScanEnablesDiscoveryForExplicitAndOmittedDefaults() throws {
    let context = "arm64-apple-macosx15.0||NATIVE"
    let base = ["-cc1", "-fmodules", "-DVALUE=1", "-I/producer"]
    let variants = [
      base,
      base + ["-fno-implicit-modules", "-fno-implicit-module-maps"],
      base + ["-fimplicit-module-maps", "-fmodules-cache-path=/producer-cache"],
    ]
    let expected = try Driver.clangBinaryScanCommand(
      [], contextArguments: base, target: context, moduleNames: ["Header"],
      scannerModuleCachePath: "/resolved-default-cache")
    for arguments in variants {
      let scan = try Driver.clangBinaryScanCommand(
        [], contextArguments: arguments, target: context, moduleNames: ["Header"],
        scannerModuleCachePath: "/resolved-default-cache")
      #expect(scan == expected)
      #expect(Driver.clangContextSemanticArguments(arguments) == base)
    }
    #expect(expected.contains(.flag("-fimplicit-module-maps")))
    #expect(expected.contains(.flag("-fmodules-cache-path=/resolved-default-cache")))
    #expect(Driver.clangModuleCachePath(in: ["-cc1", "-fmodules-cache-path=/resolved-default-cache"])
            == "/resolved-default-cache")
    #expect(Driver.clangModuleCachePath(in: ["-fmodules-cache-path", "/first",
                                            "-fmodules-cache-path=/last"]) == "/last")
    #expect(Driver.clangModuleCachePath(in: ["-fmodules-cache-path="]) == nil)
  }

  @Test func contextNormalizationRemovesOnlyOperationalArguments() {
    let result = Driver.clangContextSemanticArguments([
      "-target", "arm64-apple-macosx15.0", "--target=arm64-apple-macosx15.0",
      "-fmodules-cache-path=/tmp/cache", "-fmodule-file=Header=old.pcm",
      "-Xclang", "-fmodule-file-cache-key", "-Xclang", "old.pcm", "-Xclang", "key",
      "-fno-implicit-modules", "-fno-implicit-module-maps",
      "-D", "EXACT=1", "-I", "/headers", "-fmodule-map-file=/headers/module.modulemap",
      "-fmodules-user-build-path=/producer",
      "-Xclang", "-fapinotes-swift-version=6",
      "-darwin-target-variant", "arm64-apple-ios27.0-macabi",
    ])
    #expect(result == [
      "-D", "EXACT=1", "-I", "/headers", "-fmodule-map-file=/headers/module.modulemap",
      "-fmodules-user-build-path=/producer",
      "-Xclang", "-fapinotes-swift-version=6",
    ])
  }

  @Test func cc1ContextNormalizationPreservesPostPolicySemantics() {
    let semantic = [
      "-cc1", "-fsyntax-only", "-O3", "-debug-info-kind=standalone",
      "-dwarf-version=5", "-dwarf-ext-refs", "-fmodule-format=obj",
      "-target-cpu", "apple-m2", "-target-feature", "+neon",
      "-working-directory", "/producer", "-fmodules-user-build-path=/producer",
      "-main-file-name", "<swift-imported-modules>",
      "-D", "MACRO=VALUE", "-I", "/producer/headers",
    ]
    let result = Driver.clangContextSemanticArguments(semantic + [
      "-triple", "arm64-apple-macosx15.0.0",
      "-darwin-target-variant-triple", "arm64-apple-ios27.0.0-macabi",
      "-fmodule-file", "Header=/old/Header.pcm",
      "-fmodule-file-cache-key", "/old/Header.pcm", "old-key",
      "-fmodules-cache-path=/old/cache", "-o", "/old/output",
      "-fno-implicit-modules", "-fno-implicit-module-maps",
    ])
    #expect(result == semantic)
  }

  @Test func semanticCatalogIgnoresOnlyObjCSelectorStubEmissionPolicy() {
    let semantic = ["-cc1", "-O3", "-Os", "-D", "VALUE=1", "-I", "/producer",
                    "-fobjc-runtime=macosx-13.0.0", "-fobjc-arc",
                    "-debug-info-kind=standalone"]
    for toggles in [
      ["-fobjc-msgsend-selector-stubs", "-fobjc-msgsend-class-selector-stubs"],
      ["-fno-objc-msgsend-selector-stubs", "-fno-objc-msgsend-class-selector-stubs"],
      [],
    ] {
      #expect(Driver.clangContextSemanticArguments(semantic + toggles) == semantic)
    }
    #expect(Driver.clangContextSemanticArguments(semantic + ["-O0"]) != semantic)
    #expect(Driver.clangContextSemanticArguments(semantic + ["-I", "/consumer"]) != semantic)
    #expect(Driver.clangContextSemanticArguments(semantic + ["-D", "OTHER=1"]) != semantic)
  }

  @Test func binaryCatalogPreservesIndependentLanguageAndVariantOptions() throws {
    let plain = "arm64-apple-macosx15.0.0||LANG5"
    let zippered = "arm64-apple-macosx15.0.0|arm64-apple-ios27.0.0-macabi|LANG6"
    let entries = ["\(plain)=-cc1", "\(plain)=-D__swift__=51000",
                   "\(plain)=-fapinotes-swift-version=5",
                   "\(zippered)=-cc1", "\(zippered)=-D__swift__=60500",
                   "\(zippered)=-darwin-target-variant",
                   "\(zippered)=arm64-apple-ios27.0.0-macabi"]
    let catalog = try Driver.clangContextArgumentCatalog(entries)
    #expect(catalog[plain] == ["-cc1", "-D__swift__=51000", "-fapinotes-swift-version=5"])
    #expect(catalog[zippered] == ["-cc1", "-D__swift__=60500", "-darwin-target-variant",
                                 "arm64-apple-ios27.0.0-macabi"])
    let scan = try Driver.clangBinaryScanCommand(
      [], contextArguments: try #require(catalog[zippered]), target: zippered,
      moduleNames: ["Header"], scannerModuleCachePath: "/scan-cache")
    #expect(!scan.contains(.flag("-D__swift__=51000")))
    #expect(scan.contains(.flag("-D__swift__=60500")))
    let index = try #require(scan.firstIndex(of: .flag("-target-variant")))
    #expect(scan[index + 1] == .flag("arm64-apple-ios27.0.0-macabi"))
    #expect(throws: PlanningError.self) {
      try Driver.clangContextArgumentCatalog(["missing-context=-DVALUE=1"])
    }
  }

  /// Construct the scanner's Clang-only result, preserving the original
  /// semantic graph for Swift interface jobs.
  private func clangGraph(from semanticJSON: String, suffix: String,
                          commandLineSuffix: [String] = [],
                          nativeContext: String? = nil,
                          nativeArguments: [String]? = nil) throws
    -> InterModuleDependencyGraph {
    var json = try #require(
      JSONSerialization.jsonObject(with: Data(semanticJSON.utf8))
        as? [String: Any])
    let modules = try #require(json["modules"] as? [[String: Any]])
    var clangModules: [[String: Any]] = []
    var dependencies: [[String: String]] = []
    for index in stride(from: 0, to: modules.count, by: 2) {
      guard let name = modules[index]["clang"] as? String else { continue }
      var info = modules[index + 1]
      info["modulePath"] = "\(name)\(suffix).pcm"
      var details = try #require(info["details"] as? [String: Any])
      var clangDetails = try #require(details["clang"] as? [String: Any])
      let command = try #require(clangDetails["commandLine"] as? [String])
      clangDetails["commandLine"] = command + commandLineSuffix
      details["clang"] = clangDetails
      info["details"] = details
      if name == "c_simd", !suffix.isEmpty {
        info["directDependencies"] = [["clang": "SwiftShims"]]
      }
      clangModules.append(modules[index])
      clangModules.append(info)
      dependencies.append(["clang": name])
    }
    var mainInfo = modules[1]
    mainInfo["directDependencies"] = dependencies
    if let context = nativeContext {
      var details = try #require(mainInfo["details"] as? [String: Any])
      var swift = try #require(details["swift"] as? [String: Any])
      swift["clangTargetContext"] = context
      swift["clangContextArguments"] = nativeArguments ?? []
      details["swift"] = swift
      mainInfo["details"] = details
    }
    json["modules"] = [modules[0], mainInfo] + clangModules
    return try JSONDecoder().decode(
      InterModuleDependencyGraph.self,
      from: JSONSerialization.data(withJSONObject: json))
  }

  @Test(arguments: [false, true])
  func rootCompilesUseBothGraphsButInterfacesUseSemanticGraph(wholeModule: Bool) throws {
    var driver = try TestDriver(args: [
      "swiftc", "-explicit-module-build", "-always-rebuild-module-dependencies",
      "-module-name", "test", "-c", "-emit-module",
      "-experimental-emit-module-separately", "-emit-module-separately-wmo",
      "-emit-module-interface-path", "test.swiftinterface",
      "-enable-library-evolution", "test.swift", "other.swift",
    ] + (wholeModule ? ["-whole-module-optimization"] : []))
    let semanticGraph = try JSONDecoder().decode(
      InterModuleDependencyGraph.self,
      from: Data(ModuleDependenciesInputs.fastDependencyScannerOutput.utf8))
    let codeGenGraph = try clangGraph(
      from: ModuleDependenciesInputs.fastDependencyScannerOutput,
      suffix: ".deployment")
    let semanticPlanner = try ExplicitDependencyBuildPlanner(
      dependencyGraph: semanticGraph, toolchain: driver.toolchain)
    let phases = try driver.unwrap { driver in
      try driver.configureClangCodeGenModulePlanner(dependencyGraph: codeGenGraph)
      return try driver.computeJobsForPhasedStandardBuild(
        explicitModulePlanner: semanticPlanner)
    }
    let jobs = phases.allJobs
    let pcmJobs = jobs.filter { $0.kind == .generatePCM }
    #expect(pcmJobs.count == 4)
    #expect(Set(pcmJobs.flatMap(\.outputs).map(\.file.description)) == [
      "SwiftShims.pcm", "c_simd.pcm",
      "SwiftShims.deployment.pcm", "c_simd.deployment.pcm",
    ])
    let lowSimd = try #require(pcmJobs.first {
      $0.outputs.contains { $0.file.description == "c_simd.deployment.pcm" }
    })
    #expect(lowSimd.inputs.contains {
      $0.type == .pcm && $0.file.description == "SwiftShims.deployment.pcm"
    })
    let compileJobs = jobs.filter { $0.kind == .compile }
    #expect(!compileJobs.isEmpty)
    let emitModuleJob = try #require(jobs.first { $0.kind == .emitModule })
    let emitIndex = try #require(jobs.firstIndex(of: emitModuleJob))
    #expect(jobs[..<emitIndex].filter { $0.kind == .generatePCM }.count == pcmJobs.count)
    for job in compileJobs + [emitModuleJob] {
      #expect(job.commandLine.filter {
        $0 == .flag("-experimental-clang-codegen-module-file")
      }.count == 2)
      let pcmInputs = Set(job.inputs.filter { $0.type == .pcm }.map(\.file.description))
      #expect(pcmInputs.contains("SwiftShims.deployment.pcm"))
      #expect(pcmInputs.contains("c_simd.deployment.pcm"))
      #expect(pcmInputs.contains("SwiftShims.pcm"))
      #expect(pcmInputs.contains("c_simd.pcm"))
      for input in job.inputs where input.type == .pcm {
        #expect(pcmJobs.contains { $0.outputs.contains(input) })
      }
    }
    let interfaceJobs = jobs.filter { $0.kind == .compileModuleFromInterface }
    #expect(!interfaceJobs.isEmpty)
    let verifyJobs = jobs.filter { $0.kind == .verifyModuleInterface }
    #expect(!verifyJobs.isEmpty)
    for job in jobs where job.kind != .compile && job.kind != .emitModule &&
                           job.kind != .verifyModuleInterface {
      #expect(!job.commandLine.contains(.flag("-experimental-clang-codegen-module-file")))
    }
    for job in interfaceJobs {
      #expect(!job.inputs.contains { $0.file.description.contains(".deployment.pcm") })
    }
    for job in verifyJobs {
      #expect(job.commandLine.contains(.flag("-experimental-clang-codegen-module-file")))
      #expect(job.inputs.contains { $0.file.description.contains(".deployment.pcm") })
    }
  }

  @Test func moduleOnlyBuildDependsOnDeploymentPCMs() throws {
    var driver = try TestDriver(args: [
      "swiftc", "-explicit-module-build", "-always-rebuild-module-dependencies",
      "-module-name", "test", "-emit-module",
      "-experimental-emit-module-separately", "test.swift", "other.swift",
    ])
    let semanticGraph = try JSONDecoder().decode(
      InterModuleDependencyGraph.self,
      from: Data(ModuleDependenciesInputs.fastDependencyScannerOutput.utf8))
    let codeGenGraph = try clangGraph(
      from: ModuleDependenciesInputs.fastDependencyScannerOutput,
      suffix: ".deployment")
    let planner = try ExplicitDependencyBuildPlanner(
      dependencyGraph: semanticGraph, toolchain: driver.toolchain)
    let jobs = try driver.unwrap { driver in
      try driver.configureClangCodeGenModulePlanner(dependencyGraph: codeGenGraph)
      return try driver.computeJobsForPhasedStandardBuild(
        explicitModulePlanner: planner).allJobs
    }
    #expect(!jobs.contains { $0.kind == .compile })
    let emitModuleJob = try #require(jobs.first { $0.kind == .emitModule })
    let pcmJobs = jobs.filter { $0.kind == .generatePCM }
    #expect(pcmJobs.count == 4)
    #expect(emitModuleJob.commandLine.filter {
      $0 == .flag("-experimental-clang-codegen-module-file")
    }.count == 2)
    let deploymentInputs = emitModuleJob.inputs.filter {
      $0.type == .pcm && $0.file.description.contains(".deployment.pcm")
    }
    #expect(deploymentInputs.count == 2)
    for input in deploymentInputs {
      #expect(pcmJobs.contains { $0.outputs.contains(input) })
    }
  }

  @Test(arguments: [false, true])
  func sharedPCMOutputsRequireIdenticalJobs(conflicting: Bool) throws {
    var driver = try TestDriver(args: [
      "swiftc", "-explicit-module-build", "-always-rebuild-module-dependencies",
      "-module-name", "test", "-c", "-whole-module-optimization", "test.swift",
    ])
    let semanticGraph = try JSONDecoder().decode(
      InterModuleDependencyGraph.self,
      from: Data(ModuleDependenciesInputs.fastDependencyScannerOutput.utf8))
    let codeGenGraph = try clangGraph(
      from: ModuleDependenciesInputs.fastDependencyScannerOutput, suffix: "",
      commandLineSuffix: conflicting ? ["-DCHANGED=1"] : [])
    let planner = try ExplicitDependencyBuildPlanner(
      dependencyGraph: semanticGraph, toolchain: driver.toolchain)
    do {
      let jobs = try driver.unwrap { driver in
        try driver.configureClangCodeGenModulePlanner(dependencyGraph: codeGenGraph)
        return try driver.computeJobsForPhasedStandardBuild(
          explicitModulePlanner: planner).allJobs
      }
      #expect(!conflicting)
      #expect(jobs.filter { $0.kind == .generatePCM }.count == 2)
    } catch let error as PlanningError {
      #expect(conflicting)
      #expect(error.description.contains("conflicting PCM output paths"))
    }
  }

  @Test func interfacesUseTheirOwnPCMMapsAndShareIdenticalBuilds() throws {
    var driver = try TestDriver(args: [
      "swiftc", "-explicit-module-build", "-always-rebuild-module-dependencies",
      "-module-name", "test", "-c", "test.swift",
    ])
    let json = ModuleDependenciesInputs.fastDependencyScannerOutput
    let semanticGraph = try JSONDecoder().decode(
      InterModuleDependencyGraph.self, from: Data(json.utf8))
    let rootGraph = try clangGraph(from: json, suffix: ".13")
    let interfaceGraph = try clangGraph(from: json, suffix: ".14")
    let planner = try ExplicitDependencyBuildPlanner(
      dependencyGraph: semanticGraph, toolchain: driver.toolchain)
    let jobs = try driver.unwrap { driver in
      try driver.configureClangCodeGenModulePlanner(dependencyGraph: rootGraph)
      try driver.configureClangCodeGenModulePlanner(
        dependencyGraph: rootGraph, forSwiftModule: "Swift")
      try driver.configureClangCodeGenModulePlanner(
        dependencyGraph: interfaceGraph, forSwiftModule: "SwiftOnoneSupport")
      return try driver.computeJobsForPhasedStandardBuild(
        explicitModulePlanner: planner).allJobs
    }
    #expect(jobs.filter { $0.kind == .generatePCM }.count == 6)
    for (name, suffix, absent) in [("Swift", ".13.pcm", ".14.pcm"),
                                 ("SwiftOnoneSupport", ".14.pcm", ".13.pcm")] {
      let job = try #require(jobs.first {
        $0.kind == .compileModuleFromInterface && $0.moduleName == name
      })
      #expect(job.commandLine.filter {
        $0 == .flag("-experimental-clang-codegen-module-file")
      }.count == 2)
      #expect(job.inputs.filter { $0.file.description.hasSuffix(suffix) }.count == 2)
      #expect(!job.inputs.contains { $0.file.description.hasSuffix(absent) })
      for input in job.inputs where input.type == .pcm {
        #expect(jobs.contains { $0.kind == .generatePCM && $0.outputs.contains(input) })
      }
      #expect(job.outputs.first?.file.description == "\(name).swiftmodule")
    }
  }

  @Test func sharedPCMJobsIgnoreOnlyDependencyInputOrdering() throws {
    let driver = try TestDriver(args: ["swiftc", "-c", "test.swift"])
    let graph = try JSONDecoder().decode(InterModuleDependencyGraph.self,
      from: Data(ModuleDependenciesInputs.fastDependencyScannerOutput.utf8))
    var planner = try ExplicitDependencyBuildPlanner(
      dependencyGraph: graph, toolchain: driver.toolchain)
    var first = try #require(
      planner.generateExplicitModuleDependenciesBuildJobs().first { $0.kind == .generatePCM })
    first.inputs = try ["A.pcm", "B.pcm"].map {
      TypedVirtualPath(file: try VirtualPath(path: $0).intern(), type: .pcm)
    }
    var second = first
    second.inputs.reverse()
    #expect(first != second)
    #expect(Driver.equivalentClangPCMJobs(first, second))

    second.commandLine.append(.flag("-DCHANGED=1"))
    #expect(!Driver.equivalentClangPCMJobs(first, second))
    second = first
    second.inputs.removeLast()
    #expect(!Driver.equivalentClangPCMJobs(first, second))
    second = first
    second.extraEnvironmentBlock["CHANGED"] = "1"
    #expect(!Driver.equivalentClangPCMJobs(first, second))
  }

  @Test(arguments: [false, true])
  func producerMapsUseEffectiveTargetsAndRejectAmbiguousContexts(conflicting: Bool) throws {
    var driver = try TestDriver(args: ["swiftc", "-c", "test.swift"])
    let json = ModuleDependenciesInputs.fastDependencyScannerOutput
    let semantic = try JSONDecoder().decode(
      InterModuleDependencyGraph.self, from: Data(json.utf8))
    let root = try clangGraph(from: json, suffix: ".13", commandLineSuffix: [
      "-Xcc", "-triple", "-Xcc", "arm64-apple-macosx13.0.0",
    ])
    let producer = try clangGraph(from: json, suffix: ".producer", commandLineSuffix: [
      "-Xcc", "-triple", "-Xcc", conflicting ? "arm64-apple-macosx13.0.0" : "arm64-apple-macosx14.0.0",
    ])
    do {
      try driver.unwrap { driver in
        try driver.configureClangCodeGenModulePlanner(dependencyGraph: root)
        try driver.configureClangCodeGenModulePlanner(
          dependencyGraph: producer, forSwiftModule: "Swift", targetContext: "arm64-apple-macosx14.0")
        var inputs: [TypedVirtualPath] = []
        var command: [Job.ArgTemplate] = []
        try driver.addClangProducerModuleDependencies(
          in: semantic, consumer: .swift("test"), inputs: &inputs, commandLine: &command)
        #expect(!conflicting)
        #expect(inputs.count == 4)
        #expect(command.contains(.joinedOptionAndPath(
          "arm64-apple-macosx14.0.0=SwiftShims=", try VirtualPath(path: "SwiftShims.producer.pcm"))))
        #expect(command.contains(.joinedOptionAndPath(
          "arm64-apple-macosx13.0.0=SwiftShims=", try VirtualPath(path: "SwiftShims.13.pcm"))))
      }
    } catch let error as PlanningError {
      #expect(conflicting)
      #expect(error.description.contains("cannot distinguish producer contexts"))
    }
  }

  @Test func equalTargetsWithDifferentNativeLanguageContextsStayDistinct() throws {
    var driver = try TestDriver(args: ["swiftc", "-c", "test.swift"])
    let json = ModuleDependenciesInputs.fastDependencyScannerOutput
    let sdkContext = "arm64-apple-macosx27.0.0||SDKLANG5"
    var semanticJSON = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    var modules = try #require(semanticJSON["modules"] as? [[String: Any]])
    var details = try #require(modules[1]["details"] as? [String: Any])
    var swiftDetails = try #require(details["swift"] as? [String: Any])
    swiftDetails["clangTargetContext"] = sdkContext
    swiftDetails["clangContextArguments"] = ["-cc1", "-triple", "arm64-apple-macosx27.0",
                                            "-D__swift__=51000", "-fmodules-cache-path=/sdk/cache"]
    details["swift"] = swiftDetails
    modules[1]["details"] = details
    semanticJSON["modules"] = modules
    let semantic = try JSONDecoder().decode(InterModuleDependencyGraph.self,
      from: JSONSerialization.data(withJSONObject: semanticJSON))
    let language5 = "arm64-apple-macosx15.0.0||LANG5"
    let language6 = "arm64-apple-macosx15.0.0||LANG6"
    let first = try clangGraph(from: json, suffix: ".lang5", nativeContext: language5,
                              nativeArguments: ["-cc1", "-D__swift__=51000"])
    let second = try clangGraph(from: json, suffix: ".lang6", nativeContext: language6,
                               nativeArguments: ["-cc1", "-D__swift__=60500"])
    try driver.unwrap { driver in
      try driver.configureClangCodeGenModulePlanner(dependencyGraph: first)
      try driver.configureClangCodeGenModulePlanner(
        dependencyGraph: second, forSwiftModule: "Swift", targetContext: "ignored")
      var inputs: [TypedVirtualPath] = []
      var command: [Job.ArgTemplate] = []
      try driver.addClangProducerModuleDependencies(
        in: semantic, consumer: .swift("test"), inputs: &inputs, commandLine: &command)
      #expect(inputs.count == 4)
      let sdkIndex = try #require(command.firstIndex(of: .flag("-experimental-clang-sdk-context")))
      #expect(command[sdkIndex + 1] == .flag(sdkContext))
      #expect(command.contains(.flag("\(sdkContext)=-D__swift__=51000")))
      #expect(!command.contains(.flag("\(sdkContext)=-fmodules-cache-path=/sdk/cache")))
      var interfaceCommand: [Job.ArgTemplate] = []
      try driver.addClangProducerModuleDependencies(
        in: semantic, consumer: .swift("Swift"), inputs: &inputs, commandLine: &interfaceCommand)
      #expect(interfaceCommand.contains(.flag(sdkContext)))
      #expect(interfaceCommand.contains(.flag("\(sdkContext)=-D__swift__=51000")))
      #expect(command.contains(.flag("\(language5)=-D__swift__=51000")))
      #expect(command.contains(.flag("\(language6)=-D__swift__=60500")))
      #expect(command.contains(.joinedOptionAndPath(
        "\(language5)=SwiftShims=", try VirtualPath(path: "SwiftShims.lang5.pcm"))))
      #expect(command.contains(.joinedOptionAndPath(
        "\(language6)=SwiftShims=", try VirtualPath(path: "SwiftShims.lang6.pcm"))))
    }
  }

  @Test func interfaceClangVariantOverridesAndPCHAreRejected() throws {
    try Driver.validateClangInterfaceContext([
      "-target", "arm64-apple-macosx15.0", "-target-variant", "arm64-apple-ios18.0-macabi",
    ])
    for flag in ["-clang-target-variant", "-import-objc-header", "-import-pch"] {
      #expect(throws: PlanningError.self) {
        try Driver.validateClangInterfaceContext([flag, "value"])
      }
    }
  }

  @Test func producerVariantIsPartOfItsContextIdentity() throws {
    let json = ModuleDependenciesInputs.fastDependencyScannerOutput
    let plain = try clangGraph(from: json, suffix: ".plain", commandLineSuffix: [
      "-Xcc", "-triple", "-Xcc", "arm64-apple-macosx15.0.0",
    ])
    let zippered = try clangGraph(from: json, suffix: ".zippered", commandLineSuffix: [
      "-Xcc", "-triple", "-Xcc", "arm64-apple-macosx15.0.0",
      "-Xcc", "-darwin-target-variant-triple", "-Xcc", "arm64-apple-ios18.0.0-macabi",
    ])
    #expect(try Driver.effectiveClangTarget(in: plain, fallback: "ignored") ==
      "arm64-apple-macosx15.0.0")
    #expect(try Driver.effectiveClangTarget(in: zippered, fallback: "ignored") ==
      "arm64-apple-macosx15.0.0|arm64-apple-ios18.0.0-macabi")
  }

  @Test func deploymentHeaderInvalidatesOnlyItsSwiftConsumers() throws {
    try withTemporaryDirectory { directory in
      func path(_ name: String) -> String { directory.appending(component: name).pathString }
      func write(_ name: String, time: TimeInterval) throws {
        let file = directory.appending(component: name)
        try localFileSystem.writeFileContents(file, bytes: "")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)],
                                              ofItemAtPath: file.pathString)
      }
      for name in ["Low.h", "Low.pcm", "A.swiftmodule", "B.swiftmodule", "C.swiftmodule"] {
        try write(name, time: name == "Low.h" ? 100 : name == "Low.pcm" ? 200 : 300)
      }
      let semanticJSON = """
        {"mainModuleName":"Main","modules":[
          {"swift":"Main"},{"modulePath":"Main.swiftmodule",
           "directDependencies":[{"swift":"A"},{"swift":"C"}],"details":{"swift":{}}},
          {"swift":"A"},{"modulePath":"\(path("A.swiftmodule"))",
           "directDependencies":[{"swift":"B"}],"details":{"swift":{}}},
          {"swift":"B"},{"modulePath":"\(path("B.swiftmodule"))",
           "directDependencies":[],"details":{"swift":{}}},
          {"swift":"C"},{"modulePath":"\(path("C.swiftmodule"))",
           "directDependencies":[],"details":{"swift":{}}}
        ]}
        """
      let lowJSON = """
        {"mainModuleName":"B","modules":[
          {"swift":"B"},{"modulePath":"B.swiftmodule",
           "directDependencies":[{"clang":"Low"}],"details":{"swift":{}}},
          {"clang":"Low"},{"modulePath":"\(path("Low.pcm"))",
           "sourceFiles":["\(path("Low.h"))"],"directDependencies":[],
           "details":{"clang":{"moduleMapPath":"module.modulemap","contextHash":"13","commandLine":[]}}}
        ]}
        """
      let semantic = try JSONDecoder().decode(
        InterModuleDependencyGraph.self, from: Data(semanticJSON.utf8))
      let low = try JSONDecoder().decode(
        InterModuleDependencyGraph.self, from: Data(lowJSON.utf8))
      var driver = try TestDriver(args: ["swiftc", "-c", "test.swift"])
      try driver.unwrap { driver in
        try driver.configureClangCodeGenModulePlanner(dependencyGraph: low, forSwiftModule: "B")
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic).isEmpty)
        try write("Low.h", time: 400)
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic) ==
          [.swift("Main"), .swift("A"), .swift("B")])
        // A rebuilt PCM still invalidates the stale Swift output on the next run.
        try write("Low.pcm", time: 500)
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic) ==
          [.swift("Main"), .swift("A"), .swift("B")])
        try write("B.swiftmodule", time: 600)
        try write("A.swiftmodule", time: 600)
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic).isEmpty)
      }
    }
  }

  @Test func binaryProducerContextsReachConsumersAndInvalidateTheirInterfaces() throws {
    try withTemporaryDirectory { directory in
      func path(_ name: String) -> String { directory.appending(component: name).pathString }
      func write(_ name: String, time: TimeInterval) throws {
        let file = directory.appending(component: name)
        try localFileSystem.writeFileContents(file, bytes: "")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)],
                                              ofItemAtPath: file.pathString)
      }
      for name in ["New.h", "New.pcm", "A.swiftmodule", "C.swiftmodule", "SDK.swiftmodule"] {
        try write(name, time: name == "New.h" ? 100 : name == "New.pcm" ? 200 : 300)
      }
      let semanticJSON = """
        {"mainModuleName":"Main","modules":[
          {"swift":"Main"},{"modulePath":"Main.swiftmodule",
           "directDependencies":[{"swift":"A"},{"swift":"C"}],"details":{"swift":{}}},
          {"swift":"A"},{"modulePath":"\(path("A.swiftmodule"))",
           "directDependencies":[{"swiftPrebuiltExternal":"SDK"}],"details":{"swift":{}}},
          {"swift":"C"},{"modulePath":"\(path("C.swiftmodule"))",
           "directDependencies":[],"details":{"swift":{}}},
          {"swiftPrebuiltExternal":"SDK"},{"modulePath":"\(path("SDK.swiftmodule"))",
           "directDependencies":[{"clang":"New"}],
           "details":{"swiftPrebuiltExternal":{"compiledModulePath":"\(path("SDK.swiftmodule"))",
             "clangTargetContexts":["arm64-apple-macosx15.0"],
             "clangContextArguments":["-Xcc","-DBINARY=1"]}}},
          {"clang":"New"},{"modulePath":"semantic.pcm","directDependencies":[],
           "details":{"clang":{"moduleMapPath":"module.modulemap","contextHash":"high","commandLine":[]}}}
        ]}
        """
      let producerJSON = """
        {"mainModuleName":"Main","modules":[
          {"swift":"Main"},{"modulePath":"Main.swiftmodule",
           "directDependencies":[{"clang":"New"}],"details":{"swift":{}}},
          {"clang":"New"},{"modulePath":"\(path("New.pcm"))",
           "sourceFiles":["\(path("New.h"))"],"directDependencies":[],
           "details":{"clang":{"moduleMapPath":"module.modulemap","contextHash":"15",
             "commandLine":["-Xcc","-triple","-Xcc","arm64-apple-macosx15.0.0"]}}}
        ]}
        """
      let semantic = try JSONDecoder().decode(
        InterModuleDependencyGraph.self, from: Data(semanticJSON.utf8))
      let producer = try JSONDecoder().decode(
        InterModuleDependencyGraph.self, from: Data(producerJSON.utf8))
      var driver = try TestDriver(args: ["swiftc", "-c", "test.swift"])
      try driver.unwrap { driver in
        try driver.configureClangBinaryModulePlanner(
          dependencyGraph: producer, forSwiftModule: "SDK",
          targetContext: "arm64-apple-macosx15.0")
        var inputs: [TypedVirtualPath] = []
        var command: [Job.ArgTemplate] = []
        try driver.addClangProducerModuleDependencies(
          in: semantic, consumer: .swift("A"), inputs: &inputs, commandLine: &command)
        #expect(command == [
          .flag("-experimental-clang-producer-module-file"),
          .joinedOptionAndPath("arm64-apple-macosx15.0.0=New=", try VirtualPath(path: path("New.pcm"))),
        ])
        #expect(inputs.count == 1)
        var unrelated: [Job.ArgTemplate] = []
        try driver.addClangProducerModuleDependencies(
          in: semantic, consumer: .swift("C"), inputs: &inputs, commandLine: &unrelated)
        #expect(unrelated.isEmpty)
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic).isEmpty)
        try write("New.h", time: 400)
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic) ==
          [.swift("Main"), .swift("A")])
        try write("New.pcm", time: 500)
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic) ==
          [.swift("Main"), .swift("A")])
        try write("A.swiftmodule", time: 600)
        #expect(try driver.clangContextInvalidatedSwiftModules(in: semantic).isEmpty)
      }
    }
  }

  @Test func rejectsSwiftDependenciesInCodeGenGraph() throws {
    var driver = try TestDriver(args: ["swiftc", "-c", "test.swift"])
    let graph = try JSONDecoder().decode(
      InterModuleDependencyGraph.self,
      from: Data(ModuleDependenciesInputs.fastDependencyScannerOutput.utf8))
    #expect(throws: PlanningError.self) {
      try driver.unwrap { driver in
        try driver.configureClangCodeGenModulePlanner(dependencyGraph: graph)
      }
    }
  }

  @Test(arguments: [
    (["-no-explicit-module-build"], "requires '-explicit-module-build'"),
    (["-explicit-module-build", "-incremental"], "does not support incremental compilation"),
    (["-explicit-module-build", "-target-variant", "arm64-apple-ios15.0-macabi"],
     "does not support target variants"),
    (["-explicit-module-build", "-import-bridging-header", "test.h"],
     "does not support bridging headers or PCH files"),
  ])
  func unsupportedConfigurations(options: [String], message: String) async throws {
    var driver = try TestDriver(args: [
      "swiftc", "-experimental-clang-codegen-target-context", "-c", "test.swift",
    ] + options)
    do {
      _ = try await driver.planBuild()
      Issue.record("Expected the experimental configuration to be rejected")
    } catch let error as PlanningError {
      #expect(error.description.contains(message))
    }
  }
}
