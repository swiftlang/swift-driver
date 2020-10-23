//===--------------- Planning.swift - Swift Compilation Planning ----------===//
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

public enum PlanningError: Error, DiagnosticData {
  case replReceivedInput
  case emitPCMWrongInputFiles

  public var description: String {
    switch self {
    case .replReceivedInput:
      return "REPL mode requires no input files"

    case .emitPCMWrongInputFiles:
      return "Clang module emission requires exactly one input file (the module map)"
    }
  }
}

/// // MARK: Standard build planning
extension Driver {
  /// Plan a standard compilation, which produces jobs for compiling separate
  /// primary files.
  private mutating func planStandardCompile() throws -> [Job] {
    precondition(compilerMode.isStandardCompilationForPlanning,
                 "compiler mode \(compilerMode) is handled elsewhere")

    var jobs = [Job]()
    func addJob(_ j: Job) {
      jobs.append(j)
    }

    try addPrecompileModuleDependenciesJobs(addJob: addJob)
    try addPrecompileBridgingHeaderJob(addJob: addJob)
    try addEmitModuleJob(addJob: addJob)

    let linkerInputs = try addJobsFeedingLinker(addJob: addJob)
    try addLinkAndPostLinkJobs(linkerInputs: linkerInputs,
                               debugInfo: debugInfo,
                               addJob: addJob)
    return jobs
  }


  private mutating func addPrecompileModuleDependenciesJobs(addJob: (Job) -> Void) throws {
    // If asked, add jobs to precompile module dependencies
    guard parsedOptions.contains(.driverExplicitModuleBuild) else { return }
    let modulePrebuildJobs = try generateExplicitModuleDependenciesJobs()
    modulePrebuildJobs.forEach(addJob)
  }


  private mutating func addPrecompileBridgingHeaderJob(addJob: (Job) -> Void) throws {
    guard
      let importedObjCHeader = importedObjCHeader,
      let bridgingPrecompiledHeader = bridgingPrecompiledHeader
    else { return }

    addJob(
      try generatePCHJob(input:  .init(file: importedObjCHeader,
                                       type: .objcHeader),
                         output: .init(file: bridgingPrecompiledHeader,
                                       type: .pch))
    )
  }

  private mutating func addEmitModuleJob(addJob: (Job) -> Void) throws {
    if shouldCreateEmitModuleJob {
      addJob( try emitModuleJob() )
    }
  }

  private mutating func addJobsFeedingLinker(
    addJob: (Job) -> Void
  ) throws -> [TypedVirtualPath] {

    var linkerInputs = [TypedVirtualPath]()
    func addLinkerInput(_ li: TypedVirtualPath) { linkerInputs.append(li) }

    var moduleInputs = [TypedVirtualPath]()
    let acceptBitcodeAsLinkerInput = lto == .llvmThin || lto == .llvmFull
    func addModuleInput(_ mi: TypedVirtualPath) { moduleInputs.append(mi) }
    var moduleInputsFromJobOutputs = [TypedVirtualPath]()
    func addModuleInputFromJobOutputs(_ mis: TypedVirtualPath) {
      moduleInputsFromJobOutputs.append(mis) }

    func addJobOutputs(_ jobOutputs: [TypedVirtualPath]) {
      for jobOutput in jobOutputs {
        switch jobOutput.type {
          case .object, .autolink:
            addLinkerInput(jobOutput)
          case .llvmBitcode where acceptBitcodeAsLinkerInput:
            addLinkerInput(jobOutput)
          case .swiftModule:
            addModuleInputFromJobOutputs(jobOutput)

          default:
            break
        }
      }
    }

    try addSingleCompileJobs(addJob: addJob,
                             addJobOutputs: addJobOutputs)

    try addJobsForPrimaryInputs(
      addJob: addJob,
      addModuleInput: addModuleInput,
      addLinkerInput: addLinkerInput,
      addJobOutputs: addJobOutputs)

    try addAutolinkExtractJob(linkerInputs: linkerInputs,
                              addLinkerInput: addLinkerInput,
                              addJob: addJob)

    if let mergeJob = try mergeModuleJob(
        moduleInputs: moduleInputs,
        moduleInputsFromJobOutputs: moduleInputsFromJobOutputs) {
      addJob(mergeJob)
      try addVerifyJobs(mergeJob: mergeJob, addJob: addJob)
      try addWrapJobOrMergeOutputs(
        mergeJob: mergeJob,
        debugInfo: debugInfo,
        addJob: addJob,
        addLinkerInput: addLinkerInput)
    }
    return linkerInputs
  }

