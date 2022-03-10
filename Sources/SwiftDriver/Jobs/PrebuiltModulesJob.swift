//===----- PrebuiltModulesJob.swift - Swit prebuilt module Planning -------===//
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
import SwiftOptions

@_spi(Testing) public func isIosMacInterface(_ path: VirtualPath) throws -> Bool {
  let data = try localFileSystem.readFileContents(path).cString
  let myStrings = data.components(separatedBy: .newlines)
  let prefix = "// swift-module-flags: "
  if let argLine = myStrings.first(where: { $0.hasPrefix(prefix) }) {
    let args = argLine.dropFirst(prefix.count).components(separatedBy: " ")
    if let idx = args.firstIndex(of: "-target"), idx + 1 < args.count {
      return args[idx + 1].contains("macabi")
    }
  }
  return false
}

fileprivate func getErrKind(_ content: String) -> String {
  if content.contains("error: ") {
    return "err"
  } else if content.contains("warning: "){
    return "warn"
  } else {
    return "note"
  }
}

func isIosMac(_ path: VirtualPath) -> Bool {
  // Infer macabi interfaces by the file name.
  // FIXME: more robust way to do this.
  return path.basenameWithoutExt.contains("macabi")
}

fileprivate func getLastInputPath(_ job: Job) -> AbsolutePath {
  return job.inputs.last!.file.absolutePath!
}

fileprivate func logOutput(_ job: Job, _ result: ProcessResult, _ logPath: AbsolutePath?, _ stdout: Bool) throws {
  guard var logPath = logPath else {
    return
  }
  let content = stdout ? try result.utf8Output() : try result.utf8stderrOutput()
  guard !content.isEmpty else {
    return
  }

  let interfaceBase = getLastInputPath(job).basename
  let errKind = getErrKind(content)
  if interfaceBase.contains(".abi.json") {
    logPath = logPath.appending(component: "abi").appending(component: errKind)
  }
  if !localFileSystem.exists(logPath) {
    try localFileSystem.createDirectory(logPath, recursive: true)
  }
  let fileName = "\(job.moduleName)-\(interfaceBase)-\(stdout ? "out" : errKind).txt"
  try localFileSystem.writeFileContents(logPath.appending(component: fileName)) {
    $0 <<< content
  }
}

func printJobInfo(_ job: Job, _ start: Bool, _ verbose: Bool) {
  guard verbose else {
    return
  }
  Driver.stdErrQueue.sync {
    stderrStream <<< (start ? "started: " : "finished: ")
    stderrStream <<< getLastInputPath(job).pathString <<< "\n"
    stderrStream.flush()
  }
}

fileprivate class ModuleCompileDelegate: JobExecutionDelegate {
  var failingModules = Set<String>()
  var commandMap: [Int: String] = [:]
  let diagnosticsEngine: DiagnosticsEngine
  let verbose: Bool
  var failingCriticalOutputs: Set<VirtualPath>
  let logPath: AbsolutePath?
  public init(_ jobs: [Job], _ diagnosticsEngine: DiagnosticsEngine, _ verbose: Bool, _ logPath: AbsolutePath?) {
    self.diagnosticsEngine = diagnosticsEngine
    self.verbose = verbose
    self.failingCriticalOutputs = Set<VirtualPath>(jobs.compactMap(ModuleCompileDelegate.getCriticalOutput))
    self.logPath = logPath
  }

  /// Dangling jobs are macabi-only modules. We should run those jobs if foundation
  /// is built successfully for macabi.
  public var shouldRunDanglingJobs: Bool {
    return !failingCriticalOutputs.contains(where: isIosMac)
  }

  static func getCriticalOutput(_ job: Job) -> VirtualPath? {
    return job.moduleName == "Foundation" ? job.outputs[0].file : nil
  }

  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    commandMap[pid] = arguments.reduce("") { return $0 + " " + $1 }
    printJobInfo(job, true, verbose)
  }

  public var hasCriticalFailure: Bool {
    return !failingCriticalOutputs.isEmpty
  }

  public func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    switch result.exitStatus {
    case .terminated(code: let code):
      if code == 0 {
        printJobInfo(job, false, verbose)
        failingCriticalOutputs.remove(job.outputs[0].file)
      } else {
        failingModules.insert(job.moduleName)
        let result: String = try! result.utf8stderrOutput()
        Driver.stdErrQueue.sync {
          stderrStream <<< "failed: " <<< commandMap[pid]! <<< "\n"
          stderrStream <<< result <<< "\n"
          stderrStream.flush()
        }
      }
#if os(Windows)
    case .abnormal(let exception):
      diagnosticsEngine.emit(.remark("\(job.moduleName) exception: \(exception)"))
#else
    case .signalled:
      diagnosticsEngine.emit(.remark("\(job.moduleName) interrupted"))
#endif
    }
    do {
      try logOutput(job, result, logPath, true)
      try logOutput(job, result, logPath, false)
    } catch {
      Driver.stdErrQueue.sync {
        stderrStream <<< "Failed to generate log file"
        stderrStream.flush()
      }
    }
  }

  public func jobSkipped(job: Job) {
    diagnosticsEngine.emit(.error("\(job.moduleName) skipped"))
  }
  static func canHandle(job: Job) -> Bool {
    return job.kind == .compile
  }
}

