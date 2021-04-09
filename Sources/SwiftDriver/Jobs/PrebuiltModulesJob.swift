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

public struct PrebuiltModuleInput {
  // The path to the input/output of the a module building task.
  let path: TypedVirtualPath
  // The arch infered from the file name.
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
    let canonicalName = sdkInfo.canonicalName
    func extractVersion(_ platform: String) -> Substring? {
      if canonicalName.starts(with: platform) {
        return canonicalName.suffix(from: canonicalName.index(canonicalName.startIndex,
                                                              offsetBy: platform.count))
      }
      return nil
    }

    if let version = extractVersion("macosx") {
      return "arm64-apple-macosx\(version)"
    } else if let version = extractVersion("iphoneos") {
      return "arm64-apple-ios\(version)"
    } else if let version = extractVersion("iphonesimulator") {
      return "arm64-apple-ios\(version)-simulator"
    } else if let version = extractVersion("watchos") {
      return "armv7k-apple-watchos\(version)"
    } else if let version = extractVersion("watchsimulator") {
      return "arm64-apple-watchos\(version)-simulator"
    } else if let version = extractVersion("appletvos") {
      return "arm64-apple-tvos\(version)"
    } else if let version = extractVersion("appletvsimulator") {
      return "arm64-apple-tvos\(version)-simulator"
    } else {
      diagEngine.emit(error: "unhandled platform name: \(canonicalName)")
      return ""
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

extension Driver {

  private mutating func generateSingleModuleBuildingJob(_ moduleName: String,  _ prebuiltModuleDir: AbsolutePath,
                                                        _ inputPath: PrebuiltModuleInput, _ outputPath: PrebuiltModuleOutput,
                                                        _ dependencies: [TypedVirtualPath]) throws -> Job {
    assert(inputPath.path.file.basenameWithoutExt == outputPath.path.file.basenameWithoutExt)
    func isIosMac(_ path: TypedVirtualPath) -> Bool {
      // Infer macabi interfaces by the file name.
      // FIXME: more robust way to do this.
      return path.file.basenameWithoutExt.contains("macabi")
    }
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
    if isIosMac(inputPath.path) {
      commandLine.appendFlag(.Fsystem)
      commandLine.append(.path(iosMacFrameworksSearchPath))
    }
    commandLine.appendFlag(.serializeParseableModuleInterfaceDependencyHashes)
    return Job(
      moduleName: moduleName,
      kind: .compile,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: dependencies,
      primaryInputs: [],
      outputs: [outputPath.path]
    )
  }

  public mutating func generatePrebuitModuleGenerationJobs(_ inputMap: [String: [PrebuiltModuleInput]],
                                                           _ prebuiltModuleDir: AbsolutePath) throws -> ([Job], [Job]) {
    assert(sdkPath != nil)
    // Run the dependency scanner and update the dependency oracle with the results
    let dependencyGraph = try gatherModuleDependencies()
    var jobs: [Job] = []
    var danglingJobs: [Job] = []
    var inputCount = 0
    // Create directories for each Swift module
    try inputMap.forEach {
      assert(!$0.value.isEmpty)
      try localFileSystem.createDirectory(prebuiltModuleDir
        .appending(RelativePath($0.key + ".swiftmodule")))
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

    func getDependenciesPaths(_ module: String, _ arch: Triple.Arch) throws -> [TypedVirtualPath] {
      var results: [TypedVirtualPath] = []
      let info = dependencyGraph.modules[.swift(module)]!
      guard let dependencies = info.directDependencies else {
        return results
      }

      for dep in dependencies {
        if case let .swift(moduleName) = dep {
          if let outputs = outputMap[moduleName] {
            // Depending only those .swiftmodule files with the same arch kind.
            // FIXME: handling arm64 and arm64e specifically.
            let selectOutputs = outputs.filter ({ $0.arch == arch }).map { $0.path }
            results.append(contentsOf: selectOutputs)
          }
        }
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
          try action(inputPaths[i], outputPaths[i])
        }
      }
    }
    // Keep track of modules that are not handled.
    var unhandledModules = Set<String>(inputMap.keys)
    let moduleInfo = dependencyGraph.mainModule
    if let dependencies = moduleInfo.directDependencies {
      for dep in dependencies {
        switch dep {
        case .swift(let moduleName):
          // Removed moduleName from the list.
          unhandledModules.remove(moduleName)
          try forEachInputOutputPair(moduleName) {
            jobs.append(try generateSingleModuleBuildingJob(moduleName,
              prebuiltModuleDir, $0, $1,
              try getDependenciesPaths(moduleName, $0.arch)))
          }
        default:
          continue
        }
      }
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
        danglingJobs.append(try generateSingleModuleBuildingJob(moduleName,
          prebuiltModuleDir, input, output, []))
      }
    }

    // check we've generated jobs for all inputs
    assert(inputCount == jobs.count + danglingJobs.count)
    return (jobs, danglingJobs)
  }
}
