//===--------------- ExplicitDependencyBuildPlanner.swift ---------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.SHA256
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import struct Foundation.Data
import class Foundation.JSONEncoder

/// Details about an external target, including the path to its .swiftmodule file
/// and whether it is a framework.
public struct ExternalTargetModuleDetails {
  public init(path: AbsolutePath, isFramework: Bool) {
    self.path = path
    self.isFramework = isFramework
  }
  let path: AbsolutePath
  let isFramework: Bool
}

/// A chained bridging header file.
public struct ChainedBridgingHeaderFile {
  let path: String
  let content: String
}

// Deprecated
public typealias ExternalTargetModuleDetailsMap = [ModuleDependencyId: ExternalTargetModuleDetails]

/// In Explicit Module Build mode, this planner is responsible for generating and providing
/// build jobs for all module dependencies and providing compile command options
/// that specify said explicit module dependencies.
@_spi(Testing) public struct ExplicitDependencyBuildPlanner {
  /// The module dependency graph.
  @_spi(Testing) public let dependencyGraph: InterModuleDependencyGraph

  /// A set of direct and transitive dependencies for every module in the dependency graph
  private let reachabilityMap: [ModuleDependencyId : Set<ModuleDependencyId>]

  /// The toolchain to be used for frontend job generation.
  private let toolchain: Toolchain

  /// Whether we are using the integrated driver via libSwiftDriver shared lib
  private let integratedDriver: Bool
  private let mainModuleName: String?
  private let cas: SwiftScanCAS?
  private let prefixMap: [(AbsolutePath, AbsolutePath)]

  /// Clang PCM names contain a hash of the command-line arguments that were used to build them.
  /// We avoid re-running the hash computation with the use of this cache
  private var hashedModuleNameCache: [String: String] = [:]

  /// Does this compile support `.explicitInterfaceModuleBuild`
  private let supportsExplicitInterfaceBuild: Bool

  /// status of the scanner prefix mapping option supported by the frontend
  private let supportsScannerPrefixMapPaths: Bool

  /// Cached command-line additions for all main module compile jobs
  private struct ResolvedModuleDependenciesCommandLineComponents {
    let inputs: [TypedVirtualPath]
    let commandLine: [Job.ArgTemplate]
  }

  /// Resolved additions to all main source module compile commands
  /// specifying explicit module dependency module paths
  private let resolvedMainModuleDependenciesArgs: ResolvedModuleDependenciesCommandLineComponents

  /// Resolved additions to the main source module PCH compile command
  /// specifying explicit module dependency module paths
  private let resolvedPCHModuleDependenciesArgs: ResolvedModuleDependenciesCommandLineComponents

  /// The computed path to a chained bridging header
  let chainedBridgingHeaderFile: ChainedBridgingHeaderFile?

  /// Does this compile support resolving bridging header pch command from swiftScan.
  let supportsBridgingHeaderPCHCommand: Bool

  public init(dependencyGraph: InterModuleDependencyGraph,
              toolchain: Toolchain,
              integratedDriver: Bool = true,
              supportsExplicitInterfaceBuild: Bool = false,
              cas: SwiftScanCAS? = nil,
              prefixMap:  [(AbsolutePath, AbsolutePath)] = [],
              supportsBridgingHeaderPCHCommand: Bool = false,
              supportsScannerPrefixMapPaths: Bool = false) throws {
    self.dependencyGraph = dependencyGraph
    self.toolchain = toolchain
    self.integratedDriver = integratedDriver
    self.mainModuleName = dependencyGraph.mainModuleName
    self.reachabilityMap = try dependencyGraph.computeTransitiveClosure()
    self.supportsExplicitInterfaceBuild = supportsExplicitInterfaceBuild
    self.supportsBridgingHeaderPCHCommand = supportsBridgingHeaderPCHCommand
    self.supportsScannerPrefixMapPaths = supportsScannerPrefixMapPaths
    self.cas = cas
    self.prefixMap = prefixMap
    let mainModuleId: ModuleDependencyId = .swift(dependencyGraph.mainModuleName)
    let mainModuleDetails = try dependencyGraph.swiftModuleDetails(of: mainModuleId)
    if let path = mainModuleDetails.chainedBridgingHeaderPath,
          let content = mainModuleDetails.chainedBridgingHeaderContent {
      self.chainedBridgingHeaderFile = ChainedBridgingHeaderFile(path: path, content: content)
    } else {
      self.chainedBridgingHeaderFile = nil
    }
    self.resolvedMainModuleDependenciesArgs = try Self.resolveMainModuleDependencies(in: dependencyGraph,
                                                                                     reachabilityMap: reachabilityMap,
                                                                                     cas: cas)
    self.resolvedPCHModuleDependenciesArgs = try Self.resolveBridgingHeaderDependencies(in: dependencyGraph,
                                                                                        reachabilityMap: reachabilityMap,
                                                                                        cas: cas)
  }