  private mutating func addSingleCompileJobs(
    addJob: (Job) -> Void,
    addJobOutputs: ([TypedVirtualPath]) -> Void
  ) throws {
    guard case .singleCompile = compilerMode
    else { return }

    if parsedOptions.hasArgument(.embedBitcode),
       inputFiles.allSatisfy({ $0.type.isPartOfSwiftCompilation })
      {
        let job = try compileJob(primaryInputs: [],
                                 outputType: .llvmBitcode,
                                 addJobOutputs: addJobOutputs,
                                 emitModuleTrace: loadedModuleTracePath != nil)
        addJob(job)

        for input in job.outputs.filter({ $0.type == .llvmBitcode }) {
          let job = try backendJob(input: input, addJobOutputs: addJobOutputs)
          addJob(job)
        }
        return
      }
      // Create a single compile job for all of the files, none of which
      // are primary.
      let job = try compileJob(primaryInputs: [],
                               outputType: compilerOutputType,
                               addJobOutputs: addJobOutputs,
                               emitModuleTrace: loadedModuleTracePath != nil)
      addJob(job)
  }

  private mutating func addJobsForPrimaryInputs(
    addJob: (Job) -> Void,
    addModuleInput: (TypedVirtualPath) -> Void,
    addLinkerInput: (TypedVirtualPath) -> Void,
    addJobOutputs: ([TypedVirtualPath]) -> Void)
  throws {
    let partitions = batchPartitions()
    // Log life cycle for added batch job
    if parsedOptions.hasArgument(.driverShowJobLifecycle) {
      for input in inputFiles {
        if let idx = partitions?.assignment[input] {
          stdoutStream.write("Adding {compile: \(input.file.basename)} to batch \(idx)\n")
          stdoutStream.flush()
        }
      }
    }
    for (index, input) in inputFiles.enumerated() {
      // Only emit a loaded module trace from the first frontend job.
      let emitModuleTrace = (index == inputFiles.startIndex) && (loadedModuleTracePath != nil)
      try addJobs(
        forPrimaryInput: input,
        partitions: partitions,
        addJob: addJob,
        addModuleInput: addModuleInput,
        addLinkerInput: addLinkerInput,
        addJobOutputs: addJobOutputs,
        emitModuleTrace: emitModuleTrace)
    }
  }