fileprivate class ABICheckingDelegate: JobExecutionDelegate {
  let verbose: Bool
  let logPath: AbsolutePath?

  func jobSkipped(job: Job) {}

  public init(_ verbose: Bool, _ logPath: AbsolutePath?) {
    self.verbose = verbose
    self.logPath = logPath
  }
  static func canHandle(job: Job) -> Bool {
    return job.kind == .compareABIBaseline
  }

  func jobStarted(job: Job, arguments: [String], pid: Int) {
    printJobInfo(job, true, verbose)
  }

  func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    printJobInfo(job, false, verbose)
    do {
      try logOutput(job, result, logPath, false)
    } catch {
      Driver.stdErrQueue.sync {
        stderrStream <<< "Failed to generate log file"
        stderrStream.flush()
      }
    }
  }
}

public class PrebuitModuleGenerationDelegate: JobExecutionDelegate {

  fileprivate let compileDelegate: ModuleCompileDelegate
  fileprivate let abiCheckDelegate: ABICheckingDelegate

  private func selectDelegate(job: Job) -> JobExecutionDelegate {
    if ModuleCompileDelegate.canHandle(job: job) {
      return compileDelegate
    } else if ABICheckingDelegate.canHandle(job: job) {
      return abiCheckDelegate
    } else {
      fatalError("cannot handle job in PrebuitModuleGenerationDelegate")
    }
  }

  public init(_ jobs: [Job], _ diagnosticsEngine: DiagnosticsEngine,
              _ verbose: Bool, _ logPath: AbsolutePath?) {
    self.compileDelegate = ModuleCompileDelegate(jobs.filter(ModuleCompileDelegate.canHandle), diagnosticsEngine, verbose, logPath)
    self.abiCheckDelegate = ABICheckingDelegate(verbose, logPath)
  }

  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    selectDelegate(job: job).jobStarted(job: job, arguments: arguments, pid: pid)
  }

  public func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    selectDelegate(job: job).jobFinished(job: job, result: result, pid: pid)
  }

  public func jobSkipped(job: Job) {
    selectDelegate(job: job).jobSkipped(job: job)
  }
  public var shouldRunDanglingJobs: Bool {
    return compileDelegate.shouldRunDanglingJobs
  }
  public var hasCriticalFailure: Bool {
    return compileDelegate.hasCriticalFailure
  }
}

public struct PrebuiltModuleInput {
  // The path to the input/output of the a module building task.
  let path: TypedVirtualPath
  // The arch inferred from the file name.
  let arch: Triple.Arch
  init(_ path: TypedVirtualPath) {
    let baseName = path.file.basename
    let arch = baseName.prefix(upTo: baseName.firstIndex(where: { $0 == "-" || $0 == "." })!)
    self.init(path, Triple.Arch.parse(arch)!)
  }
  init(_ path: TypedVirtualPath, _ arch: Triple.Arch) {
    self.path = path
    self.arch = arch
  }
}

typealias PrebuiltModuleOutput = PrebuiltModuleInput