  /// Generate build jobs for all dependencies of the main module.
  /// The main module itself is handled elsewhere in the driver.
  ///
  /// The main source of complexity in this procedure is versioning of Clang dependency PCMs.
  /// There exists a strict limitation that a compatible PCM must have the exact same target version
  /// with the loading module (either a Swift module or another PCM). This means that each PCM may
  /// have to be built multiple times, once for each unique (SDK, architecture, toolchain) tuple
  /// of some loading module.
  ///
  /// For example:
  ///   Main (target: 10.13) depends on ClangA, SwiftB, SwiftC, SwiftD, ClangD
  ///   SwiftB (target: 10.12) depends on ClangB, SwiftC
  ///   SwiftC (target: 10.11) depends on ClangC
  ///   SwiftD (target: 10.10) depends on ClangD
  /// (Clang{A,B,C,D} are leaf modules)
  /// If the task is to build `main`, the Clang modules in this example have the following "uses":
  ///   ClangA is used directly by Main.
  ///   ClangB is used directly by SwiftB and transitively by Main.
  ///   ClangC is used directly by SwiftC and transitively by Main and SwiftB.
  ///   ClangD is used directly by SwiftD and Main.
  /// Given the individual targets of the uses, the following versions of the Clang modules must
  /// be built:
  ///   ClangA: (10.13)
  ///   ClangB: (10.12, 10.13)
  ///   ClangC: (10.11, 10.12, 10.13)
  ///   ClangD: (10.10, 10.13)
  ///
  /// Due to this requirement, we generate jobs for main main module dependencies in two stages:
  /// 1. Generate jobs for all Swift modules, accumulating, for each Clang dependency, the depending Swift
  /// module's target version (PCM Args).
  /// 2. Generate jobs for all Clang modules, now that we have each module's set of PCM versions it must be
  /// built against.
  public mutating func generateExplicitModuleDependenciesBuildJobs() throws -> [Job] {
    let mainModuleId: ModuleDependencyId = .swift(dependencyGraph.mainModuleName)
    guard let mainModuleDependencies = reachabilityMap[mainModuleId] else {
      fatalError("Expected reachability information for the main module.")
    }
    let swiftDependenciesJobs =
      try generateSwiftDependenciesBuildJobs(for: mainModuleDependencies)

    // Generate build jobs for all Clang modules
    let clangDependenciesJobs =
      try generateClangDependenciesBuildJobs(for: mainModuleDependencies)

    return swiftDependenciesJobs + clangDependenciesJobs
  }