  private mutating func addJobs(
    forPrimaryInput input: TypedVirtualPath,
    partitions: BatchPartitions?,
    addJob: (Job) -> Void,
    addModuleInput: (TypedVirtualPath) -> Void,
    addLinkerInput: (TypedVirtualPath) -> Void,
    addJobOutputs: ([TypedVirtualPath]) -> Void,
    emitModuleTrace: Bool
  ) throws
  {
    switch input.type {
    case .swift, .sil, .sib:
      // Generate a compile job for primary inputs here.
      guard compilerMode.usesPrimaryFileInputs else { break }

      var primaryInputs: [TypedVirtualPath]
      if let partitions = partitions, let partitionIdx = partitions.assignment[input] {
        // We have a partitioning for batch mode. If this input file isn't the first
        // file in the partition, skip it: it's been accounted for already.
        let partition = partitions.partitions[partitionIdx]
        if partition[0] != input {
          return
        }

        if parsedOptions.hasArgument(.driverShowJobLifecycle) {
          stdoutStream.write("Forming batch job from \(partition.count) constituents\n")
          stdoutStream.flush()
        }

        primaryInputs = partitions.partitions[partitionIdx]
      } else {
        primaryInputs = [input]
      }

      if parsedOptions.hasArgument(.embedBitcode) {
        let job = try compileJob(primaryInputs: primaryInputs,
                                 outputType: .llvmBitcode,
                                 addJobOutputs: addJobOutputs,
                                 emitModuleTrace: emitModuleTrace)
        addJob(job)
        for input in job.outputs.filter({ $0.type == .llvmBitcode }) {
          let job = try backendJob(input: input, addJobOutputs: addJobOutputs)
          addJob(job)
        }
      } else {
        let job = try compileJob(primaryInputs: primaryInputs,
                                 outputType: compilerOutputType,
                                 addJobOutputs: addJobOutputs,
                                 emitModuleTrace: emitModuleTrace)
        addJob(job)
      }

    case .object, .autolink, .llvmBitcode:
      if linkerOutputType != nil {
        addLinkerInput(input)
      } else {
        diagnosticEngine.emit(.error_unexpected_input_file(input.file))
      }

    case .swiftModule, .swiftDocumentation:
      if moduleOutputInfo.output != nil && linkerOutputType == nil {
        // When generating a .swiftmodule as a top-level output (as opposed
        // to, for example, linking an image), treat .swiftmodule files as
        // inputs to a MergeModule action.
        addModuleInput(input)
      } else if linkerOutputType != nil {
        // Otherwise, if linking, pass .swiftmodule files as inputs to the
        // linker, so that their debug info is available.
        addLinkerInput(input)
      } else {
        diagnosticEngine.emit(.error_unexpected_input_file(input.file))
      }

    default:
      diagnosticEngine.emit(.error_unexpected_input_file(input.file))
    }
  }

  /// Need a merge module job if there are module inputs
  private mutating func mergeModuleJob(
    moduleInputs: [TypedVirtualPath],
    moduleInputsFromJobOutputs: [TypedVirtualPath]
  ) throws -> Job? {
    guard moduleOutputInfo.output != nil,
          !(moduleInputs.isEmpty && moduleInputsFromJobOutputs.isEmpty),
          compilerMode.usesPrimaryFileInputs
    else { return nil }
    return try mergeModuleJob(inputs: moduleInputs, inputsFromOutputs: moduleInputsFromJobOutputs)
  }

  private mutating func addVerifyJobs(mergeJob: Job, addJob: (Job) -> Void )
  throws {
    guard
       parsedOptions.hasArgument(.enableLibraryEvolution),
       parsedOptions.hasFlag(positive: .verifyEmittedModuleInterface,
                             negative: .noVerifyEmittedModuleInterface,
                             default: false)
    else { return }

    func addVerifyJob(forPrivate: Bool) throws {
      let isNeeded =
        forPrivate
        ? parsedOptions.hasArgument(.emitPrivateModuleInterfacePath)
        : parsedOptions.hasArgument(.emitModuleInterface, .emitModuleInterfacePath)
      guard isNeeded else { return }

      let outputType: FileType =
        forPrivate ? .privateSwiftInterface : .swiftInterface
      let mergeInterfaceOutputs = mergeJob.outputs.filter { $0.type == outputType }
      assert(mergeInterfaceOutputs.count == 1,
             "Merge module job should only have one swiftinterface output")
      let job = try verifyModuleInterfaceJob(interfaceInput: mergeInterfaceOutputs[0])
      addJob(job)
    }
    try addVerifyJob(forPrivate: false)
    try addVerifyJob(forPrivate: true )
  }

  private mutating func addAutolinkExtractJob(
    linkerInputs: [TypedVirtualPath],
    addLinkerInput: (TypedVirtualPath) -> Void,
    addJob: (Job) -> Void)
  throws
  {
    let autolinkInputs = linkerInputs.filter { $0.type == .object }
    if let autolinkExtractJob = try autolinkExtractJob(inputs: autolinkInputs) {
      addJob(autolinkExtractJob)
      autolinkExtractJob.outputs.forEach(addLinkerInput)
    }
  }

