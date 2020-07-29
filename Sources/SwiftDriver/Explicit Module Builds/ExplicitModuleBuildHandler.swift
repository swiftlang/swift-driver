//===--------------- ExplicitModuleBuildHandler.swift ---------------------===//
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
import TSCBasic
import TSCUtility
import Foundation

/// In Explicit Module Build mode, this handler is responsible for generating and providing
/// build jobs for all module dependencies and providing compile command options
/// that specify said explicit module dependencies.
@_spi(Testing) public struct ExplicitModuleBuildHandler {
  /// The module dependency graph.
  public var dependencyGraph: InterModuleDependencyGraph

  /// Cache Clang modules for which a build job has already been constructed with a given
  /// target triple.
  private var clangTargetModuleBuildCache = ClangModuleBuildJobCache()

  /// Cache Swift modules for which a build job has already been constructed.
  @_spi(Testing) public var swiftModuleBuildCache: [ModuleDependencyId: Job] = [:]

  /// The toolchain to be used for frontend job generation.
  private let toolchain: Toolchain

  /// The file system which we should interact with.
  /// FIXME: Our end goal is to not have any direct filesystem manipulation in here, but  that's dependent on getting the
  /// dependency scanner/dependency job generation  moved into a Job.
  private let fileSystem: FileSystem

  /// Path to the directory that will contain the temporary files.
  /// e.g. Explicit Swift module artifact files
  /// FIXME: Our end goal is to not have any direct filesystem manipulation in here, but  that's dependent on getting the
  /// dependency scanner/dependency job generation  moved into a Job.
  private let temporaryDirectory: AbsolutePath

  public init(dependencyGraph: InterModuleDependencyGraph, toolchain: Toolchain,
              fileSystem: FileSystem) throws {
    self.dependencyGraph = dependencyGraph
    self.toolchain = toolchain
    self.fileSystem = fileSystem
    self.temporaryDirectory = try determineTempDirectory()
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
  /// Constructing a build job for a given Swift module `A` requires resolving all of the `A`'s
  /// dependencies (direct and transitive). To do so, we traverse the dependency graph starting at
  /// `A`'s node, in a depth-first fashion, passing along `A`'s target triple, adding the
  /// encountered modules to the build job's inputs and command line arguments. For every node `B`
  /// encountered along the way, if `B`'s build job has not yet been created, the handler will
  /// request that a build job be generated and cached. If `B` is a Clang module, then `A`'s
  /// specified target triple is used to build its PCM. Generating `B`'s build job results in a new
  /// depth-first traversal of the dependency graph, starting at `B`. If `B` is a Swift module, then
  /// its target triple is passed along when traversing its dependencies to generate its build job.
  /// Once `B`'s build job is generated, `A`'s dependency traversal continues until all dependencies
  /// are exhausted and `A`'s build job can be constructed.
  ///
  /// For example:
  /// Generating build jobs for the following dependency graph:
  /// Module:     S1 ---->   S2 ---->  S3 ----> C1
  /// Target:  (10.14)    (10.12)   (10.12)
  /// (Sx: Swift module, Cx: Clang Module)
  /// (A ----> B: module A depends on module B)
  ///
  /// Startig at S1, the traversal is as follows:
  /// - S1 Traversal starts
  ///     - S2 Traversal Starts
  ///         - S3 Traversal Starts
  ///         - Visit C1: (Generate Job: C1-10.12)
  ///         - Generate Job: S3
  ///     - Visit S3: (S3 found in cache)
  ///     - Visit C1: (C1-10.12 found in cache)
  ///     - Generate Job: S2
  /// - Visit S2: (S2 found in cache)
  /// - Visit S3: (S3 found in cache)
  /// - Visit C1: (Generate Job: C1-10.14)
  /// - Generate Job: S1
  ///
  mutating public func generateExplicitModuleDependenciesBuildJobs() throws -> [Job] {
    var mainModuleInputs: [TypedVirtualPath] = []
    var mainModuleCommandLine: [Job.ArgTemplate] = []
    try resolveMainModuleDependencies(inputs: &mainModuleInputs,
                                      commandLine: &mainModuleCommandLine)
    return Array(swiftModuleBuildCache.values) + clangTargetModuleBuildCache.allJobs
  }

  /// Resolve all module dependencies of the main module and add them to the lists of
  /// inputs and command line flags.
  mutating public func resolveMainModuleDependencies(inputs: inout [TypedVirtualPath],
                                                     commandLine: inout [Job.ArgTemplate]) throws {
    let mainModuleId: ModuleDependencyId = .swift(dependencyGraph.mainModuleName)
    try resolveExplicitModuleDependencies(moduleId: mainModuleId,
                                          pcmArgs: try dependencyGraph.swiftModulePCMArgs(of: mainModuleId),
                                          inputs: &inputs,
                                          commandLine: &commandLine)
  }

  /// For a given Swift module, generate a build job and resolve its dependencies.
  /// Resolving a module's dependencies will ensure that the dependencies' build jobs are also
  /// generated.
  mutating private func genSwiftModuleBuildJob(moduleId: ModuleDependencyId) throws {
    let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
    var inputs: [TypedVirtualPath] = []
    let outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: try VirtualPath(path: moduleInfo.modulePath), type: .swiftModule)
    ]
    var commandLine: [Job.ArgTemplate] = []

