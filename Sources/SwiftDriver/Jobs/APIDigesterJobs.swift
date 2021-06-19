//===- APIDigesterJobs.swift - Baseline Generation and API/ABI Comparison -===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic

enum DigesterMode {
  case api, abi

  var baselineFileType: FileType {
    switch self {
    case .api:
      return .jsonAPIBaseline
    case .abi:
      return .jsonABIBaseline
    }
  }

  var baselineGenerationJobKind: Job.Kind {
    switch self {
    case .api:
      return .generateAPIBaseline
    case .abi:
      return .generateABIBaseline
    }
  }
}

extension Driver {
  mutating func digesterBaselineGenerationJob(modulePath: VirtualPath.Handle, outputPath: VirtualPath.Handle, mode: DigesterMode) throws -> Job {
    var commandLine = [Job.ArgTemplate]()
    commandLine.appendFlag("-dump-sdk")

    if mode == .abi {
      commandLine.appendFlag("-abi")
    }

    commandLine.appendFlag("-module")
    commandLine.appendFlag(moduleOutputInfo.name)

    commandLine.appendFlag(.I)
    commandLine.appendPath(VirtualPath.lookup(modulePath).parentDirectory)

    commandLine.appendFlag(.target)
    commandLine.appendFlag(targetTriple.triple)

    if let sdkPath = frontendTargetInfo.sdkPath?.path {
      commandLine.appendFlag(.sdk)
      commandLine.append(.path(VirtualPath.lookup(sdkPath)))
    }

    // Resource directory.
    commandLine.appendFlag(.resourceDir)
    commandLine.appendPath(VirtualPath.lookup(frontendTargetInfo.runtimeResourcePath.path))

    try commandLine.appendAll(.I, from: &parsedOptions)
    try commandLine.appendAll(.F, from: &parsedOptions)
    for systemFramework in parsedOptions.arguments(for: .Fsystem) {
      commandLine.appendFlag(.iframework)
      commandLine.appendFlag(systemFramework.argument.asSingle)
    }

    try commandLine.appendLast(.swiftVersion, from: &parsedOptions)

    commandLine.appendFlag(.o)
    commandLine.appendPath(VirtualPath.lookup(outputPath))

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: mode.baselineGenerationJobKind,
      tool: .absolute(try toolchain.getToolPath(.swiftAPIDigester)),
      commandLine: commandLine,
      inputs: [.init(file: modulePath, type: .swiftModule)],
      primaryInputs: [],
      outputs: [.init(file: outputPath, type: mode.baselineFileType)],
      supportsResponseFiles: true
    )
  }
}