  private mutating func addWrapJobOrMergeOutputs(mergeJob: Job,
                                                 debugInfo: DebugInfo,
                                                 addJob: (Job) -> Void,
                                                 addLinkerInput: (TypedVirtualPath) -> Void)
  throws {
    guard case .astTypes = debugInfo.level
    else { return }
    if targetTriple.objectFormat != .macho {
      // Module wrapping is required.
      let mergeModuleOutputs = mergeJob.outputs.filter { $0.type == .swiftModule }
      assert(mergeModuleOutputs.count == 1,
             "Merge module job should only have one swiftmodule output")
      let wrapJob = try moduleWrapJob(moduleInput: mergeModuleOutputs[0])
      addJob(wrapJob)
      wrapJob.outputs.forEach(addLinkerInput)
    } else {
      mergeJob.outputs.forEach(addLinkerInput)
    }
  }

  private mutating func addLinkAndPostLinkJobs(
    linkerInputs: [TypedVirtualPath],
    debugInfo: DebugInfo,
    addJob: (Job) -> Void)
  throws {
    guard linkerOutputType != nil && !linkerInputs.isEmpty
    else { return }

    let linkJ = try linkJob(inputs: linkerInputs)
    addJob(linkJ)
    guard targetTriple.isDarwin, debugInfo.level != nil
    else {return }

    let dsymJob = try generateDSYMJob(inputs: linkJ.outputs)
    addJob(dsymJob)
    if debugInfo.shouldVerify {
      addJob(try verifyDebugInfoJob(inputs: dsymJob.outputs))
    }
  }

  /// Prescan the source files to produce a module dependency graph and turn it into a set
  /// of jobs required to build all dependencies.
  /// Preprocess the graph by resolving placeholder dependencies, if any are present and
  /// by re-scanning all Clang modules against all possible targets they will be built against.
  public mutating func generateExplicitModuleDependenciesJobs() throws -> [Job] {
    let dependencyGraph = try generateInterModuleDependencyGraph()
    explicitModuleBuildHandler =
        try ExplicitModuleBuildHandler(dependencyGraph: dependencyGraph,
                                       toolchain: toolchain)
    return try explicitModuleBuildHandler!.generateExplicitModuleDependenciesBuildJobs()
  }

  private mutating func generateInterModuleDependencyGraph() throws -> InterModuleDependencyGraph {
    let dependencyScannerJob = try dependencyScanningJob()
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)

    var dependencyGraph =
      try self.executor.execute(job: dependencyScannerJob,
                                capturingJSONOutputAs: InterModuleDependencyGraph.self,
                                forceResponseFiles: forceResponseFiles,
                                recordedInputModificationDates: recordedInputModificationDates)

    // Resolve placeholder dependencies in the dependency graph, if any.
    if externalBuildArtifacts != nil, !externalBuildArtifacts!.0.isEmpty {
      try dependencyGraph.resolvePlaceholderDependencies(using: externalBuildArtifacts!)
    }

    // Re-scan Clang modules at all the targets they will be built against.
    try resolveVersionedClangDependencies(dependencyGraph: &dependencyGraph)

    // Set dependency modules' paths to be saved in the module cache.
    try updateDependencyModulesWithModuleCachePath(dependencyGraph: &dependencyGraph)