    // First, take the command line options provided in the dependency information
    let moduleDetails = try dependencyGraph.swiftModuleDetails(of: moduleId)
    moduleDetails.commandLine?.forEach { commandLine.appendFlags($0) }

    // Resolve all dependency module inputs for this Swift module
    try resolveExplicitModuleDependencies(moduleId: moduleId,
                                          pcmArgs: dependencyGraph.swiftModulePCMArgs(of: moduleId),
                                          inputs: &inputs, commandLine: &commandLine)

    // Build the .swiftinterfaces file using a list of command line options specified in the
    // `details` field.
    guard let moduleInterfacePath = moduleDetails.moduleInterfacePath else {
      throw Driver.Error.malformedModuleDependency(moduleId.moduleName,
                                                   "no `moduleInterfacePath` object")
    }
    inputs.append(TypedVirtualPath(file: try VirtualPath(path: moduleInterfacePath),
                                   type: .swiftInterface))

    // Add precompiled module candidates, if present
    if let compiledCandidateList = moduleDetails.compiledModuleCandidates {
      for compiledCandidate in compiledCandidateList {
        commandLine.appendFlag("-candidate-module-file")
        let compiledCandidatePath = try VirtualPath(path: compiledCandidate)
        commandLine.appendPath(compiledCandidatePath)
        inputs.append(TypedVirtualPath(file: compiledCandidatePath,
                                       type: .swiftModule))
      }
    }

    swiftModuleBuildCache[moduleId] = Job(
      moduleName: moduleId.moduleName,
      kind: .emitModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }

