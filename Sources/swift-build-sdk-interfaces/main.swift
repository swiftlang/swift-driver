//===--------------- main.swift - swift-build-sdk-interfaces ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import SwiftDriverExecution
import SwiftDriver
import TSCLibc
import TSCBasic
import TSCUtility

let diagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler])

guard let sdkPathRaw = ProcessEnv.vars["SDKROOT"] else {
  diagnosticsEngine.emit(.error("need to set SDKROOT"))
  exit(1)
}

var rawOutputDir = ""
if let oid = CommandLine.arguments.firstIndex(of: "-o") {
  let dirId = oid.advanced(by: 1)
  if dirId < CommandLine.arguments.count {
    rawOutputDir = CommandLine.arguments[dirId]
  }
}
if rawOutputDir.isEmpty {
  diagnosticsEngine.emit(.error("need to specify -o"))
  exit(1)
}

class PrebuitGenDelegate: JobExecutionDelegate {
  var failingModules = Set<String>()
  var commandMap: [Int: String] = [:]
  func jobStarted(job: Job, arguments: [String], pid: Int) {
    commandMap[pid] = arguments.reduce("") { return $0 + " " + $1 }
  }

  var hasStdlibFailure: Bool {
    return failingModules.contains("Swift") || failingModules.contains("_Concurrency")
  }

  func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    switch result.exitStatus {
    case .terminated(code: let code):
      if code != 0 {
        failingModules.insert(job.moduleName)
        Driver.stdErrQueue.sync {
          stderrStream <<< "failed: " <<< commandMap[pid]! <<< "\n"
          stderrStream.flush()
        }
      }
    case .signalled:
      diagnosticsEngine.emit(.remark("\(job.moduleName) interrupted"))
    }
  }

  func jobSkipped(job: Job) {
    diagnosticsEngine.emit(.error("\(job.moduleName) skipped"))
  }
}
do {
  let sdkPath = try VirtualPath(path: sdkPathRaw).absolutePath!
  if !localFileSystem.exists(sdkPath) {
    diagnosticsEngine.emit(error: "cannot find sdk: \(sdkPath.pathString)")
    exit(1)
  }
  let collector = SDKPrebuiltModuleInputsCollector(sdkPath, diagnosticsEngine)
  var outputDir = try VirtualPath(path: rawOutputDir).absolutePath!
  // if the given output dir ends with 'prebuilt-modules', we should
  // append the SDK version number so all modules will built into
  // the SDK-versioned sub-directory.
  if outputDir.basename == "prebuilt-modules" {
    outputDir = outputDir.appending(RelativePath(collector.versionString))
  }
  if !localFileSystem.exists(outputDir) {
    try localFileSystem.createDirectory(outputDir)
  }
  let swiftcPathRaw = ProcessEnv.vars["SWIFT_EXEC"]
  var swiftcPath: AbsolutePath
  if let swiftcPathRaw = swiftcPathRaw {
    swiftcPath = try VirtualPath(path: swiftcPathRaw).absolutePath!
  } else {
    swiftcPath = sdkPath.parentDirectory.parentDirectory.parentDirectory
      .parentDirectory.parentDirectory.appending(RelativePath("Toolchains"))
      .appending(RelativePath("XcodeDefault.xctoolchain")).appending(RelativePath("usr"))
      .appending(RelativePath("bin")).appending(RelativePath("swiftc"))
  }
  if !localFileSystem.exists(swiftcPath) {
    diagnosticsEngine.emit(error: "cannot find swift compiler: \(swiftcPath.pathString)")
    exit(1)
  }

  let sysVersionFile = outputDir.appending(component: "SystemVersion.plist")
  if localFileSystem.exists(sysVersionFile) {
    try localFileSystem.removeFileTree(sysVersionFile)
  }
  // Copy $SDK/System/Library/CoreServices/SystemVersion.plist file from the SDK
  // into the prebuilt module file to keep track of which SDK build we are generating
  // the modules from.
  try localFileSystem.copy(from: sdkPath.appending(component: "System")
                              .appending(component: "Library")
                              .appending(component: "CoreServices")
                              .appending(component: "SystemVersion.plist"),
                           to: sysVersionFile)
  let processSet = ProcessSet()
  let inputMap = try collector.collectSwiftInterfaceMap()
  let allModules = inputMap.keys
  try withTemporaryFile(suffix: ".swift") {
    let tempPath = $0.path
    try localFileSystem.writeFileContents(tempPath, body: {
      for module in allModules {
        $0 <<< "import " <<< module <<< "\n"
      }
    })
    let executor = try SwiftDriverExecutor(diagnosticsEngine: diagnosticsEngine,
                                           processSet: processSet,
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.vars)
    var driver = try Driver(args: ["swiftc",
                                   "-target", collector.targetTriple,
                                   tempPath.description,
                                   "-sdk", sdkPathRaw],
                            diagnosticsEngine: diagnosticsEngine,
                            executor: executor,
                            compilerExecutableDir: swiftcPath.parentDirectory)
    let (jobs, danglingJobs) = try driver.generatePrebuitModuleGenerationJobs(inputMap, outputDir)
    let delegate = PrebuitGenDelegate()
    do {
      try executor.execute(workload: DriverExecutorWorkload.init(jobs, nil, continueBuildingAfterErrors: true),
                           delegate: delegate, numParallelJobs: 128)
    } catch {
      // Only fail the process if stdlib failed
      if delegate.hasStdlibFailure {
        exit(1)
      }
    }
    do {
      try executor.execute(workload: DriverExecutorWorkload.init(danglingJobs, nil, continueBuildingAfterErrors: true), delegate: delegate, numParallelJobs: 128)
    } catch {
      // Failing of dangling jobs don't fail the process.
      exit(0)
    }
  }
} catch {
  print("error: \(error)")
  exit(1)
}