    return dependencyGraph
  }

  /// Update the given inter-module dependency graph to set module paths to be within the module cache,
  /// if one is present.
  private mutating func updateDependencyModulesWithModuleCachePath(dependencyGraph:
                                                                    inout InterModuleDependencyGraph)
  throws {
    let moduleCachePath = parsedOptions.getLastArgument(.moduleCachePath)?.asSingle
    if moduleCachePath != nil {
      for (moduleId, moduleInfo) in dependencyGraph.modules {
        // Output path on the main module is determined by the invocation arguments.
        guard moduleId.moduleName != dependencyGraph.mainModuleName else {
          continue
        }
        let modulePath = moduleInfo.modulePath
        // Only update paths on modules which do not already specify a path beyond their module name
        // and a file extension.
        if modulePath == moduleId.moduleName + ".swiftmodule" ||
            modulePath == moduleId.moduleName + ".pcm" {
          // Use VirtualPath to get the OS-specific path separators right.
          let modulePathInCache =
            try VirtualPath(path: moduleCachePath!).appending(component: modulePath).description
          dependencyGraph.modules[moduleId]!.modulePath = modulePathInCache
        }
      }
    }
  }

}

/// MARK: Planning
extension Driver {
  /// Create a job if needed for simple requests that can be immediately
  /// forwarded to the frontend.
  public mutating func immediateForwardingJob() throws -> Job? {
    if parsedOptions.hasArgument(.printTargetInfo) {
      let sdkPath = try parsedOptions.getLastArgument(.sdk).map { try VirtualPath(path: $0.asSingle) }
      let resourceDirPath = try parsedOptions.getLastArgument(.resourceDir).map { try VirtualPath(path: $0.asSingle) }
      var useStaticResourceDir = false
      if parsedOptions.hasFlag(positive: .staticExecutable,
                              negative: .noStaticExecutable,
                              default: false) ||
         parsedOptions.hasFlag(positive: .staticStdlib,
                              negative: .noStaticStdlib,
                              default: false) {
        useStaticResourceDir = true
      }

      return try toolchain.printTargetInfoJob(target: targetTriple,
                                              targetVariant: targetVariantTriple,
                                              sdkPath: sdkPath,
                                              resourceDirPath: resourceDirPath,
                                              requiresInPlaceExecution: true,
                                              useStaticResourceDir: useStaticResourceDir,
                                              swiftCompilerPrefixArgs: swiftCompilerPrefixArgs)
    }

    if parsedOptions.hasArgument(.version) || parsedOptions.hasArgument(.version_) {
      return Job(
        moduleName: moduleOutputInfo.name,
        kind: .versionRequest,
        tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
        commandLine: [.flag("--version")],
        inputs: [],
        primaryInputs: [],
        outputs: [],
        requiresInPlaceExecution: true)
    }

    if parsedOptions.contains(.help) || parsedOptions.contains(.helpHidden) {
      var commandLine: [Job.ArgTemplate] = [.flag("-tool=\(driverKind.rawValue)")]
      if parsedOptions.contains(.helpHidden) {
        commandLine.append(.flag("-show-hidden"))
      }
      return Job(
        moduleName: moduleOutputInfo.name,
        kind: .help,
        tool: .absolute(try toolchain.getToolPath(.swiftHelp)),
        commandLine: commandLine,
        inputs: [],
        primaryInputs: [],
        outputs: [],
        requiresInPlaceExecution: true)
    }

    return nil
  }

  /// Plan a build by producing a set of jobs to complete the build.
  public mutating func planBuild() throws -> [Job] {

    if let job = try immediateForwardingJob() {
      return [job]
    }

    // The REPL doesn't require input files, but all other modes do.
    guard !inputFiles.isEmpty || compilerMode == .repl else {
      if parsedOptions.hasArgument(.v) {
        // `swiftc -v` is allowed and prints version information.
        return []
      }
      throw Error.noInputFiles
    }

    // Plan the build.
    switch compilerMode {
    case .repl:
      if !inputFiles.isEmpty {
        throw PlanningError.replReceivedInput
      }
      return [try replJob()]

    case .immediate:
      return [try interpretJob(inputs: inputFiles)]

    case .standardCompile, .batchCompile, .singleCompile:
      return try planStandardCompile()

    case .compilePCM:
      if inputFiles.count != 1 {
        throw PlanningError.emitPCMWrongInputFiles
      }
      return [try generatePCMJob(input: inputFiles.first!)]
    }
  }
}