  /// Generate a build job for each Swift module in the set of supplied `dependencies`
  private mutating func generateSwiftDependenciesBuildJobs(for dependencies: Set<ModuleDependencyId>)
  throws -> [Job] {
    var jobs: [Job] = []
    let swiftDependencies = dependencies.filter {
      if case .swift(_) = $0 {
        return true
      }
      return false
    }
    for moduleId in swiftDependencies {
      let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
      var inputs: [TypedVirtualPath] = []
      var commandLine: [Job.ArgTemplate] = []
      // First, take the command line options provided in the dependency information
      let moduleDetails = try dependencyGraph.swiftModuleDetails(of: moduleId)
      moduleDetails.commandLine?.forEach { commandLine.appendFlags($0) }

      // Resolve all dependency module inputs for this Swift module
      try Self.resolveExplicitModuleDependencies(moduleId: moduleId,
                                                 in: dependencyGraph,
                                                 reachabilityMap: reachabilityMap,
                                                 cas: cas,
                                                 inputs: &inputs,
                                                 commandLine: &commandLine)

      // Build the .swiftinterfaces file using a list of command line options specified in the
      // `details` field.
      guard let moduleInterfacePath = moduleDetails.moduleInterfacePath else {
        throw Driver.Error.malformedModuleDependency(moduleId.moduleName,
                                                     "no `moduleInterfacePath` object")
      }

      let inputInterfacePath = TypedVirtualPath(file: moduleInterfacePath.path, type: .swiftInterface)
      inputs.append(inputInterfacePath)
      let outputModulePath = TypedVirtualPath(file: moduleInfo.modulePath.path, type: .swiftModule)
      let outputs = [outputModulePath]

      let cacheKeys : [TypedVirtualPath : String]
      if let key = moduleDetails.moduleCacheKey {
        cacheKeys = [inputInterfacePath: key]
      } else {
        cacheKeys = [:]
      }
      // Add precompiled module candidates, if present
      if let compiledCandidateList = moduleDetails.compiledModuleCandidates {
        for compiledCandidate in compiledCandidateList {
          inputs.append(TypedVirtualPath(file: compiledCandidate.path,
                                         type: .swiftModule))
        }
      }

      // Add prefix mapping. The option is cache invariant so it can be added without affecting cache key.
      for (key, value) in prefixMap {
        commandLine.appendFlag("-cache-replay-prefix-map")
        if supportsScannerPrefixMapPaths {
          commandLine.appendFlag(value.pathString)
          commandLine.appendFlag(key.pathString)
        } else {
          commandLine.appendFlag(value.pathString + "=" + key.pathString)
        }
      }

      jobs.append(Job(
        moduleName: moduleId.moduleName,
        kind: .compileModuleFromInterface,
        tool: try toolchain.resolvedTool(.swiftCompiler),
        commandLine: commandLine,
        inputs: inputs,
        primaryInputs: [],
        outputs: outputs,
        outputCacheKeys: cacheKeys
      ))
    }
    return jobs
  }

  /// Generate a build job for each Clang module in the set of supplied `dependencies`.
  private mutating func generateClangDependenciesBuildJobs(for dependencies: Set<ModuleDependencyId>)
  throws -> [Job] {
    var jobs: [Job] = []
    let clangDependencies = dependencies.filter {
      if case .clang(_) = $0 {
        return true
      }
      return false
    }
    for moduleId in clangDependencies {
      let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
      // Generate a distinct job for each required set of PCM Arguments for this module
      var inputs: [TypedVirtualPath] = []
      var outputs: [TypedVirtualPath] = []
      var commandLine: [Job.ArgTemplate] = []

      // First, take the command line options provided in the dependency information
      let moduleDetails = try dependencyGraph.clangModuleDetails(of: moduleId)
      moduleDetails.commandLine.forEach { commandLine.appendFlags($0) }

      // Resolve all dependency module inputs for this Clang module
      try Self.resolveExplicitModuleDependencies(moduleId: moduleId, in: dependencyGraph,
                                                 reachabilityMap: reachabilityMap,
                                                 cas: cas, inputs: &inputs,
                                                 commandLine: &commandLine)

      let moduleMapPath = TypedVirtualPath(file: moduleDetails.moduleMapPath.path, type: .clangModuleMap)
      let modulePCMPath = TypedVirtualPath(file: moduleInfo.modulePath.path, type: .pcm)
      outputs.append(modulePCMPath)

      // The only required input is the .modulemap for this module.
      // Command line options in the dependency scanner output will include the
      // required modulemap, so here we must only add it to the list of inputs.
      let cacheKeys : [TypedVirtualPath : String]
      if let key = moduleDetails.moduleCacheKey {
        cacheKeys = [moduleMapPath: key]
      } else {
        cacheKeys = [:]
      }

      // Add prefix mapping. The option is cache invariant so it can be added without affecting cache key.
      for (key, value) in prefixMap {
        commandLine.appendFlag("-cache-replay-prefix-map")
        if supportsScannerPrefixMapPaths {
          commandLine.appendFlag(value.pathString)
          commandLine.appendFlag(key.pathString)
        } else {
          commandLine.appendFlag(value.pathString + "=" + key.pathString)
        }
      }

      jobs.append(Job(
        moduleName: moduleId.moduleName,
        kind: .generatePCM,
        tool: try toolchain.resolvedTool(.swiftCompiler),
        commandLine: commandLine,
        inputs: inputs,
        primaryInputs: [],
        outputs: outputs,
        outputCacheKeys: cacheKeys
      ))
    }
    return jobs
  }