public struct SDKPrebuiltModuleInputsCollector {
  let sdkPath: AbsolutePath
  let nonFrameworkDirs = [RelativePath("usr/lib/swift"),
                          RelativePath("System/iOSSupport/usr/lib/swift")]
  let frameworkDirs = [RelativePath("System/Library/Frameworks"),
                      RelativePath("System/iOSSupport/System/Library/Frameworks")]
  let sdkInfo: DarwinToolchain.DarwinSDKInfo
  let diagEngine: DiagnosticsEngine
  public init(_ sdkPath: AbsolutePath, _ diagEngine: DiagnosticsEngine) {
    self.sdkPath = sdkPath
    self.sdkInfo = DarwinToolchain.readSDKInfo(localFileSystem,
                                               VirtualPath.absolute(sdkPath).intern())!
    self.diagEngine = diagEngine
  }

  public var versionString: String {
    return sdkInfo.versionString
  }

  // Returns a target triple that's proper to use with the given SDK path.
  public var targetTriple: String {
    let version = sdkInfo.versionString
    switch sdkInfo.platformKind {
    case .macosx:
      return "arm64-apple-macosx\(version)"
    case .iphoneos:
      return "arm64-apple-ios\(version)"
    case .iphonesimulator:
      return "arm64-apple-ios\(version)-simulator"
    case .watchos:
      return "armv7k-apple-watchos\(version)"
    case .watchsimulator:
      return "arm64-apple-watchos\(version)-simulator"
    case .appletvos:
      return "arm64-apple-tvos\(version)"
    case .appletvsimulator:
      return "arm64-apple-tvos\(version)-simulator"
    case .unknown:
      fatalError("unknown platform kind")
    }
  }

  private func sanitizeInterfaceMap(_ map: [String: [PrebuiltModuleInput]]) -> [String: [PrebuiltModuleInput]] {
    return map.filter {
      // Remove modules without associated .swiftinterface files and diagnose.
      if $0.value.isEmpty {
        diagEngine.emit(warning: "\($0.key) has no associated .swiftinterface files")
        return false
      }
      return true
    }
  }

  public func collectSwiftInterfaceMap() throws -> [String: [PrebuiltModuleInput]] {
    var results: [String: [PrebuiltModuleInput]] = [:]

    func updateResults(_ dir: AbsolutePath) throws {
      if !localFileSystem.exists(dir) {
        return
      }
      let moduleName = dir.basenameWithoutExt
      if results[moduleName] == nil {
        results[moduleName] = []
      }

      // Search inside a .swiftmodule directory for any .swiftinterface file, and
      // add the files into the dictionary.
      // Duplicate entries are discarded, otherwise llbuild will complain.
      try localFileSystem.getDirectoryContents(dir).forEach {
        let currentFile = AbsolutePath(dir, try VirtualPath(path: $0).relativePath!)
        if currentFile.extension == "swiftinterface" {
          let currentBaseName = currentFile.basenameWithoutExt
          let interfacePath = TypedVirtualPath(file: VirtualPath.absolute(currentFile).intern(),
                                               type: .swiftInterface)
          if !results[moduleName]!.contains(where: { $0.path.file.basenameWithoutExt == currentBaseName }) {
            results[moduleName]!.append(PrebuiltModuleInput(interfacePath))
          }
        }
        if currentFile.extension == "swiftmodule" {
          diagEngine.emit(warning: "found \(currentFile)")
        }
      }
    }
    // Search inside framework dirs in an SDK to find .swiftmodule directories.
    for dir in frameworkDirs {
      let frameDir = AbsolutePath(sdkPath, dir)
      if !localFileSystem.exists(frameDir) {
        continue
      }
      try localFileSystem.getDirectoryContents(frameDir).forEach {
        let frameworkPath = try VirtualPath(path: $0)
        if frameworkPath.extension != "framework" {
          return
        }
        let moduleName = frameworkPath.basenameWithoutExt
        let swiftModulePath = frameworkPath
          .appending(component: "Modules")
          .appending(component: moduleName + ".swiftmodule").relativePath!
        try updateResults(AbsolutePath(frameDir, swiftModulePath))
      }
    }
    // Search inside lib dirs in an SDK to find .swiftmodule directories.
    for dir in nonFrameworkDirs {
      let swiftModuleDir = AbsolutePath(sdkPath, dir)
      if !localFileSystem.exists(swiftModuleDir) {
        continue
      }
      try localFileSystem.getDirectoryContents(swiftModuleDir).forEach {
        if $0.hasSuffix(".swiftmodule") {
          try updateResults(AbsolutePath(swiftModuleDir, $0))
        }
      }
    }
    return sanitizeInterfaceMap(results)
  }
}