extension Diagnostic.Message {
  static func error_unexpected_input_file(_ file: VirtualPath) -> Diagnostic.Message {
    .error("unexpected input file: \(file.name)")
  }
}

// MARK: Batch mode
extension Driver {
  /// Determine the number of partitions we'll use for batch mode.
  private func numberOfBatchPartitions(
    _ info: BatchModeInfo,
    swiftInputFiles: [TypedVirtualPath]
  ) -> Int {
    // If the number of partitions was specified by the user, use it
    if let fixedCount = info.count {
      return fixedCount
    }

    // This is a long comment to justify a simple calculation.
    //
    // Because there is a secondary "outer" build system potentially also
    // scheduling multiple drivers in parallel on separate build targets
    // -- while we, the driver, schedule our own subprocesses -- we might
    // be creating up to $NCPU^2 worth of _memory pressure_.
    //
    // Oversubscribing CPU is typically no problem these days, but
    // oversubscribing memory can lead to paging, which on modern systems
    // is quite bad.
    //
    // In practice, $NCPU^2 processes doesn't _quite_ happen: as core
    // count rises, it usually exceeds the number of large targets
    // without any dependencies between them (which are the only thing we
    // have to worry about): you might have (say) 2 large independent
    // modules * 2 architectures, but that's only an $NTARGET value of 4,
    // which is much less than $NCPU if you're on a 24 or 36-way machine.
    //
    //  So the actual number of concurrent processes is:
    //
    //     NCONCUR := $NCPU * min($NCPU, $NTARGET)
    //
    // Empirically, a frontend uses about 512kb RAM per non-primary file
    // and about 10mb per primary. The number of non-primaries per
    // process is a constant in a given module, but the number of
    // primaries -- the "batch size" -- is inversely proportional to the
    // batch count (default: $NCPU). As a result, the memory pressure
    // we can expect is:
    //
    //  $NCONCUR * (($NONPRIMARYMEM * $NFILE) +
    //              ($PRIMARYMEM * ($NFILE/$NCPU)))
    //
    // If we tabulate this across some plausible values, we see
    // unfortunate memory-pressure results:
    //
    //                          $NFILE
    //                  +---------------------
    //  $NTARGET $NCPU  |  100    500    1000
    //  ----------------+---------------------
    //     2        2   |  2gb   11gb    22gb
    //     4        4   |  4gb   24gb    48gb
    //     4        8   |  5gb   28gb    56gb
    //     4       16   |  7gb   36gb    72gb
    //     4       36   | 11gb   56gb   112gb
    //
    // As it happens, the lower parts of the table are dominated by
    // number of processes rather than the files-per-batch (the batches
    // are already quite small due to the high core count) and the left
    // side of the table is dealing with modules too small to worry
    // about. But the middle and upper-right quadrant is problematic: 4
    // and 8 core machines do not typically have 24-48gb of RAM, it'd be
    // nice not to page on them when building a 4-target project with
    // 500-file modules.
    //
    // Turns we can do that if we just cap the batch size statically at,
    // say, 25 files per batch, we get a better formula:
    //
    //  $NCONCUR * (($NONPRIMARYMEM * $NFILE) +
    //              ($PRIMARYMEM * min(25, ($NFILE/$NCPU))))
    //
    //                          $NFILE
    //                  +---------------------
    //  $NTARGET $NCPU  |  100    500    1000
    //  ----------------+---------------------
    //     2        2   |  1gb    2gb     3gb
    //     4        4   |  4gb    8gb    12gb
    //     4        8   |  5gb   16gb    24gb
    //     4       16   |  7gb   32gb    48gb
    //     4       36   | 11gb   56gb   108gb
    //
    // This means that the "performance win" of batch mode diminishes
    // slightly: the batching factor in the equation drops from
    // ($NFILE/$NCPU) to min(25, $NFILE/$NCPU). In practice this seems to
    // not cost too much: the additional factor in number of subprocesses
    // run is the following:
    //
    //                          $NFILE
    //                  +---------------------
    //  $NTARGET $NCPU  |  100    500    1000
    //  ----------------+---------------------
    //     2        2   |  2x    10x      20x
    //     4        4   |   -     5x      10x
    //     4        8   |   -   2.5x       5x
    //     4       16   |   -  1.25x     2.5x
    //     4       36   |   -      -     1.1x
    //
    // Where - means "no difference" because the batches were already
    // smaller than 25.
    //
    // Even in the worst case here, the 1000-file module on 2-core
    // machine is being built with only 40 subprocesses, rather than the
    // pre-batch-mode 1000. I.e. it's still running 96% fewer
    // subprocesses than before. And significantly: it's doing so while
    // not exceeding the RAM of a typical 2-core laptop.

    // An explanation of why the partition calculation isn't integer
    // division. Using an example, a module of 26 files exceeds the
    // limit of 25 and must be compiled in 2 batches. Integer division
    // yields 26/25 = 1 batch, but a single batch of 26 exceeds the
    // limit. The calculation must round up, which can be calculated
    // using: `(x + y - 1) / y`
    let divideRoundingUp = { num, div in
        return (num + div - 1) / div
    }

    let defaultSizeLimit = 25
    let numInputFiles = swiftInputFiles.count
    let sizeLimit = info.sizeLimit ?? defaultSizeLimit

    let numTasks = numParallelJobs ?? 1
    return max(numTasks, divideRoundingUp(numInputFiles, sizeLimit))
  }