  /// For the specified module, update the given command line flags and inputs
  /// to use explicitly-built module dependencies.
  private static func resolveExplicitModuleDependencies(moduleId: ModuleDependencyId,
                                                        in dependencyGraph: InterModuleDependencyGraph,
                                                        reachabilityMap: [ModuleDependencyId : Set<ModuleDependencyId>],
                                                        cas: SwiftScanCAS?,
                                                        inputs: inout [TypedVirtualPath],
                                                        commandLine: inout [Job.ArgTemplate]) throws {
    // Prohibit the frontend from implicitly building textual modules into binary modules.
    var swiftDependencyArtifacts: Set<SwiftModuleArtifactInfo> = []
    var clangDependencyArtifacts: Set<ClangModuleArtifactInfo> = []
    try Self.addModuleDependencies(of: moduleId,
                                   in: dependencyGraph,
                                   reachabilityMap: reachabilityMap,
                              clangDependencyArtifacts: &clangDependencyArtifacts,
                              swiftDependencyArtifacts: &swiftDependencyArtifacts)

    // Each individual module binary is still an "input" to ensure the build system gets the
    // order correctly.
    for dependencyModule in swiftDependencyArtifacts {
      inputs.append(TypedVirtualPath(file: dependencyModule.modulePath.path,
                                     type: .swiftModule))
    }
    for moduleArtifactInfo in clangDependencyArtifacts {
      let clangModulePath =
        TypedVirtualPath(file: moduleArtifactInfo.clangModulePath.path,
                         type: .pcm)
      inputs.append(clangModulePath)
    }

    // Swift Main Module dependencies are passed encoded in a JSON file as described by
    // SwiftModuleArtifactInfo
    guard moduleId == .swift(dependencyGraph.mainModuleName) else { return }
    let dependencyFileContent =
      try Self.serializeModuleDependencies(for: moduleId,
                                           swiftDependencyArtifacts: swiftDependencyArtifacts,
                                           clangDependencyArtifacts: clangDependencyArtifacts)
    if let cas = cas {
      // When using a CAS, write JSON into CAS and pass the ID on command-line.
      let casID = try cas.store(data: dependencyFileContent)
      commandLine.appendFlag("-explicit-swift-module-map-file")
      commandLine.appendFlag(casID)
    } else {
      // Write JSON to a file and add the JSON artifacts to command-line and inputs.
      let dependencyFile =
        try VirtualPath.createUniqueTemporaryFileWithKnownContents(.init(validating: "\(moduleId.moduleName)-dependencies.json"),
                                                                   dependencyFileContent)
      commandLine.appendFlag("-explicit-swift-module-map-file")
      commandLine.appendPath(dependencyFile)
      inputs.append(TypedVirtualPath(file: dependencyFile.intern(),
                                     type: .jsonSwiftArtifacts))
    }
  }

