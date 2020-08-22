//===--------------- ArgsResolver.swift - Argument Resolution -------------===//
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

/// Resolver for a job's argument template.
public struct ArgsResolver {
  /// The map of virtual path to the actual path.
  public var pathMapping: [VirtualPath: AbsolutePath]

  /// The file system used by the resolver.
  private let fileSystem: FileSystem

  /// Path to the directory that will contain the temporary files.
  // FIXME: We probably need a dedicated type for this...
  private let temporaryDirectory: VirtualPath

  public init(fileSystem: FileSystem, temporaryDirectory: VirtualPath? = nil) throws {
    self.pathMapping = [:]
    self.fileSystem = fileSystem

    if let temporaryDirectory = temporaryDirectory {
      self.temporaryDirectory = temporaryDirectory
    } else {
      let tmpDir: AbsolutePath = try withTemporaryDirectory(removeTreeOnDeinit: false) { path in
        // FIXME: TSC removes empty directories even when removeTreeOnDeinit is false. This seems like a bug.
        try fileSystem.writeFileContents(path.appending(component: ".keep-directory")) { $0 <<< "" }
        return path
      }
      self.temporaryDirectory = .absolute(tmpDir)
    }
  }

  public func resolveArgumentList(for job: Job, forceResponseFiles: Bool) throws -> [String] {
    let (arguments, _) = try resolveArgumentList(for: job, forceResponseFiles: forceResponseFiles)
    return arguments
  }

  public func resolveArgumentList(for job: Job, forceResponseFiles: Bool) throws -> ([String], usingResponseFile: Bool) {
    let tool = try resolve(.path(job.tool))
    var arguments = [tool] + (try job.commandLine.map { try resolve($0) })
    let usingResponseFile = try createResponseFileIfNeeded(for: job, resolvedArguments: &arguments,
                                                           forceResponseFiles: forceResponseFiles)
    return (arguments, usingResponseFile)
  }

  /// Resolve the given argument.
  public func resolve(_ arg: Job.ArgTemplate) throws -> String {
    switch arg {
    case .flag(let flag):
      return flag

    case .path(let path):
      // Return the path from the temporary directory if this is a temporary file.
      if path.isTemporary {
        let actualPath = temporaryDirectory.appending(component: path.name)
        return actualPath.name
      }

      // If there was a path mapping, use it.
      if let actualPath = pathMapping[path] {
        return actualPath.pathString
      }

      // Otherwise, return the path.
      return path.name
    case .responseFilePath(let path):
      return "@\(try resolve(.path(path)))"
    }
  }

  private func createResponseFileIfNeeded(for job: Job, resolvedArguments: inout [String], forceResponseFiles: Bool) throws -> Bool {
    if forceResponseFiles ||
      (job.supportsResponseFiles && !commandLineFitsWithinSystemLimits(path: resolvedArguments[0], args: resolvedArguments)) {
      assert(!forceResponseFiles || job.supportsResponseFiles,
             "Platform does not support response files for job: \(job)")
      // Match the integrated driver's behavior, which uses response file names of the form "arguments-[0-9a-zA-Z].resp".
      let responseFilePath = temporaryDirectory.appending(component: "arguments-\(abs(job.hashValue)).resp")

      // FIXME: Need a way to support this for distributed build systems...
      if let absPath = responseFilePath.absolutePath {
        try fileSystem.writeFileContents(absPath) {
          $0 <<< resolvedArguments[1...].map{ $0.spm_shellEscaped() }.joined(separator: "\n")
        }
        resolvedArguments = [resolvedArguments[0], "@\(absPath.pathString)"]
      }

      return true
    }
    return false
  }

  /// Remove the temporary directory from disk.
  public func removeTemporaryDirectory() throws {
    // Only try to remove if we have an absolute path.
    if let absPath = temporaryDirectory.absolutePath {
      try fileSystem.removeFileTree(absPath)
    }
  }
}