  /// Describes the partitions used when batching.
  private struct BatchPartitions {
    /// Assignment of each Swift input file to a particular partition.
    /// The values are indices into `partitions`.
    let assignment: [TypedVirtualPath : Int]

    /// The contents of each partition.
    let partitions: [[TypedVirtualPath]]
  }

  /// Compute the partitions we'll use for batch mode.
  private func batchPartitions() -> BatchPartitions? {
    guard case let .batchCompile(info) = compilerMode
    else { return nil }

    let swiftInputFiles = inputFiles.filter { inputFile in
      inputFile.type.isPartOfSwiftCompilation
    }
    let numPartitions = numberOfBatchPartitions(info, swiftInputFiles: swiftInputFiles)

    if parsedOptions.hasArgument(.driverShowJobLifecycle) {
      stdoutStream.write("Found \(swiftInputFiles.count) batchable jobs\n")
      stdoutStream.write("Forming into \(numPartitions) batches\n")
      stdoutStream.flush()
    }

    // If there is only one partition, fast path.
    if numPartitions == 1 {
      var assignment = [TypedVirtualPath: Int]()
      for input in swiftInputFiles {
        assignment[input] = 0
      }
      return BatchPartitions(assignment: assignment, partitions: [swiftInputFiles])
    }

    // Map each input file to a partition index. Ensure that we evenly
    // distribute the remainder.
    let numInputFiles = swiftInputFiles.count
    let remainder = numInputFiles % numPartitions
    let targetSize = numInputFiles / numPartitions
    var partitionIndices: [Int] = []
    for partitionIdx in 0..<numPartitions {
      let fillCount = targetSize + (partitionIdx < remainder ? 1 : 0)
      partitionIndices.append(contentsOf: Array(repeating: partitionIdx, count: fillCount))
    }
    assert(partitionIndices.count == numInputFiles)

    if let seed = info.seed {
      var generator = PredictableRandomNumberGenerator(seed: UInt64(seed))
      partitionIndices.shuffle(using: &generator)
    }

    // Form the actual partitions.
    var assignment: [TypedVirtualPath : Int] = [:]
    var partitions = Array<[TypedVirtualPath]>(repeating: [], count: numPartitions)
    for (fileIndex, file) in swiftInputFiles.enumerated() {
      let partitionIdx = partitionIndices[fileIndex]
      assignment[file] = partitionIdx
      partitions[partitionIdx].append(file)
    }

    return BatchPartitions(assignment: assignment, partitions: partitions)
  }
}
