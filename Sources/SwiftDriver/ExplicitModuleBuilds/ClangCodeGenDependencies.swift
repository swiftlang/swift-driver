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

import SwiftOptions

extension Driver {
  private var hasClangTargetContextPlanners: Bool {
    clangCodeGenModulePlanner != nil || !clangInterfaceModulePlanners.isEmpty ||
      !clangBinaryModulePlanners.isEmpty
  }

  mutating func validateClangCodeGenTargetContext() throws {
    guard parsedOptions.contains(.driverExperimentalClangCodegenTargetContext) else {
      return
    }
    func unsupported(_ reason: String) throws -> Never {
      throw PlanningError.clangCodeGenTargetContextUnsupported(reason)
    }
    guard parsedOptions.contains(.driverExplicitModuleBuild) else {
      try unsupported("requires '-explicit-module-build'")
    }
    guard compilerMode.isStandardCompilationForPlanning,
          !parsedOptions.contains(.scanDependencies) else {
      try unsupported("requires a standard compilation")
    }
    guard !parsedOptions.contains(.targetVariant),
          !parsedOptions.contains(.clangTargetVariant),
          !parsedOptions.contains(.experimentalEmitVariantModule) else {
      try unsupported("does not support target variants")
    }
    guard !enableCaching, cas == nil,
          !parsedOptions.contains(.casPath),
          !parsedOptions.contains(.scannerCasFs),
          !parsedOptions.contains(.clangIncludeTreeRoot),
          !parsedOptions.contains(.clangIncludeTreeFilelist) else {
      try unsupported("does not support CAS caching")
    }
    guard !parsedOptions.contains(.incremental) else {
      try unsupported("does not support incremental compilation")
    }
    guard !parsedOptions.contains(.importBridgingHeader),
          !parsedOptions.contains(.internalImportBridgingHeader),
          !parsedOptions.contains(.importPch),
          !parsedOptions.contains(.internalImportPch) else {
      try unsupported("does not support bridging headers or PCH files")
    }
    for flag in ["-experimental-clang-codegen-dependency",
                 "-experimental-clang-codegen-module-file",
                 "-experimental-clang-target-context",
                 "-experimental-clang-context-argument",
                 "-experimental-clang-producer-module-file",
                 "-experimental-clang-producer-context-argument",
                 "-experimental-clang-sdk-context"] {
      guard Self.isOptionFound(flag, allOpts: supportedFrontendFlags) else {
        try unsupported("requires frontend support for '\(flag)'")
      }
    }
  }