extension InterModuleDependencyGraph {
  func dumpDotGraph(_ path: AbsolutePath, _ includingPCM: Bool) throws {
    func isPCM(_ dep: ModuleDependencyId) -> Bool {
      switch dep {
      case .clang:
        return true
      default:
        return false
      }
    }
    func dumpModuleName(_ stream: WritableByteStream, _ dep: ModuleDependencyId) {
      switch dep {
      case .swift(let name):
        stream <<< "\"\(name).swiftmodule\""
      case .clang(let name):
        stream <<< "\"\(name).pcm\""
      default:
        break
      }
    }
    try localFileSystem.writeFileContents(path) {Stream in
      Stream <<< "digraph {\n"
      for key in modules.keys {
        switch key {
        case .swift(let name):
          if name == mainModuleName {
              break
          }
          fallthrough
        case .clang:
          if !includingPCM && isPCM(key) {
            break
          }
          modules[key]!.directDependencies?.forEach { dep in
            if !includingPCM && isPCM(dep) {
              return
            }
            dumpModuleName(Stream, key)
            Stream <<< " -> "
            dumpModuleName(Stream, dep)
            Stream <<< ";\n"
          }
        default:
          break
        }
      }
      Stream <<< "}\n"
    }
  }
}

extension Driver {

  fileprivate mutating func generateABICheckJob(_ moduleName: String,
                                                _ baselineABIDir: AbsolutePath,
                                                _ currentABI: TypedVirtualPath) throws -> Job? {
    let baselineABI = TypedVirtualPath(file: VirtualPath.absolute(baselineABIDir
      .appending(component: "\(moduleName).swiftmodule")
      .appending(component: currentABI.file.basename)).intern(), type: .jsonABIBaseline)
    guard try localFileSystem.exists(baselineABI.file) else {
      return nil
    }
    var commandLine: [Job.ArgTemplate] = []
    commandLine.appendFlag(.diagnoseSdk)
    commandLine.appendFlag(.inputPaths)
    commandLine.appendPath(baselineABI.file)
    commandLine.appendFlag(.inputPaths)
    commandLine.appendPath(currentABI.file)
    commandLine.appendFlag(.compilerStyleDiags)
    commandLine.appendFlag(.abi)
    commandLine.appendFlag(.swiftOnly)
    commandLine.appendFlag(.printModule)
    return Job(
      moduleName: moduleName,
      kind: .compareABIBaseline,
      tool: .absolute(try toolchain.getToolPath(.swiftAPIDigester)),
      commandLine: commandLine,
      inputs: [currentABI, baselineABI],
      primaryInputs: [],
      outputs: []
    )
  }