  private static func addModuleDependency(of moduleId: ModuleDependencyId,
                                          in dependencyGraph: InterModuleDependencyGraph,
                                          dependencyId: ModuleDependencyId,
                                          clangDependencyArtifacts: inout Set<ClangModuleArtifactInfo>,
                                          swiftDependencyArtifacts: inout Set<SwiftModuleArtifactInfo>,
                                          bridgingHeaderDeps: Set<ModuleDependencyId>? = nil
  ) throws {
    switch dependencyId {
      case .swift:
        let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)
        let swiftModulePath: TypedVirtualPath
        let isFramework: Bool
        swiftModulePath = .init(file: dependencyInfo.modulePath.path,
                                type: .swiftModule)
        let swiftModuleDetails = try dependencyGraph.swiftModuleDetails(of: dependencyId)
        isFramework = swiftModuleDetails.isFramework ?? false
        // Accumulate the required information about this dependency
        // TODO: add .swiftdoc and .swiftsourceinfo for this module.
        swiftDependencyArtifacts.insert(
          SwiftModuleArtifactInfo(name: dependencyId.moduleName,
                                  modulePath: TextualVirtualPath(path: swiftModulePath.fileHandle),
                                  isFramework: isFramework,
                                  moduleCacheKey: swiftModuleDetails.moduleCacheKey))
      case .clang:
        let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)
        let dependencyClangModuleDetails =
          try dependencyGraph.clangModuleDetails(of: dependencyId)
        // Accumulate the required information about this dependency
        clangDependencyArtifacts.insert(
          ClangModuleArtifactInfo(name: dependencyId.moduleName,
                                  modulePath: TextualVirtualPath(path: dependencyInfo.modulePath.path),
                                  moduleMapPath: dependencyClangModuleDetails.moduleMapPath,
                                  moduleCacheKey: dependencyClangModuleDetails.moduleCacheKey,
                                  isBridgingHeaderDependency: bridgingHeaderDeps?.contains(dependencyId) ?? true))
      case .swiftPrebuiltExternal:
        let prebuiltModuleDetails = try dependencyGraph.swiftPrebuiltDetails(of: dependencyId)
        let compiledModulePath = prebuiltModuleDetails.compiledModulePath
        let isFramework = prebuiltModuleDetails.isFramework ?? false
        let swiftModulePath: TypedVirtualPath =
          .init(file: compiledModulePath.path, type: .swiftModule)
        // Accumulate the required information about this dependency
        // TODO: add .swiftdoc and .swiftsourceinfo for this module.
        swiftDependencyArtifacts.insert(
          SwiftModuleArtifactInfo(name: dependencyId.moduleName,
                                  modulePath: TextualVirtualPath(path: swiftModulePath.fileHandle),
                                  headerDependencies: prebuiltModuleDetails.headerDependencyPaths,
                                  isFramework: isFramework,
                                  moduleCacheKey: prebuiltModuleDetails.moduleCacheKey))
    }
  }

  /// Collect the Set of all Clang module dependencies which are dependencies of either
  /// the `moduleId` bridging header or dependencies of bridging headers
  /// of any prebuilt binary Swift modules in the dependency graph.
  private static func collectHeaderModuleDeps(of moduleId: ModuleDependencyId,
                                              in dependencyGraph: InterModuleDependencyGraph,
                                              reachabilityMap: [ModuleDependencyId : Set<ModuleDependencyId>]
  ) throws -> Set<ModuleDependencyId>?  {
    var bridgingHeaderDeps: Set<ModuleDependencyId>? = nil
    guard let moduleDependencies = reachabilityMap[moduleId] else {
      fatalError("Expected reachability information for the module: \(moduleId.moduleName).")
    }
    if let dependencySourceBridingHeaderDeps =
        try dependencyGraph.moduleInfo(of: moduleId).bridgingHeaderModuleDependencies {
      bridgingHeaderDeps = Set(dependencySourceBridingHeaderDeps)
    } else {
      bridgingHeaderDeps = Set<ModuleDependencyId>()
    }
    // Collect all binary Swift module dependnecies' header input module dependencies
    for dependencyId in moduleDependencies {
      if case .swiftPrebuiltExternal(_) = dependencyId {
        let prebuiltDependencyDetails = try dependencyGraph.swiftPrebuiltDetails(of: dependencyId)
        for headerDependency in prebuiltDependencyDetails.headerDependencyModuleDependencies ?? [] {
          bridgingHeaderDeps!.insert(headerDependency)
        }
      }
    }
    return bridgingHeaderDeps
  }

  /// Add a specific module dependency as an input and a corresponding command
  /// line flag.
  private static func addModuleDependencies(of moduleId: ModuleDependencyId,
                                            in dependencyGraph: InterModuleDependencyGraph,
                                            reachabilityMap: [ModuleDependencyId : Set<ModuleDependencyId>],
                                            clangDependencyArtifacts: inout Set<ClangModuleArtifactInfo>,
                                            swiftDependencyArtifacts: inout Set<SwiftModuleArtifactInfo>
  ) throws {
    guard let moduleDependencies = reachabilityMap[moduleId] else {
      fatalError("Expected reachability information for the module: \(moduleId.moduleName).")
    }
    for dependencyId in moduleDependencies {
      try Self.addModuleDependency(of: moduleId, in: dependencyGraph, dependencyId: dependencyId,
                                   clangDependencyArtifacts: &clangDependencyArtifacts,
                                   swiftDependencyArtifacts: &swiftDependencyArtifacts,
                                   bridgingHeaderDeps: try collectHeaderModuleDeps(of: moduleId,
                                                                                   in: dependencyGraph,
                                                                                   reachabilityMap: reachabilityMap))
    }
  }

  public func getLinkLibraryLoadCommandFlags(_ commandLine: inout [Job.ArgTemplate]) throws {
    var allLinkLibraries: [LinkLibraryInfo] = []
    for (_, moduleInfo) in dependencyGraph.modules {
      guard let moduleLinkLibraries = moduleInfo.linkLibraries else {
        continue
      }
      for linkLibrary in moduleLinkLibraries {
        allLinkLibraries.append(linkLibrary)
      }
    }
    toolchain.addAutoLinkFlags(for: allLinkLibraries, to: &commandLine)
  }

  private static func resolveMainModuleDependencies(in dependencyGraph: InterModuleDependencyGraph,
                                                    reachabilityMap: [ModuleDependencyId : Set<ModuleDependencyId>],
                                                    cas: SwiftScanCAS?) throws -> ResolvedModuleDependenciesCommandLineComponents {
    var inputAdditions: [TypedVirtualPath] = []
    var commandLineAdditions: [Job.ArgTemplate] = []
    let mainModuleId: ModuleDependencyId = .swift(dependencyGraph.mainModuleName)
    let mainModuleDetails = try dependencyGraph.swiftModuleDetails(of: mainModuleId)
    if let additionalArgs = mainModuleDetails.commandLine {
      additionalArgs.forEach { commandLineAdditions.appendFlag($0) }
    }
    commandLineAdditions.appendFlags("-disable-implicit-swift-modules",
                                     "-Xcc", "-fno-implicit-modules",
                                     "-Xcc", "-fno-implicit-module-maps")
    try Self.resolveExplicitModuleDependencies(moduleId: mainModuleId,
                                               in: dependencyGraph,
                                               reachabilityMap: reachabilityMap,
                                               cas: cas,
                                               inputs: &inputAdditions,
                                               commandLine: &commandLineAdditions)
    return ResolvedModuleDependenciesCommandLineComponents(
      inputs: inputAdditions,
      commandLine: commandLineAdditions
    )
  }

  /// Resolve all module dependencies of the main module and add them to the lists of
  /// inputs and command line flags.
  public func resolveMainModuleDependencies(inputs: inout [TypedVirtualPath],
                                            commandLine: inout [Job.ArgTemplate]) {
    inputs.append(contentsOf: resolvedMainModuleDependenciesArgs.inputs)
    commandLine.append(contentsOf: resolvedMainModuleDependenciesArgs.commandLine)
  }

  /// Get the context hash for the main module.
  public func getMainModuleContextHash() throws -> String? {
    let mainModuleId: ModuleDependencyId = .swift(dependencyGraph.mainModuleName)
    let mainModuleDetails = try dependencyGraph.swiftModuleDetails(of: mainModuleId)
    return mainModuleDetails.contextHash
  }

  /// Resolve all module dependencies of the main module and add them to the lists of
  /// inputs and command line flags.
  private static func resolveBridgingHeaderDependencies(in dependencyGraph: InterModuleDependencyGraph,
                                                        reachabilityMap: [ModuleDependencyId : Set<ModuleDependencyId>],
                                                        cas: SwiftScanCAS?) throws -> ResolvedModuleDependenciesCommandLineComponents {
    var inputAdditions: [TypedVirtualPath] = []
    var commandLineAdditions: [Job.ArgTemplate] = []

    let mainModuleId: ModuleDependencyId = .swift(dependencyGraph.mainModuleName)
    var swiftDependencyArtifacts: Set<SwiftModuleArtifactInfo> = []
    var clangDependencyArtifacts: Set<ClangModuleArtifactInfo> = []
    let mainModuleDetails = try dependencyGraph.swiftModuleDetails(of: mainModuleId)

    var addedDependencies: Set<ModuleDependencyId> = []
    var dependenciesWorklist = mainModuleDetails.bridgingHeaderDependencies ?? []

    while !dependenciesWorklist.isEmpty {
      guard let bridgingHeaderDepID = dependenciesWorklist.popLast() else {
        break
      }
      guard !addedDependencies.contains(bridgingHeaderDepID) else {
        continue
      }
      addedDependencies.insert(bridgingHeaderDepID)
      try Self.addModuleDependency(of: mainModuleId, in: dependencyGraph,
                                   dependencyId: bridgingHeaderDepID,
                                   clangDependencyArtifacts: &clangDependencyArtifacts,
                                   swiftDependencyArtifacts: &swiftDependencyArtifacts)
      try Self.addModuleDependencies(of: bridgingHeaderDepID, in: dependencyGraph,
                                     reachabilityMap: reachabilityMap,
                                     clangDependencyArtifacts: &clangDependencyArtifacts,
                                     swiftDependencyArtifacts: &swiftDependencyArtifacts)
      let depInfo = try dependencyGraph.moduleInfo(of: bridgingHeaderDepID)
      dependenciesWorklist.append(contentsOf: depInfo.allDependencies)
    }

    // Clang module dependencies are specified on the command line explicitly
    for moduleArtifactInfo in clangDependencyArtifacts {
      let clangModulePath =
        TypedVirtualPath(file: moduleArtifactInfo.clangModulePath.path,
                         type: .pcm)
      inputAdditions.append(clangModulePath)
    }

    // Return if depscanner provided build commands.
    if let scannerPCHArgs = mainModuleDetails.bridgingPchCommandLine {
      scannerPCHArgs.forEach { commandLineAdditions.appendFlag($0) }
      return ResolvedModuleDependenciesCommandLineComponents(
        inputs: inputAdditions,
        commandLine: commandLineAdditions
      )
    }

    assert(cas == nil, "Caching build should always return command-line from scanner")
    // Prohibit the frontend from implicitly building textual modules into binary modules.
    commandLineAdditions.appendFlags("-disable-implicit-swift-modules",
                                     "-Xcc", "-fno-implicit-modules",
                                     "-Xcc", "-fno-implicit-module-maps")

    let dependencyFileContent =
      try Self.serializeModuleDependencies(for: mainModuleId,
                                           swiftDependencyArtifacts: swiftDependencyArtifacts,
                                           clangDependencyArtifacts: clangDependencyArtifacts)

    let dependencyFile =
      try VirtualPath.createUniqueTemporaryFileWithKnownContents(.init(validating: "\(mainModuleId.moduleName)-dependencies.json"),
                                                                 dependencyFileContent)
    commandLineAdditions.appendFlag("-explicit-swift-module-map-file")
    commandLineAdditions.appendPath(dependencyFile)
    inputAdditions.append(TypedVirtualPath(file: dependencyFile.intern(),
                                   type: .jsonSwiftArtifacts))

    return ResolvedModuleDependenciesCommandLineComponents(
      inputs: inputAdditions,
      commandLine: commandLineAdditions
    )
  }

  /// Resolve all module dependencies of the main module and add them to the lists of
  /// inputs and command line flags.
  public func resolveBridgingHeaderDependencies(inputs: inout [TypedVirtualPath],
                                                commandLine: inout [Job.ArgTemplate]) {
    inputs.append(contentsOf: resolvedPCHModuleDependenciesArgs.inputs)
    commandLine.append(contentsOf: resolvedPCHModuleDependenciesArgs.commandLine)
  }

  /// Serialize the output file artifacts for a given module in JSON format.
  private static func serializeModuleDependencies(for moduleId: ModuleDependencyId,
                                                  swiftDependencyArtifacts: Set<SwiftModuleArtifactInfo>,
                                                  clangDependencyArtifacts: Set<ClangModuleArtifactInfo>
  ) throws -> Data {
    // The module dependency map in CAS needs to be stable.
    // Sort the dependencies by name.
    let allDependencyArtifacts: [ModuleDependencyArtifactInfo] =
      swiftDependencyArtifacts.sorted().map {ModuleDependencyArtifactInfo.swift($0)} +
      clangDependencyArtifacts.sorted().map {ModuleDependencyArtifactInfo.clang($0)}
    let encoder = JSONEncoder()
    // Use sorted key to ensure the order of the keys is stable.
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(allDependencyArtifacts)
  }
}