  mutating func scanClangCodeGenDependencies(of semanticGraph: InterModuleDependencyGraph) throws {
    try Self.validateNativeClangContext(in: semanticGraph)
    let rootJob = try dependencyScanningJob()
    let root: ModuleDependencyId = .swift(semanticGraph.mainModuleName)
    let reachable = try semanticGraph.computeTransitiveClosure()[root] ?? []
    for consumer in [root] + reachable.sorted(by: { $0.moduleName < $1.moduleName }) {
      guard case .swift(let name) = consumer else { continue }
      let names = try Self.clangCodeGenDependencyRoots(in: semanticGraph, from: consumer)
      // An empty list would request an ordinary Swift scan.
      guard !names.isEmpty else { continue }
      var job = rootJob
      let target: String
      if consumer == root {
        target = targetTriple.triple
      } else {
        let details = try semanticGraph.swiftModuleDetails(of: consumer)
        guard let command = details.commandLine,
              let descriptor = Self.clangTargetContext(in: command),
              let interface = details.moduleInterfacePath else {
          throw PlanningError.clangCodeGenTargetContextUnsupported(
            "missing scanner target context for Swift module '\(name)'")
        }
        try Self.validateClangInterfaceContext(command)
        target = descriptor
        job.commandLine = Self.clangInterfaceScanCommand(
          command, interfacePath: VirtualPath.lookup(interface.path).description,
          sourceInputs: inputFiles.filter { $0.type == .swift }.map { .path($0.file) },
          rootScanCommand: rootJob.commandLine)
        job.moduleName = name
      }
      job.commandLine = Self.clangCodeGenScanCommand(
        job.commandLine, target: target, moduleNames: names)

      // Scanner caches cannot share module-name entries across these contexts.
      let oracle = InterModuleDependencyOracle()
      if let scanner = swiftScanLibInstance {
        try oracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanner.path)
      }
      let graph = try performDependencyScan(scannerJob: job, oracle: oracle)
      try Self.validateNativeClangContext(in: graph)
      for name in names where graph.modules[.clang(name)] == nil {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "could not scan Clang module '\(name)' for target '\(target)'")
      }
      try configureClangCodeGenModulePlanner(
        dependencyGraph: graph, forSwiftModule: consumer == root ? nil : name,
        targetContext: target)
    }

    for consumer in reachable.sorted(by: { $0.moduleName < $1.moduleName }) {
      guard case .swiftPrebuiltExternal(let name) = consumer,
            case .swiftPrebuiltExternal(let details) =
              try semanticGraph.moduleInfo(of: consumer).details else { continue }
      let names = try Self.clangCodeGenDependencyRoots(in: semanticGraph, from: consumer)
      guard !names.isEmpty, let targets = details.clangTargetContexts,
            !targets.isEmpty else { continue }
      guard let arguments = details.clangContextArguments, !arguments.isEmpty else {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "missing saved Clang configuration for binary Swift module '\(name)'")
      }
      let catalog = try Self.clangContextArgumentCatalog(arguments)
      let rootDetails = try semanticGraph.swiftModuleDetails(of: root)
      guard let rootArguments = rootDetails.clangContextArguments,
            let scannerModuleCachePath = Self.clangModuleCachePath(in: rootArguments) else {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "dependency scanner did not export its resolved Clang module cache path")
      }
      for target in Set(targets).sorted() {
        guard let savedArguments = catalog[target], !savedArguments.isEmpty else {
          throw PlanningError.clangCodeGenTargetContextUnsupported(
            "missing saved arguments for producer context '\(target)'")
        }
        var job = rootJob
        job.commandLine = try Self.clangBinaryScanCommand(
          rootJob.commandLine, contextArguments: savedArguments, target: target,
          moduleNames: names, scannerModuleCachePath: scannerModuleCachePath)
        let oracle = InterModuleDependencyOracle()
        if let scanner = swiftScanLibInstance {
          try oracle.verifyOrCreateScannerInstance(swiftScanLibPath: scanner.path)
        }
        let graph = try performDependencyScan(scannerJob: job, oracle: oracle)
        try Self.validateNativeClangContext(in: graph, expected: target)
        for module in names where graph.modules[.clang(module)] == nil {
          throw PlanningError.clangCodeGenTargetContextUnsupported(
            "could not scan Clang module '\(module)' for binary producer '\(name)' at '\(target)'")
        }
        try configureClangBinaryModulePlanner(
          dependencyGraph: graph, forSwiftModule: name, targetContext: target)
      }
    }
  }

  /// A binary carries the complete cc1 arguments of every referenced
  /// invocation, including the -cc1 marker. Preserve ordering and '=' within
  /// individual arguments.
  @_spi(Testing) public static func clangContextArgumentCatalog(
    _ entries: [String]
  ) throws -> [String: [String]] {
    var result: [String: [String]] = [:]
    for entry in entries {
      guard let separator = entry.firstIndex(of: "="),
            separator != entry.startIndex else {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "malformed saved Clang context argument")
      }
      let context = String(entry[..<separator])
      let argument = String(entry[entry.index(after: separator)...])
      guard !argument.isEmpty else {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "empty saved Clang context argument")
      }
      _ = try nativeClangContextComponents(context)
      result[context, default: []].append(argument)
    }
    return result
  }

  /// Module files and cache destinations are build artifacts, not producer
  /// semantics. Targets are reconstructed from the native descriptor. Keep
  /// AST-affecting arguments in order, including defines and search paths.
  @_spi(Testing) public static func clangContextSemanticArguments(
    _ arguments: [String]
  ) -> [String] {
    let values = ["-target": 1, "--target": 1, "-triple": 1,
                  "-darwin-target-variant": 1, "-darwin-target-variant-triple": 1,
                  "-fmodule-file": 1,
                  "-fmodule-file-cache-key": 2, "-fmodules-cache-path": 1,
                  "-o": 1]
    // These Objective-C stubs affect emitted calls only. Clang marks both
    // options benign for AST identity, and supplemental contexts never emit
    // calls. The root compilation retains its original emission policy.
    let flags: Set<String> = [
      "-fno-implicit-modules", "-fno-implicit-module-maps", "-fimplicit-module-maps",
      "-fobjc-msgsend-selector-stubs", "-fno-objc-msgsend-selector-stubs",
      "-fobjc-msgsend-class-selector-stubs", "-fno-objc-msgsend-class-selector-stubs",
    ]
    let joined = ["-target=", "--target=", "-triple=",
                  "-darwin-target-variant=", "-darwin-target-variant-triple=",
                  "-fmodule-file=", "-fmodule-file-cache-key=",
                  "-fmodules-cache-path="]
    var result: [String] = []
    var index = 0
    while index < arguments.count {
      let isXclang = arguments[index] == "-Xclang"
      let flagIndex = index + (isXclang ? 1 : 0)
      guard flagIndex < arguments.count else {
        result.append(arguments[index])
        break
      }
      let flag = arguments[flagIndex]
      if let count = values[flag] {
        index = flagIndex + 1
        for _ in 0..<count {
          if isXclang, index < arguments.count, arguments[index] == "-Xclang" { index += 1 }
          if index < arguments.count { index += 1 }
        }
        continue
      }
      if flags.contains(flag) || joined.contains(where: flag.hasPrefix) {
        index = flagIndex + 1
        continue
      }
      result.append(arguments[index])
      index += 1
    }
    return result
  }

  private static func nativeClangContextComponents(_ context: String)
    throws -> (primary: String, variant: String?) {
    let parts = context.split(separator: "|", omittingEmptySubsequences: false)
    guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty else {
      throw PlanningError.clangCodeGenTargetContextUnsupported(
        "malformed native Clang context '\(context)'")
    }
    return (String(parts[0]), parts[1].isEmpty ? nil : String(parts[1]))
  }

  private static func validateNativeClangContext(
    in graph: InterModuleDependencyGraph, expected: String? = nil
  ) throws {
    let details = try graph.swiftModuleDetails(of: .swift(graph.mainModuleName))
    guard let context = details.clangTargetContext,
          let arguments = details.clangContextArguments,
          arguments.first == "-cc1" else {
      throw PlanningError.clangCodeGenTargetContextUnsupported(
        "dependency scanner did not export its native Clang cc1 context")
    }
    _ = try nativeClangContextComponents(context)
    if let expected = expected, context != expected {
      throw PlanningError.clangCodeGenTargetContextUnsupported(
        "saved Clang context '\(expected)' reconstructed as '\(context)'")
    }
  }

  /// Use the scanner's resolved cache path, including its frontend default
  /// when the driver invocation did not specify -module-cache-path.
  @_spi(Testing) public static func clangModuleCachePath(in arguments: [String]) -> String? {
    var result: String?
    for index in arguments.indices {
      if arguments[index] == "-fmodules-cache-path", index + 1 < arguments.count {
        result = arguments[index + 1]
      } else if arguments[index].hasPrefix("-fmodules-cache-path=") {
        result = String(arguments[index].dropFirst("-fmodules-cache-path=".count))
      }
    }
    return result.flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Replace the consumer's Clang options with the exact producer invocation.
  /// The native override prevents duplicate importer defaults from changing
  /// macro definitions, header lookup or the Clang context hash.
  @_spi(Testing) public static func clangBinaryScanCommand(
    _ command: [Job.ArgTemplate], contextArguments: [String],
    target: String, moduleNames: [String], scannerModuleCachePath: String
  ) throws -> [Job.ArgTemplate] {
    let (primary, variant) = try nativeClangContextComponents(target)
    let replacedValues: Set<String> = [
      "-Xcc", "-I", "-Isystem", "-F", "-Fsystem", "-sdk", "-resource-dir",
      "-vfsoverlay", "-clang-target", "-clang-target-variant", "-target-variant",
      "-experimental-clang-context-argument",
      "-experimental-clang-producer-context-argument",
    ]
    var result: [Job.ArgTemplate] = []
    var index = 0
    while index < command.count {
      if case .flag(let flag) = command[index], replacedValues.contains(flag) {
        index += 2
        continue
      }
      result.append(command[index])
      index += 1
    }
    guard contextArguments.first == "-cc1" else {
      throw PlanningError.clangCodeGenTargetContextUnsupported(
        "missing Clang cc1 snapshot in saved producer configuration")
    }
    for argument in clangContextSemanticArguments(contextArguments) {
      result.appendFlags("-experimental-clang-context-argument", argument)
    }
    // Saved explicit compilations disable discovery and may omit the positive
    // module-map flag entirely. A named scan needs discovery and a cache path
    // after its prebuilt inputs have been removed. Neither affects the native
    // context hash; the saved producer catalog remains unchanged.
    result.appendFlags("-experimental-clang-context-argument", "-fimplicit-module-maps")
    result.appendFlags("-experimental-clang-context-argument",
                       "-fmodules-cache-path=\(scannerModuleCachePath)")
    if let variant = variant { result.appendFlags("-target-variant", variant) }
    return clangCodeGenScanCommand(result, target: primary, moduleNames: moduleNames)
  }

  /// The scanner exports the parsed interface target after applying its flags.
  @_spi(Testing) public static func clangTargetContext(in command: [String]) -> String? {
    var result: String?
    var index = 0
    while index < command.count {
      if command[index] == "-Xcc" {
        index += 2
        continue
      }
      if command[index] == "-experimental-clang-target-context", index + 1 < command.count {
        result = command[index + 1]
        index += 2
      } else {
        index += 1
      }
    }
    return result
  }

  @_spi(Testing) public static func validateClangInterfaceContext(_ command: [String]) throws {
    let unsupported: Set<String> = [
      "-clang-target-variant", "-import-objc-header", "-import-pch",
      "-import-objc-header-materialize", "-import-pch-materialize", "-cache-compile-job",
      "-cas-path", "-clang-include-tree-root", "-clang-include-tree-filelist",
    ]
    var index = 0
    while index < command.count {
      if command[index] == "-Xcc" {
        index += 2
        continue
      }
      if unsupported.contains(command[index]) {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "does not support '\(command[index])' in a Swift interface context")
      }
      index += 1
    }
  }

  @_spi(Testing) public static func clangInterfaceScanCommand(
    _ command: [String], interfacePath: String, sourceInputs: [Job.ArgTemplate],
    rootScanCommand: [Job.ArgTemplate] = []
  ) -> [Job.ArgTemplate] {
    var result: [Job.ArgTemplate] = []
    var index = 0
    while index < command.count {
      let arg = command[index]
      if arg == "-Xcc", index + 1 < command.count {
        result.appendFlags(arg, command[index + 1])
        index += 2
      } else if arg == "-compile-module-from-interface" {
        result.appendFlag("-scan-dependencies")
        index += 1
      } else if arg == "-o" || arg == "-candidate-module-file" {
        index += 2
      } else if arg == interfacePath || arg == "-explicit-interface-module-build" ||
                  arg == "-disable-implicit-swift-modules" {
        index += 1
      } else {
        result.appendFlag(arg)
        index += 1
      }
    }
    // Named Clang scans do not parse the Swift source, but frontend setup still
    // expects an input. Reuse the source invocation's inputs, not the interface.
    result.append(contentsOf: sourceInputs)
    // Interface build commands do not carry scanner output locations. Reuse
    // the user's destinations so equal scanner context hashes share one PCM.
    index = 0
    while index < rootScanCommand.count {
      if rootScanCommand[index] == .flag("-Xcc") {
        index += 2
        continue
      }
      if rootScanCommand[index] == .flag("-module-cache-path") ||
          rootScanCommand[index] == .flag("-sdk-module-cache-path"),
         index + 1 < rootScanCommand.count {
        result.append(contentsOf: rootScanCommand[index...index + 1])
        index += 2
      } else {
        index += 1
      }
    }
    return result
  }

  /// Clang-to-Clang dependencies must be discovered again at the deployment
  /// target. A dependency selected by the SDK's preprocessor may not exist there.
  @_spi(Testing) public static func clangCodeGenDependencyRoots(
    in graph: InterModuleDependencyGraph, from consumer: ModuleDependencyId? = nil
  ) throws -> [String] {
    let main: ModuleDependencyId = consumer ?? .swift(graph.mainModuleName)
    var reachable = try graph.computeTransitiveClosure()[main] ?? []
    reachable.insert(main)
    var names: Set<String> = []
    for id in reachable {
      if case .clang = id { continue }
      let info = try graph.moduleInfo(of: id)
      for dependency in info.allDependencies +
          (info.bridgingHeaderModuleDependencies ?? []) {
        if case .clang(let name) = dependency {
          names.insert(name)
        }
      }
    }
    return names.sorted()
  }

  @_spi(Testing) public mutating func configureClangCodeGenModulePlanner(
    dependencyGraph: InterModuleDependencyGraph, forSwiftModule moduleName: String? = nil,
    targetContext: String? = nil
  ) throws {
    let planner = try makeClangContextPlanner(dependencyGraph)
    if let moduleName = moduleName {
      clangInterfaceModulePlanners[moduleName] = planner
      if let target = targetContext {
        clangInterfaceTargetContexts[moduleName] = try Self.effectiveClangTarget(
          in: dependencyGraph, fallback: target)
      }
    } else {
      clangCodeGenModulePlanner = planner
    }
  }

  @_spi(Testing) public mutating func configureClangBinaryModulePlanner(
    dependencyGraph: InterModuleDependencyGraph, forSwiftModule moduleName: String,
    targetContext: String
  ) throws {
    let target = try Self.effectiveClangTarget(in: dependencyGraph, fallback: targetContext)
    if let existing = clangBinaryModulePlanners[moduleName]?[target] {
      let previous = existing.dependencyGraph.modules
      guard previous.count == dependencyGraph.modules.count,
            dependencyGraph.modules.allSatisfy({
              previous[$0.key]?.modulePath == $0.value.modulePath
            }) else {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "cannot distinguish binary producer contexts for target '\(target)'")
      }
      return
    }
    clangBinaryModulePlanners[moduleName, default: [:]][target] =
      try makeClangContextPlanner(dependencyGraph)
  }

  private func makeClangContextPlanner(_ dependencyGraph: InterModuleDependencyGraph)
    throws -> ExplicitDependencyBuildPlanner {
    for id in dependencyGraph.modules.keys {
      switch id {
      case .clang:
        break
      case .swift(let name) where name == dependencyGraph.mainModuleName:
        break
      default:
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "received a non-Clang dependency in its code-generation graph")
      }
    }
    return try ExplicitDependencyBuildPlanner(
      dependencyGraph: dependencyGraph, toolchain: toolchain,
      integratedDriver: integratedDriver)
  }

  /// Change only the Clang target of the scan. The Swift target and the normal
  /// semantic graph are retained for importing SDK interfaces.
  @_spi(Testing) public static func clangCodeGenScanCommand(
    _ command: [Job.ArgTemplate], target: String, moduleNames: [String]
  ) -> [Job.ArgTemplate] {
    let flagsWithValues: [String: Int] = [
      "-clang-target": 1, "-clang-target-variant": 1,
      "-dependency-scan-cache-path": 1,
      "-explicit-swift-module-map-file": 1, "-module-cache-key": 1,
      "-clang-include-tree-root": 1, "-clang-include-tree-filelist": 1,
      "-fmodule-file": 1, "-fmodule-file-cache-key": 2,
      "-experimental-clang-codegen-module-file": 1,
      "-experimental-clang-producer-module-file": 1,
      "-experimental-clang-producer-context-argument": 1,
      "-experimental-clang-sdk-context": 1,
    ]
    let flagsWithoutValues: Set<String> = [
      "-load-dependency-scan-cache", "-validate-prior-dependency-scan-cache",
      "-serialize-dependency-scan-cache", "-direct-clang-cc1-module-build",
      "-fno-implicit-modules", "-fno-implicit-module-maps",
    ]
    var result: [Job.ArgTemplate] = []
    var index = 0
    while index < command.count {
      if command[index] == .flag("-experimental-clang-context-argument"),
         index + 1 < command.count {
        result.append(contentsOf: command[index...index + 1])
        index += 2
        continue
      }
      let isXcc = command[index] == .flag("-Xcc")
      let flagIndex = index + (isXcc ? 1 : 0)
      guard flagIndex < command.count,
            case .flag(let flag) = command[flagIndex] else {
        result.append(command[index])
        index += 1
        continue
      }
      if let valueCount = flagsWithValues[flag] {
        index = flagIndex + 1
        for _ in 0..<valueCount {
          if isXcc, index < command.count, command[index] == .flag("-Xcc") {
            index += 1
          }
          if index < command.count { index += 1 }
        }
        continue
      }
      if flagsWithoutValues.contains(flag) ||
           flag.hasPrefix("-fmodule-file=") ||
           flag.hasPrefix("-fmodule-file-cache-key=") ||
           flag.hasPrefix("-swift-module-file=") {
        index = flagIndex + 1
        continue
      }
      result.append(command[index])
      index += 1
    }
    result.appendFlag("-clang-target")
    result.appendFlag(target)
    for name in moduleNames {
      result.appendFlag("-experimental-clang-codegen-dependency")
      result.appendFlag(name)
    }
    return result
  }

  @_spi(Testing) public func addClangCodeGenModuleDependencies(
    inputs: inout [TypedVirtualPath], commandLine: inout [Job.ArgTemplate],
    forSwiftModule moduleName: String? = nil
  ) {
    let selected = moduleName.flatMap { clangInterfaceModulePlanners[$0] }
    guard let planner = moduleName == nil ? clangCodeGenModulePlanner : selected else { return }
    for id in planner.dependencyGraph.modules.keys.sorted(by: {
      $0.moduleName < $1.moduleName
    }) {
      guard case .clang(let name) = id,
            let info = planner.dependencyGraph.modules[id] else { continue }
      let path = info.modulePath.path
      inputs.append(TypedVirtualPath(file: path, type: .pcm))
      commandLine.appendFlag("-experimental-clang-codegen-module-file")
      commandLine.append(.joinedOptionAndPath("\(name)=", VirtualPath.lookup(path)))
    }
  }

  /// Clang can normalize or raise the Swift target (for example arm64 macOS
  /// deployment before 11). The serialized producer records this effective
  /// cc1 target, so use the scanner's value rather than guessing that mapping.
  @_spi(Testing) public static func effectiveClangTarget(
    in graph: InterModuleDependencyGraph, fallback: String
  ) throws -> String {
    if let details = try? graph.swiftModuleDetails(of: .swift(graph.mainModuleName)),
       let context = details.clangTargetContext {
      return context
    }
    var targets: Set<String> = []
    for (_, info) in graph.modules {
      guard case .clang(let details) = info.details else { continue }
      let args = details.commandLine.filter { $0 != "-Xcc" }
      if let index = args.lastIndex(of: "-triple"), index + 1 < args.count {
        var target = args[index + 1]
        if let variant = args.lastIndex(of: "-darwin-target-variant-triple"),
           variant + 1 < args.count {
          target += "|" + args[variant + 1]
        }
        targets.insert(target)
      }
    }
    guard targets.count <= 1 else {
      throw PlanningError.clangCodeGenTargetContextUnsupported(
        "received inconsistent effective Clang targets in a deployment graph")
    }
    return targets.first ?? fallback
  }

  /// Supply the Clang contexts of reachable Swift producers for cross-reference
  /// validation. Each key includes Clang's native invocation hash, so equal
  /// target triples with different language or macro settings stay distinct.
  @_spi(Testing) public func addClangProducerModuleDependencies(
    in semanticGraph: InterModuleDependencyGraph, consumer: ModuleDependencyId,
    inputs: inout [TypedVirtualPath], commandLine: inout [Job.ArgTemplate]
  ) throws {
    guard hasClangTargetContextPlanners else { return }
    var contexts: [String: [String: VirtualPath.Handle]] = [:]
    var arguments: [String: [String]] = [:]
    let semanticDetails = try semanticGraph.swiftModuleDetails(
      of: .swift(semanticGraph.mainModuleName))
    if let context = semanticDetails.clangTargetContext,
       let raw = semanticDetails.clangContextArguments {
      commandLine.appendFlags("-experimental-clang-sdk-context", context)
      arguments[context] = Self.clangContextSemanticArguments(raw)
    }
    func register(_ planner: ExplicitDependencyBuildPlanner, target: String) throws {
      let details = try planner.dependencyGraph.swiftModuleDetails(
        of: .swift(planner.dependencyGraph.mainModuleName))
      if let raw = details.clangContextArguments {
        let saved = Self.clangContextSemanticArguments(raw)
        if let existing = arguments[target], existing != saved {
          throw PlanningError.clangCodeGenTargetContextUnsupported(
            "conflicting native arguments for Clang context '\(target)'")
        }
        arguments[target] = saved
      }
      for (id, info) in planner.dependencyGraph.modules {
        guard case .clang(let name) = id else { continue }
        if let previous = contexts[target]?[name], previous != info.modulePath.path {
          throw PlanningError.clangCodeGenTargetContextUnsupported(
            "cannot distinguish producer contexts for target '\(target)' and Clang module '\(name)': " +
              "'\(VirtualPath.lookup(previous))' and '\(VirtualPath.lookup(info.modulePath.path))'")
        }
        contexts[target, default: [:]][name] = info.modulePath.path
      }
    }
    for (planner, target) in try clangProducerContexts(in: semanticGraph, consumer: consumer) {
      if let target = target { try register(planner, target: target) }
    }
    for target in arguments.keys.sorted() {
      for argument in arguments[target]! {
        commandLine.appendFlags("-experimental-clang-producer-context-argument",
                                "\(target)=\(argument)")
      }
    }
    for target in contexts.keys.sorted() {
      for (name, path) in contexts[target]!.sorted(by: { $0.key < $1.key }) {
        let input = TypedVirtualPath(file: path, type: .pcm)
        if !inputs.contains(input) { inputs.append(input) }
        commandLine.appendFlag("-experimental-clang-producer-module-file")
        commandLine.append(.joinedOptionAndPath("\(target)=\(name)=", VirtualPath.lookup(path)))
      }
    }
  }

  private func clangProducerContexts(
    in semanticGraph: InterModuleDependencyGraph, consumer: ModuleDependencyId
  ) throws -> [(ExplicitDependencyBuildPlanner, String?)] {
    guard hasClangTargetContextPlanners else { return [] }
    var reachable = try semanticGraph.computeTransitiveClosure()[consumer] ?? []
    reachable.insert(consumer)
    var result: [(ExplicitDependencyBuildPlanner, String?)] = []
    for dependency in reachable.sorted(by: { $0.moduleName < $1.moduleName }) {
      switch dependency {
      case .swift(let name):
        if let planner = clangInterfaceModulePlanners[name] {
          result.append((planner, clangInterfaceTargetContexts[name]))
        } else if dependency == .swift(semanticGraph.mainModuleName),
                  let planner = clangCodeGenModulePlanner {
          result.append((planner, try Self.effectiveClangTarget(
            in: planner.dependencyGraph, fallback: targetTriple.triple)))
        }
      case .swiftPrebuiltExternal(let name):
        for (target, planner) in (clangBinaryModulePlanners[name] ?? [:])
          .sorted(by: { $0.key < $1.key }) {
          result.append((planner, target))
        }
      default:
        break
      }
    }
    return result
  }

  /// A changed deployment-only header must invalidate the Swift interface that
  /// folded its declarations, even when the SDK dependency graph is unchanged.
  @_spi(Testing) public func clangContextInvalidatedSwiftModules(
    in semanticGraph: InterModuleDependencyGraph
  ) throws -> Set<ModuleDependencyId> {
    guard hasClangTargetContextPlanners else { return [] }
    var invalidated: Set<ModuleDependencyId> = []
    for (id, info) in semanticGraph.modules {
      guard case .swift = id, id != .swift(semanticGraph.mainModuleName) else { continue }
      let contexts = try clangProducerContexts(in: semanticGraph, consumer: id)
      guard !contexts.isEmpty else { continue }
      guard let outputTime = try? fileSystem.lastModificationTime(
              for: VirtualPath.lookup(info.modulePath.path)) else {
        invalidated.insert(id)
        continue
      }
      for (planner, _) in contexts {
        let stale = try planner.dependencyGraph.computeInvalidatedModuleDependencies(
          fileSystem: fileSystem, cas: nil, forRebuild: true)
        if !stale.isEmpty {
          invalidated.insert(id)
          break
        }
        for (dependency, details) in planner.dependencyGraph.modules {
          guard case .clang = dependency else { continue }
          guard let pcmTime = try? fileSystem.lastModificationTime(
            for: VirtualPath.lookup(details.modulePath.path)), pcmTime <= outputTime else {
            invalidated.insert(id)
            break
          }
        }
        if invalidated.contains(id) { break }
      }
    }
    // Propagate to Swift consumers without merging the distinct Clang graphs.
    var changed = true
    while changed {
      changed = false
      for (id, info) in semanticGraph.modules where !invalidated.contains(id) {
        if info.allDependencies.contains(where: invalidated.contains) {
          invalidated.insert(id)
          changed = true
        }
      }
    }
    return invalidated
  }

  mutating func addClangCodeGenDependencyJobs(semanticJobs: [Job],
                                              addJob: (Job) -> Void) throws {
    guard hasClangTargetContextPlanners else { return }
    var planners = clangInterfaceModulePlanners.sorted { $0.key < $1.key }.map(\.value)
    planners += clangBinaryModulePlanners.sorted { $0.key < $1.key }.flatMap {
      $0.value.sorted { $0.key < $1.key }.map(\.value)
    }
    if let root = clangCodeGenModulePlanner { planners.insert(root, at: 0) }
    var acceptedJobs = semanticJobs
    for var planner in planners {
      var jobs = try planner.generateExplicitModuleDependenciesBuildJobs()
      guard jobs.allSatisfy({ $0.kind == .generatePCM }) else {
        throw PlanningError.clangCodeGenTargetContextUnsupported(
          "received a non-PCM build job in its deployment graph")
      }
      // Sharing preserves the complete job, apart from the ordering of input
      // dependencies collected from sets by the explicit module planner.
      jobs = try jobs.filter { job in
        let overlapping = acceptedJobs.filter {
          !Set($0.outputs).isDisjoint(with: job.outputs)
        }
        if overlapping.isEmpty {
          acceptedJobs.append(job)
          return true
        }
        guard overlapping.count == 1,
              Self.equivalentClangPCMJobs(overlapping[0], job) else {
          throw PlanningError.clangCodeGenTargetContextUnsupported(
            "received conflicting PCM output paths from its dependency scans")
        }
        return false
      }
      if !parsedOptions.contains(.alwaysRebuildModuleDependencies) {
        jobs = try planner.filterMandatoryModuleDependencyCompileJobs(
          jobs, fileSystem: fileSystem, cas: nil, reporter: nil)
      }
      jobs.forEach(addJob)
    }
  }

  @_spi(Testing) public static func equivalentClangPCMJobs(_ first: Job, _ second: Job) -> Bool {
    guard first.kind == .generatePCM, second.kind == .generatePCM else { return false }
    func orderedInputs(_ job: Job) -> Job {
      var result = job
      result.inputs.sort {
        ($0.file.description, $0.type.rawValue) < ($1.file.description, $1.type.rawValue)
      }
      return result
    }
    return orderedInputs(first) == orderedInputs(second)
  }
}
