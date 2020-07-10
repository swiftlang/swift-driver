//===--------------- JITBuildJob.swift - Swift JIT Build Job --------------===//
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

extension Driver {
  /// A frontend job that will provide JIT code for an executable.
  mutating func frontendJITBuildJob() throws -> Job {
    var commandLine = swiftCompilerPrefixArgs.map(Job.ArgTemplate.flag)
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-jit-build")

    // Add the frontend inputs. Note we don't output anything – the stub
    // executable output will be created separately.
    var inputs: [TypedVirtualPath] = []
    _ = addCompileInputs(primaryInputs: [], inputs: &inputs, outputType: nil,
                         commandLine: &commandLine)
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .frontendJITBuild,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: []
    )
  }

  /// Retrieve the jobs needed to generate a stub executable with a frontend
  /// process registered to JIT code for it.
  public mutating func generateJITCompileJobs() throws -> [Job] {
    // Ask the toolchain for the jit stub executable.
    let rawStubPath = try toolchain.getToolPath(.jitStub)
    let stubPath = TypedVirtualPath(file: .absolute(rawStubPath), type: .image)

    // Compute the output path for the stub executable, using the same logic
    // as the linker job.
    let stubOutputPath = try getOutputFileForImage()

    var jobs = [Job]()

    // First create a symlink to the stub executable at the output path.
    jobs.append(try symlinkJob(from: stubPath, to: stubOutputPath))

    // Then add a .xojit directory adjacent to the output.
    let outputDir = stubOutputPath.dirname
    let stubName = stubOutputPath.basename
    let xojitOutputPath = outputDir.appending(component: ".\(stubName).xojit")
    jobs.append(try mkdirJob(for: xojitOutputPath))

    // Finally invoke the frontend, which will register itself as a JIT
    // provider.
    jobs.append(try frontendJITBuildJob())
    return jobs
  }
}