/// Encapsulates some of the common queries of the ExplicitDependencyBuildPlanner with error-checking
/// on the dependency graph's structure.
@_spi(Testing) public extension InterModuleDependencyGraph {
  func moduleInfo(of moduleId: ModuleDependencyId) throws -> ModuleInfo {
    guard let moduleInfo = modules[moduleId] else {
      throw Driver.Error.missingModuleDependency(moduleId.moduleName)
    }
    return moduleInfo
  }

  func swiftModuleDetails(of moduleId: ModuleDependencyId) throws -> SwiftModuleDetails {
    guard case .swift(let swiftModuleDetails) = try moduleInfo(of: moduleId).details else {
      throw Driver.Error.malformedModuleDependency(moduleId.moduleName, "no Swift `details` object")
    }
    return swiftModuleDetails
  }

  func swiftPrebuiltDetails(of moduleId: ModuleDependencyId)
  throws -> SwiftPrebuiltExternalModuleDetails {
    guard case .swiftPrebuiltExternal(let prebuiltModuleDetails) =
            try moduleInfo(of: moduleId).details else {
      throw Driver.Error.malformedModuleDependency(moduleId.moduleName,
                                                   "no SwiftPrebuiltExternal `details` object")
    }
    return prebuiltModuleDetails
  }