  /// For a given Clang module, generate a build job and resolve its dependencies.
  /// Resolving a module's dependencies will ensure that the dependencies' build jobs are also
  /// generated.
  mutating private func genClangModuleBuildJob(moduleId: ModuleDependencyId,
                                               pcmArgs: [String]) throws {
    let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = []
    var commandLine: [Job.ArgTemplate] = []

    // First, take the command line options provided in the dependency information
    let moduleDetails = try dependencyGraph.clangModuleDetails(of: moduleId)
    moduleDetails.commandLine?.forEach { commandLine.appendFlags($0) }

    // Add the `-target` option as inherited from the dependent Swift module's PCM args
    pcmArgs.forEach { commandLine.appendFlags($0) }

    // Resolve all dependency module inputs for this Clang module
    try resolveExplicitModuleDependencies(moduleId: moduleId, pcmArgs: pcmArgs, inputs: &inputs,
                                          commandLine: &commandLine)

    // Encode the target triple pcm args into the output `.pcm` filename
    let targetEncodedModulePath =
      try ExplicitModuleBuildHandler.targetEncodedClangModuleFilePath(for: moduleInfo,
                                                                      pcmArgs: pcmArgs)
    outputs.append(TypedVirtualPath(file: targetEncodedModulePath, type: .pcm))
    commandLine.appendFlags("-emit-pcm", "-module-name", moduleId.moduleName,
                            "-o", targetEncodedModulePath.description)

    // The only required input is the .modulemap for this module.
    // Command line options in the dependency scanner output will include the required modulemap,
    // so here we must only add it to the list of inputs.
    inputs.append(TypedVirtualPath(file: try VirtualPath(path: moduleDetails.moduleMapPath),
                                   type: .clangModuleMap))

    clangTargetModuleBuildCache[(moduleId, pcmArgs)] = Job(
      moduleName: moduleId.moduleName,
      kind: .generatePCM,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }

  /// Store the output file artifacts for a given module in a JSON file, return the file's path.
  private func serializeModuleDependencies(for moduleId: ModuleDependencyId,
                                           dependencyArtifacts: [SwiftModuleArtifactInfo]
  ) throws -> AbsolutePath {
    let dependencyFilePath =
      temporaryDirectory.appending(component: "\(moduleId.moduleName)-dependencies.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(dependencyArtifacts)
    try fileSystem.writeFileContents(dependencyFilePath, bytes: ByteString(contents))
    return dependencyFilePath
  }

  /// For the specified module, update the given command line flags and inputs
  /// to use explicitly-built module dependencies.
  /// 
  /// Along the way, for any dependency module (direct or transitive) for which no build job
  /// has yet been generated, generate one and cache it.
  mutating private func resolveExplicitModuleDependencies(moduleId: ModuleDependencyId,
                                                          pcmArgs: [String],
                                                          inputs: inout [TypedVirtualPath],
                                                          commandLine: inout [Job.ArgTemplate]
  ) throws {
    // Prohibit the frontend from implicitly building textual modules into binary modules.
    commandLine.appendFlags("-disable-implicit-swift-modules", "-Xcc", "-Xclang", "-Xcc",
                            "-fno-implicit-modules")
    var swiftDependencyArtifacts: [SwiftModuleArtifactInfo] = []
    var clangDependencyArtifacts: [ClangModuleArtifactInfo] = []
    var alreadyAddedDependencies = Set<ModuleDependencyId>()
    try addModuleDependencies(moduleId: moduleId, pcmArgs: pcmArgs,
                              addedDependenciesSet: &alreadyAddedDependencies,
                              clangDependencyArtifacts: &clangDependencyArtifacts,
                              swiftDependencyArtifacts: &swiftDependencyArtifacts)

    // Swift Module dependencies are passed encoded in a JSON file as described by
    // SwiftModuleArtifactInfo
    if !swiftDependencyArtifacts.isEmpty {
      let dependencyFile =
        try serializeModuleDependencies(for: moduleId, dependencyArtifacts: swiftDependencyArtifacts)
      commandLine.appendFlag("-explicit-swift-module-map-file")
      commandLine.appendPath(dependencyFile)
      inputs.append(TypedVirtualPath(file: try VirtualPath(path: dependencyFile.pathString),
                                     type: .jsonSwiftArtifacts))
      // Each individual module binary is still an "input" to ensure the build system gets the
      // order correctly.
      for dependencyModule in swiftDependencyArtifacts {
        inputs.append(TypedVirtualPath(file: try VirtualPath(path: dependencyModule.modulePath),
                                       type: .swiftModule))
      }
    }
    // Clang module depenencies are specified on the command line eplicitly
    for moduleArtifactInfo in clangDependencyArtifacts {
      let clangModulePath =
        TypedVirtualPath(file: try VirtualPath(path: moduleArtifactInfo.modulePath),
                         type: .pcm)
      let clangModuleMapPath =
        TypedVirtualPath(file: try VirtualPath(path: moduleArtifactInfo.moduleMapPath),
                         type: .clangModuleMap)
      commandLine.appendFlags("-Xcc", "-Xclang", "-Xcc",
                              "-fmodule-file=\(clangModulePath.file.description)")
      commandLine.appendFlags("-Xcc", "-Xclang", "-Xcc",
                              "-fmodule-map-file=\(clangModuleMapPath.file.description)")
      inputs.append(clangModulePath)
      inputs.append(clangModuleMapPath)
    }
  }

  /// Add a specific module dependency as an input and a corresponding command
  /// line flag. Dispatches to clang and swift-specific variants.
  mutating private func addModuleDependencies(moduleId: ModuleDependencyId, pcmArgs: [String],
                                              addedDependenciesSet: inout Set<ModuleDependencyId>,
                                              clangDependencyArtifacts: inout [ClangModuleArtifactInfo],
                                              swiftDependencyArtifacts: inout [SwiftModuleArtifactInfo]
  ) throws {
    for dependencyId in try dependencyGraph.moduleInfo(of: moduleId).directDependencies {
      guard addedDependenciesSet.insert(dependencyId).inserted else {
        continue
      }
      switch dependencyId {
        case .swift:
          try addSwiftModuleDependency(moduleId: moduleId, dependencyId: dependencyId,
                                       pcmArgs: pcmArgs,
                                       addedDependenciesSet: &addedDependenciesSet,
                                       clangDependencyArtifacts: &clangDependencyArtifacts,
                                       swiftDependencyArtifacts: &swiftDependencyArtifacts)
        case .clang:
          try addClangModuleDependency(moduleId: moduleId, dependencyId: dependencyId,
                                       pcmArgs: pcmArgs,
                                       addedDependenciesSet: &addedDependenciesSet,
                                       clangDependencyArtifacts: &clangDependencyArtifacts,
                                       swiftDependencyArtifacts: &swiftDependencyArtifacts)
      }
    }
  }

  /// Add a specific Swift module dependency as an input and a corresponding command
  /// line flag.
  /// Check the module build job cache for whether a build job has already been
  /// generated for this dependency module; if not, request that one is generated.
  mutating private func addSwiftModuleDependency(moduleId: ModuleDependencyId,
                                                 dependencyId: ModuleDependencyId,
                                                 pcmArgs: [String],
                                                 addedDependenciesSet: inout Set<ModuleDependencyId>,
                                                 clangDependencyArtifacts: inout [ClangModuleArtifactInfo],
                                                 swiftDependencyArtifacts: inout [SwiftModuleArtifactInfo]
  ) throws {
    // Add it as an explicit dependency
    let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)

    let swiftModulePath: TypedVirtualPath
    if case .swift(let details) = dependencyInfo.details,
       let compiledModulePath = details.compiledModulePath {
      // If an already-compiled module is available, use it.
      swiftModulePath = .init(file: try VirtualPath(path: compiledModulePath),
                              type: .swiftModule)
    } else {
      // Generate a build job for the dependency module, if not already generated
      if swiftModuleBuildCache[dependencyId] == nil {
        try genSwiftModuleBuildJob(moduleId: dependencyId)
        assert(swiftModuleBuildCache[dependencyId] != nil)
      }
      swiftModulePath = .init(file: try VirtualPath(path: dependencyInfo.modulePath),
                              type: .swiftModule)
    }

    // Collect the required information about this module
    // TODO: add .swiftdoc and .swiftsourceinfo for this module.
    swiftDependencyArtifacts.append(
      SwiftModuleArtifactInfo(name: dependencyId.moduleName,
                              modulePath: swiftModulePath.file.description))

    // Process all transitive dependencies as direct
    try addModuleDependencies(moduleId: dependencyId, pcmArgs: pcmArgs,
                              addedDependenciesSet: &addedDependenciesSet,
                              clangDependencyArtifacts: &clangDependencyArtifacts,
                              swiftDependencyArtifacts: &swiftDependencyArtifacts)
  }

  /// Add a specific Clang module dependency as an input and a corresponding command
  /// line flag.
  /// Check the module build job cache for whether a build job has already been
  /// generated for this dependency module; if not, request that one is generated.
  mutating private func addClangModuleDependency(moduleId: ModuleDependencyId,
                                                 dependencyId: ModuleDependencyId,
                                                 pcmArgs: [String],
                                                 addedDependenciesSet: inout Set<ModuleDependencyId>,
                                                 clangDependencyArtifacts: inout [ClangModuleArtifactInfo],
                                                 swiftDependencyArtifacts: inout [SwiftModuleArtifactInfo]
  ) throws {
    // Generate a build job for the dependency module at the given target, if not already generated
    if clangTargetModuleBuildCache[(dependencyId, pcmArgs)] == nil {
      try genClangModuleBuildJob(moduleId: dependencyId, pcmArgs: pcmArgs)
      assert(clangTargetModuleBuildCache[(dependencyId, pcmArgs)] != nil)
    }

    // Add it as an explicit dependency
    let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)
    let dependencyClangModuleDetails = try dependencyGraph.clangModuleDetails(of: dependencyId)
    let clangModulePath =
      try ExplicitModuleBuildHandler.targetEncodedClangModuleFilePath(for: dependencyInfo,
                                                                      pcmArgs: pcmArgs)

    // Collect the requried information about this module
    clangDependencyArtifacts.append(
      ClangModuleArtifactInfo(name: dependencyId.moduleName, modulePath: clangModulePath.description,
                              moduleMapPath: dependencyClangModuleDetails.moduleMapPath))

    // Process all transitive dependencies as direct
    try addModuleDependencies(moduleId: dependencyId, pcmArgs: pcmArgs,
                              addedDependenciesSet: &addedDependenciesSet,
                              clangDependencyArtifacts: &clangDependencyArtifacts,
                              swiftDependencyArtifacts: &swiftDependencyArtifacts)
  }
}

