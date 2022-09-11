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

import class Foundation.NSLock

import TSCBasic // <<<
import func TSCBasic.withTemporaryDirectory
import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath

@_implementationOnly import Yams

/// How the resolver is to handle usage of response files
public enum ResponseFileHandling {
  case forced
  case disabled
  case heuristic
}

/// Resolver for a job's argument template.
public final class ArgsResolver {
  /// The map of virtual path to the actual path.
  public var pathMapping: [VirtualPath: String]

  /// The file system used by the resolver.
  private let fileSystem: FileSystem

  /// Path to the directory that will contain the temporary files.
  // FIXME: We probably need a dedicated type for this...
  private let temporaryDirectory: VirtualPath

  private let lock = NSLock()

  public init(fileSystem: FileSystem, temporaryDirectory: VirtualPath? = nil) throws {
    self.pathMapping = [:]
    self.fileSystem = fileSystem

    if let temporaryDirectory = temporaryDirectory {
      self.temporaryDirectory = temporaryDirectory
    } else {
      // FIXME: withTemporaryDirectory uses FileManager.default, need to create a FileSystem.temporaryDirectory api.
      let tmpDir: AbsolutePath = try withTemporaryDirectory(removeTreeOnDeinit: false) { path in
        // FIXME: TSC removes empty directories even when removeTreeOnDeinit is false. This seems like a bug.
        try fileSystem.writeFileContents(path.appending(component: ".keep-directory")) { $0 <<< "" }
        return path
      }
      self.temporaryDirectory = .absolute(tmpDir)
    }
  }

  public func resolveArgumentList(for job: Job, useResponseFiles: ResponseFileHandling = .heuristic,
                                  quotePaths: Bool = false) throws -> [String] {
    let (arguments, _) = try resolveArgumentList(for: job, useResponseFiles: useResponseFiles,
                                                 quotePaths: quotePaths)
    return arguments
  }

  public func resolveArgumentList(for job: Job, useResponseFiles: ResponseFileHandling = .heuristic,
                                  quotePaths: Bool = false) throws -> ([String], usingResponseFile: Bool) {
    let tool = try resolve(.path(job.tool), quotePaths: quotePaths)
    var arguments = [tool] + (try job.commandLine.map { try resolve($0, quotePaths: quotePaths) })
    let usingResponseFile = try createResponseFileIfNeeded(for: job, resolvedArguments: &arguments,
                                                           useResponseFiles: useResponseFiles)
    return (arguments, usingResponseFile)
  }

  @available(*, deprecated, message: "use resolveArgumentList(for:,useResponseFiles:,quotePaths:)")
  public func resolveArgumentList(for job: Job, forceResponseFiles: Bool,
                                  quotePaths: Bool = false) throws -> [String] {
    let useResponseFiles: ResponseFileHandling = forceResponseFiles ? .forced : .heuristic
    return try resolveArgumentList(for: job, useResponseFiles: useResponseFiles, quotePaths: quotePaths)
  }

  @available(*, deprecated, message: "use resolveArgumentList(for:,useResponseFiles:,quotePaths:)")
  public func resolveArgumentList(for job: Job, forceResponseFiles: Bool,
                                  quotePaths: Bool = false) throws -> ([String], usingResponseFile: Bool) {
    let useResponseFiles: ResponseFileHandling = forceResponseFiles ? .forced : .heuristic
    return try resolveArgumentList(for: job, useResponseFiles: useResponseFiles, quotePaths: quotePaths)
  }

  /// Resolve the given argument.
  public func resolve(_ arg: Job.ArgTemplate,
                      quotePaths: Bool = false) throws -> String {
    switch arg {
    case .flag(let flag):
      return flag

    case .path(let path):
      return try lock.withLock {
        return try unsafeResolve(path: path, quotePaths: quotePaths)
      }

    case .responseFilePath(let path):
      return "@\(try resolve(.path(path), quotePaths: quotePaths))"

    case let .joinedOptionAndPath(option, path):
      return option + (try resolve(.path(path), quotePaths: quotePaths))

    case let .squashedArgumentList(option: option, args: args):
      return try option + args.map {
        try resolve($0, quotePaths: quotePaths)
      }.joined(separator: " ")
    }
  }

