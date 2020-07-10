//===--------------- FilesystemJobs.swift - Generic Filesystem Jobs -------===//
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

extension Driver {
  /// Create a symbolic link.
  func symlinkJob(from input: TypedVirtualPath, to output: VirtualPath) throws -> Job {
    let invocation = try toolchain.getSymlinkInvocation(from: input.file, to: output)
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .symlink,
      tool: invocation.command,
      commandLine: invocation.args,
      displayInputs: [input],
      inputs: [input],
      outputs: [.init(file: output, type: input.type)]
    )
  }

  /// Create a directory.
  func mkdirJob(for path: VirtualPath) throws -> Job {
    let invocation = try toolchain.getMkdirInvocation(for: path)
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .mkdir,
      tool: invocation.command,
      commandLine: invocation.args,
      inputs: [],
      outputs: []
    )
  }
}