/// Utility methods for encoding PCM's target triple into its name.
extension ExplicitModuleBuildHandler {
  /// Compute a full path to the resulting .pcm file for a given Clang module, with the
  /// target triple encoded in the name.
  public static func targetEncodedClangModuleFilePath(for moduleInfo: ModuleInfo,
                                                      pcmArgs: [String]) throws -> VirtualPath {
    let plainModulePath = try VirtualPath(path: moduleInfo.modulePath)
    let targetEncodedBaseName =
      try targetEncodedClangModuleName(for: plainModulePath.basenameWithoutExt,
                                       pcmArgs: pcmArgs)
    let modifiedModulePath =
      moduleInfo.modulePath.replacingOccurrences(of: plainModulePath.basenameWithoutExt,
                                                 with: targetEncodedBaseName)
    return try VirtualPath(path: modifiedModulePath)
  }

  /// Compute the name of a given Clang module, along with a hash of extra PCM build arguments it
  /// is to be constructed with.
  public static func targetEncodedClangModuleName(for moduleName: String,
                                                  pcmArgs: [String]) throws -> String {
    var hasher = Hasher()
    pcmArgs.forEach { hasher.combine($0) }
    return moduleName + String(hasher.finalize())
  }
}

/// Encapsulates some of the common queries of the ExplicitModuleBuildeHandler with error-checking
/// on the dependency graph's structure.
private extension InterModuleDependencyGraph {
  func moduleInfo(of moduleId: ModuleDependencyId) throws -> ModuleInfo {
    guard let moduleInfo = modules[moduleId] else {
      throw Driver.Error.missingModuleDependency(moduleId.moduleName)
    }
    return moduleInfo
  }

  func swiftModuleDetails(of moduleId: ModuleDependencyId) throws -> SwiftModuleDetails {
    guard case .swift(let swiftModuleDetails) = try moduleInfo(of: moduleId).details else {
      throw Driver.Error.malformedModuleDependency(mainModuleName, "no Swift `details` object")
    }
    return swiftModuleDetails
  }

  func clangModuleDetails(of moduleId: ModuleDependencyId) throws -> ClangModuleDetails {
    guard case .clang(let clangModuleDetails) = try moduleInfo(of: moduleId).details else {
      throw Driver.Error.malformedModuleDependency(mainModuleName, "no Clang `details` object")
    }
    return clangModuleDetails
  }

  func swiftModulePCMArgs(of moduleId: ModuleDependencyId) throws -> [String] {
    let moduleDetails = try swiftModuleDetails(of: moduleId)
    guard let pcmArgs = moduleDetails.extraPcmArgs else {
      throw Driver.Error.missingPCMArguments(mainModuleName)
    }
    return pcmArgs
  }
}


