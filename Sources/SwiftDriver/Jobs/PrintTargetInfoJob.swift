//===----------- PrintTargetInfoJob.swift - Swift Target Info Job ---------===//
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


extension Toolchain {
  func printTargetInfoJob(target: Triple?,
                          targetVariant: Triple?,
                          sdkPath: VirtualPath? = nil,
                          resourceDirPath: VirtualPath? = nil,
                          requiresInPlaceExecution: Bool = false) throws -> Job {
    var commandLine: [Job.ArgTemplate] = [.flag("-frontend"),
                                          .flag("-print-target-info")]
    // If we were given a target, include it. Otherwise, let the frontend
    // tell us the host target.
    if let target = target {
      commandLine += [.flag("-target"), .flag(target.triple)]
    }

    // If there is a target variant, include that too.
    if let targetVariant = targetVariant {
      commandLine += [.flag("-target-variant"), .flag(targetVariant.triple)]
    }

    if let sdkPath = sdkPath {
      commandLine += [.flag("-sdk"), .path(sdkPath)]
    }

    if let resourceDirPath = resourceDirPath {
      commandLine += [.flag("-resource-dir"), .path(resourceDirPath)]
    }

    return Job(
      moduleName: "",
      kind: .printTargetInfo,
      tool: .absolute(try getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      displayInputs: [],
      inputs: [],
      outputs: [.init(file: .standardOutput, type: .jsonTargetInfo)],
      requiresInPlaceExecution: requiresInPlaceExecution,
      supportsResponseFiles: false
    )
  }
}