  func clangModuleDetails(of moduleId: ModuleDependencyId) throws -> ClangModuleDetails {
    guard case .clang(let clangModuleDetails) = try moduleInfo(of: moduleId).details else {
      throw Driver.Error.malformedModuleDependency(moduleId.moduleName, "no Clang `details` object")
    }
    return clangModuleDetails
  }
}

internal extension ExplicitDependencyBuildPlanner {
  func findPath(from source: ModuleDependencyId, to destination: ModuleDependencyId) throws -> [ModuleDependencyId]? {
    guard dependencyGraph.modules.contains(where: { $0.key == destination }) else { return nil }
    var result: [ModuleDependencyId]? = nil
    var visited: Set<ModuleDependencyId> = []
    try dependencyGraph.findAPath(source: source,
                                  pathSoFar: [source],
                                  visited: &visited,
                                  result: &result) { $0 == destination }
    return result
  }
}

internal extension ExplicitDependencyBuildPlanner {
  func filterMandatoryModuleDependencyCompileJobs(_ allJobs: [Job],
                                                  fileSystem: FileSystem,
                                                  cas: SwiftScanCAS?,
                                                  reporter: IncrementalCompilationState.Reporter? = nil) throws -> [Job] {
    return try dependencyGraph.filterMandatoryModuleDependencyCompileJobs(allJobs, fileSystem: fileSystem, cas: cas, reporter: reporter)
  }
}

// InterModuleDependencyGraph printing, useful for debugging
internal extension InterModuleDependencyGraph {
  func prettyPrintString() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(self)
    return String(data: contents, encoding: .utf8)!
  }
}