  private mutating func generateSingleModuleBuildingJob(_ moduleName: String,  _ prebuiltModuleDir: AbsolutePath,
                                                        _ inputPath: PrebuiltModuleInput, _ outputPath: PrebuiltModuleOutput,
                                                        _ dependencies: [TypedVirtualPath], _ currentABIDir: AbsolutePath?,
                                                        _ baselineABIDir: AbsolutePath?) throws -> [Job] {
    assert(inputPath.path.file.basenameWithoutExt == outputPath.path.file.basenameWithoutExt)
    var commandLine: [Job.ArgTemplate] = []
    commandLine.appendFlag(.compileModuleFromInterface)
    commandLine.appendFlag(.sdk)
    commandLine.append(.path(sdkPath!))
    commandLine.appendFlag(.prebuiltModuleCachePath)
    commandLine.appendPath(prebuiltModuleDir)
    commandLine.appendFlag(.moduleName)
    commandLine.appendFlag(moduleName)
    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath.path.file)
    commandLine.appendPath(inputPath.path.file)
    if moduleName == "Swift" {
      commandLine.appendFlag(.parseStdlib)
    }
    // Add macabi-specific search path.
    if try isIosMacInterface(inputPath.path.file) {
      commandLine.appendFlag(.Fsystem)
      commandLine.append(.path(iosMacFrameworksSearchPath))
    }
    // Use the specified module cache dir
    if let mcp = parsedOptions.getLastArgument(.moduleCachePath)?.asSingle {
      commandLine.appendFlag(.moduleCachePath)
      commandLine.append(.path(try VirtualPath(path: mcp)))
    }
    commandLine.appendFlag(.serializeParseableModuleInterfaceDependencyHashes)
    commandLine.appendFlag(.badFileDescriptorRetryCount)
    commandLine.appendFlag("30")
    var allOutputs: [TypedVirtualPath] = [outputPath.path]
    var allJobs: [Job] = []
    // Emit ABI descriptor if the output dir is given
    if let currentABIDir = currentABIDir, isFrontendArgSupported(.emitAbiDescriptorPath) {
      commandLine.appendFlag(.emitAbiDescriptorPath)
      // Derive ABI descriptor path from the prebuilt module path.
      let moduleABIDir = currentABIDir.appending(component: "\(moduleName).swiftmodule")
      if !localFileSystem.exists(moduleABIDir) {
        try localFileSystem.createDirectory(moduleABIDir, recursive: true)
      }
      let abiFilePath = VirtualPath.absolute(moduleABIDir.appending(component:
        outputPath.path.file.basename)).replacingExtension(with: .jsonABIBaseline).intern()
      let abiPath = TypedVirtualPath(file: abiFilePath, type: .jsonABIBaseline)
      commandLine.appendPath(abiPath.file)
      allOutputs.append(abiPath)
      if let baselineABIDir = baselineABIDir,
         let abiJob = try generateABICheckJob(moduleName, baselineABIDir, abiPath) {
        allJobs.append(abiJob)
      }
    }
    var allInputs = dependencies
    allInputs.append(inputPath.path)
    allJobs.append(Job(
      moduleName: moduleName,
      kind: .compile,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: allInputs,
      primaryInputs: [],
      outputs: allOutputs
    ))
    return allJobs
  }

  public mutating func generatePrebuitModuleGenerationJobs(with inputMap: [String: [PrebuiltModuleInput]],
                                                           into prebuiltModuleDir: AbsolutePath,
                                                           exhaustive: Bool,
                                                           dotGraphPath: AbsolutePath? = nil,
                                                           currentABIDir: AbsolutePath? = nil,
                                                           baselineABIDir: AbsolutePath? = nil) throws -> ([Job], [Job]) {
    assert(sdkPath != nil)
    // Run the dependency scanner and update the dependency oracle with the results
    // We only need Swift dependencies here, so we don't need to invoke gatherModuleDependencies,
    // which also resolves versioned clang modules.
    let dependencyGraph = try performDependencyScan()
    if let dotGraphPath = dotGraphPath {
      try dependencyGraph.dumpDotGraph(dotGraphPath, false)
    }
    var jobs: [Job] = []
    var danglingJobs: [Job] = []
    var inputCount = 0
    // Create directories for each Swift module
    try inputMap.forEach {
      assert(!$0.value.isEmpty)
      let moduleDir = prebuiltModuleDir.appending(RelativePath($0.key + ".swiftmodule"))
      if !localFileSystem.exists(moduleDir) {
        try localFileSystem.createDirectory(moduleDir)
      }
    }

    // Generate an outputMap from the inputMap for easy reference.
    let outputMap: [String: [PrebuiltModuleOutput]] =
      Dictionary.init(uniqueKeysWithValues: inputMap.map { key, value in
      let outputPaths: [PrebuiltModuleInput] = value.map {
        let path = prebuiltModuleDir.appending(RelativePath(key + ".swiftmodule"))
          .appending(RelativePath($0.path.file.basenameWithoutExt + ".swiftmodule"))
        return PrebuiltModuleOutput(TypedVirtualPath(file: VirtualPath.absolute(path).intern(),
                                                     type: .swiftModule), $0.arch)
      }
      inputCount += outputPaths.count
      return (key, outputPaths)
    })

    func collectSwiftModuleNames(_ ids: [ModuleDependencyId]) -> [String] {
      return ids.compactMap { id in
        if case .swift(let module) = id {
          return module
        }
        return nil
      }
    }

    func getSwiftDependencies(for module: String) -> [String] {
      let info = dependencyGraph.modules[.swift(module)]!
      guard let dependencies = info.directDependencies else {
        return []
      }
      return collectSwiftModuleNames(dependencies)
    }

    func getOutputPaths(withName modules: [String], loadableFor arch: Triple.Arch) throws -> [TypedVirtualPath] {
      var results: [TypedVirtualPath] = []
      modules.forEach { module in
        guard let allOutputs = outputMap[module] else {
          diagnosticEngine.emit(error: "cannot find output paths for \(module)")
          return
        }
        let allPaths = allOutputs.filter { output in
          if output.arch == arch {
            return true
          }
          // arm64e interfaces can be loded from an arm64 interface but not vice
          // versa.
          if arch == .aarch64 && output.arch == .aarch64e {
            return true
          }
          return false
        }.map { $0.path }
        results.append(contentsOf: allPaths)
      }
      return results
    }

    func forEachInputOutputPair(_ moduleName: String,
                                _ action: (PrebuiltModuleInput, PrebuiltModuleOutput) throws -> ()) throws {
      if let inputPaths = inputMap[moduleName] {
        let outputPaths = outputMap[moduleName]!
        assert(inputPaths.count == outputPaths.count)
        assert(!inputPaths.isEmpty)
        for i in 0..<inputPaths.count {
          let (input, output) = (inputPaths[i], outputPaths[i])
          assert(input.path.file.basenameWithoutExt == output.path.file.basenameWithoutExt)
          try action(input, output)
        }
      }
    }
    // Keep track of modules we haven't handled.
    var unhandledModules = Set<String>(inputMap.keys)
    if let importedModules = dependencyGraph.mainModule.directDependencies {
      // Start from those modules explicitly imported into the file under scanning
      var openModules = collectSwiftModuleNames(importedModules)
      var idx = 0
      while idx != openModules.count {
        let module = openModules[idx]
        let dependencies = getSwiftDependencies(for: module)
        try forEachInputOutputPair(module) { input, output in
          jobs.append(contentsOf: try generateSingleModuleBuildingJob(module,
            prebuiltModuleDir, input, output,
            try getOutputPaths(withName: dependencies, loadableFor: input.arch),
            currentABIDir, baselineABIDir))
        }
        // For each dependency, add to the list to handle if the list doesn't
        // contain this dependency.
        dependencies.forEach({ newModule in
          if !openModules.contains(newModule) {
            diagnosticEngine.emit(note: "\(newModule) is discovered.")
            openModules.append(newModule)
          }
        })
        unhandledModules.remove(module)
        idx += 1
      }
    }

    // We are done if we don't need to handle all inputs exhaustively.
    if !exhaustive {
      return (jobs, [])
    }
    // For each unhandled module, generate dangling jobs for each associated
    // interfaces.
    // The only known usage of this so for is in macosx SDK where some collected
    // modules are only for macabi. The file under scanning is using a target triple
    // of mac native so those macabi-only modules cannot be found by the scanner.
    // We have to handle those modules separately without any dependency info.
    try unhandledModules.forEach { moduleName in
      diagnosticEngine.emit(warning: "handle \(moduleName) as dangling jobs")
      try forEachInputOutputPair(moduleName) { input, output in
        danglingJobs.append(contentsOf: try generateSingleModuleBuildingJob(moduleName,
          prebuiltModuleDir, input, output, [], currentABIDir, baselineABIDir))
      }
    }
    // check we've generated jobs for all inputs
    assert(inputCount == jobs.filter { $0.kind == .compile }.count +
           danglingJobs.filter { $0.kind == .compile }.count)
    return (jobs, danglingJobs)
  }
}