  /// Needs to be done inside of `lock`. Marked unsafe to make that more obvious.
  private func unsafeResolve(path: VirtualPath, quotePaths: Bool) throws -> String {
    // If there was a path mapping, use it.
    if let actualPath = pathMapping[path] {
      return quotePaths ? "'\(actualPath)'" : actualPath
    }

    // Return the path from the temporary directory if this is a temporary file.
    if path.isTemporary {
      let actualPath = temporaryDirectory.appending(component: path.name)
      switch path {
      case .temporary:
        break // No special behavior required.
      case let .temporaryWithKnownContents(_, contents):
        // FIXME: Need a way to support this for distributed build systems...
        if let absolutePath = actualPath.absolutePath {
          try fileSystem.writeFileContents(absolutePath, bytes: .init(contents))
        }
      case let .fileList(_, .list(items)):
        try createFileList(path: actualPath, contents: items)
      case let .fileList(_, .outputFileMap(map)):
        try createFileList(path: actualPath, outputFileMap: map)
      case .relative, .absolute, .standardInput, .standardOutput:
        fatalError("Not a temporary path.")
      }

      let result = actualPath.name
      pathMapping[path] = result
      return quotePaths ? "'\(result)'" : result
    }

    // Otherwise, return the path.
    let result = path.name
    pathMapping[path] = result
    return quotePaths ? "'\(result)'" : result
  }

  private func createFileList(path: VirtualPath, contents: [VirtualPath]) throws {
    // FIXME: Need a way to support this for distributed build systems...
    if let absPath = path.absolutePath {
      try fileSystem.writeFileContents(absPath) { out in
        for path in contents {
          try! out <<< unsafeResolve(path: path, quotePaths: false) <<< "\n"
        }
      }
    }
  }

  private func createFileList(path: VirtualPath, outputFileMap: OutputFileMap)
  throws {
    // FIXME: Need a way to support this for distributed build systems...
    if let absPath = path.absolutePath {
      // This uses Yams to escape and quote strings, but not to output the whole yaml file because
      // it sometimes outputs mappings in explicit block format (https://yaml.org/spec/1.2/spec.html#id2798057)
      // and the frontend (llvm) only seems to support implicit block format.
      try fileSystem.writeFileContents(absPath) { out in
        for (input, map) in outputFileMap.entries {
          out <<< quoteAndEscape(path: VirtualPath.lookup(input)) <<< ":"
          if map.isEmpty {
            out <<< " {}\n"
          } else {
            out <<< "\n"
            for (type, output) in map {
              out <<< "  " <<< type.name <<< ": " <<< quoteAndEscape(path: VirtualPath.lookup(output)) <<< "\n"
            }
          }
        }
      }
    }
  }

  private func quoteAndEscape(path: VirtualPath) -> String {
    let inputNode = Node.scalar(Node.Scalar(try! unsafeResolve(path: path, quotePaths: false),
                                            Tag(.str), .doubleQuoted))
    // Width parameter of -1 sets preferred line-width to unlimited so that no extraneous
    // line-breaks will be inserted during serialization.
    let string = try! Yams.serialize(node: inputNode, width: -1)
    // Remove the newline from the end
    return string.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func createResponseFileIfNeeded(for job: Job, resolvedArguments: inout [String], useResponseFiles: ResponseFileHandling) throws -> Bool {
    func quote(_ string: String) -> String {
      return "\"\(String(string.flatMap { ["\\", "\""].contains($0) ? "\\\($0)" : "\($0)" }))\""
    }
    guard useResponseFiles != .disabled else {
      return false
    }
    
    let forceResponseFiles = useResponseFiles == .forced
    if forceResponseFiles ||
      (job.supportsResponseFiles && !commandLineFitsWithinSystemLimits(path: resolvedArguments[0], args: resolvedArguments)) {
      assert(!forceResponseFiles || job.supportsResponseFiles,
             "Platform does not support response files for job: \(job)")
      // Match the integrated driver's behavior, which uses response file names of the form "arguments-[0-9a-zA-Z].resp".
      let responseFilePath = temporaryDirectory.appending(component: "arguments-\(abs(job.hashValue)).resp")

      // FIXME: Need a way to support this for distributed build systems...
      if let absPath = responseFilePath.absolutePath {
        // Adopt the same technique as clang -
        //   Wrap all arguments in double quotes to ensure that both Unix and
        //   Windows tools understand the response file.
        try fileSystem.writeFileContents(absPath) {
          $0 <<< resolvedArguments[1...].map { quote($0) }.joined(separator: "\n")
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

fileprivate extension NSLock {
    /// NOTE: Keep in sync with SwiftPM's 'Sources/Basics/NSLock+Extensions.swift'
    /// Execute the given block while holding the lock.
    func withLock<T> (_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
