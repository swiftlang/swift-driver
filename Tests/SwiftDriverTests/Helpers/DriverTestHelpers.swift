//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable @_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TSCBasic
import Testing
import TestUtilities
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#endif

// MARK: - Assertion Helpers

/// Compatibility helper for assertions with complex expressions.
func expectEqual<T: Equatable>(
  _ lhs: @autoclosure () throws -> T,
  _ rhs: @autoclosure () throws -> T,
  _ message: @autoclosure () -> String = "",
  sourceLocation: SourceLocation = #_sourceLocation
) rethrows {
  let lhsVal = try lhs()
  let rhsVal = try rhs()
  #expect(lhsVal == rhsVal, Comment(rawValue: message()), sourceLocation: sourceLocation)
}

func assertString(
  _ haystack: String, contains needle: String, _ message: String = "",
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(haystack.contains(needle), """
                \(String(reflecting: needle)) not found in \
                \(String(reflecting: haystack))\
                \(message.isEmpty ? "" : ": " + message)
                """, sourceLocation: sourceLocation)
}

// MARK: - Path Helpers

func executableName(_ name: String) -> String {
#if os(Windows)
  if name.count > 4, name.suffix(from: name.index(name.endIndex, offsetBy: -4)) == ".exe" {
    return name
  }
  return "\(name).exe"
#else
  return name
#endif
}

func rebase(_ arc: String, at base: AbsolutePath = localFileSystem.currentWorkingDirectory!) -> String {
  base.appending(component: arc).nativePathString(escaped: false)
}

func rebase(_ arcs: String..., at base: AbsolutePath = localFileSystem.currentWorkingDirectory!) -> String {
  base.appending(components: arcs).nativePathString(escaped: false)
}

var testInputsPath: AbsolutePath {
  get throws {
    var root: AbsolutePath = try AbsolutePath(validating: #filePath)
    while root.basename != "Tests" {
      root = root.parentDirectory
    }
    return root.parentDirectory.appending(component: "TestInputs")
  }
}

func toPath(_ path: String, isRelative: Bool = true) throws -> VirtualPath {
  if isRelative {
    return VirtualPath.relative(try .init(validating: path))
  }
  return try VirtualPath(path: path).resolvedRelativePath(base: localFileSystem.currentWorkingDirectory!)
}

func toPathOption(_ path: String, isRelative: Bool = true) throws -> Job.ArgTemplate {
  return .path(try toPath(path, isRelative: isRelative))
}

// MARK: - Test Environment Helpers

var envWithFakeSwiftHelp: ProcessEnvironmentBlock {
  // During build-script builds, build products are not installed into the toolchain
  // until a project's tests pass. However, we're in the middle of those tests,
  // so there is no swift-help in the toolchain yet. Set the environment variable
  // as if we had found it for the purposes of testing build planning.
  var env = ProcessEnv.block
  env["SWIFT_DRIVER_SWIFT_HELP_EXEC"] = "/tmp/.test-swift-help"
  return env
}

/// Determine if the test's execution environment has LLDB.
/// Used to skip tests that rely on LLDB in such environments.
func testEnvHasLLDB() throws -> Bool {
  let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                         processSet: ProcessSet(),
                                         fileSystem: localFileSystem,
                                         env: ProcessEnv.block)
  let toolchain: Toolchain
  #if os(macOS)
  toolchain = DarwinToolchain(env: ProcessEnv.block, executor: executor)
  #elseif os(Windows)
  toolchain = WindowsToolchain(env: ProcessEnv.block, executor: executor)
  #else
  toolchain = GenericUnixToolchain(env: ProcessEnv.block, executor: executor)
  #endif
  do {
    _ = try toolchain.getToolPath(.lldb)
  } catch ToolchainError.unableToFind {
    return false
  }
  return true
}

/// Create a fake linker stub for tests that plan link jobs.
func makeLdStub() throws -> AbsolutePath {
  try withTemporaryDirectory(removeTreeOnDeinit: false) {
    let ld = $0.appending(component: executableName("ld64.lld"))
    try localFileSystem.writeFileContents(ld, bytes: "")
    try localFileSystem.chmod(.executable, path: AbsolutePath(validating: ld.nativePathString(escaped: false)))
    return ld
  }
}

// MARK: - Job.ArgTemplate Extensions

extension Array where Element == Job.ArgTemplate {
  func containsPathWithBasename(_ basename: String) -> Bool {
    contains {
      switch $0 {
      case let .path(path):
        return path.basename == basename
      case .flag, .responseFilePath, .joinedOptionAndPath, .commaJoinedOptionAndPaths, .squashedArgumentList:
        return false
      }
    }
  }

  var supplementaryOutputFilemap: OutputFileMap {
    get throws {
      guard let argIdx = firstIndex(where: { $0 == .flag("-supplementary-output-file-map") }) else {
        throw StringError("supplementaryOutputFilemap doesn't exist")
      }
      let supplementaryOutputs = self[argIdx + 1]
      guard case let .path(path) = supplementaryOutputs,
            case let .fileList(_, fileList) = path,
            case let .outputFileMap(outputFileMap) = fileList else {
        throw StringError("Unexpected argument for output file map")
      }
      return outputFileMap
    }
  }
}

// MARK: - Collection Extensions

extension BidirectionalCollection where Element: Equatable, Index: Strideable, Index.Stride: SignedInteger {
  /// Returns true if the receiver contains the given elements as a subsequence
  /// (i.e., all elements are present, contiguous, and in the same order).
  func contains<Elements: Collection>(
    subsequence: Elements
  ) -> Bool
  where Elements.Element == Element
  {
    precondition(!subsequence.isEmpty,  "Subsequence may not be empty")

    guard self.count >= subsequence.count else {
      return false
    }

    for index in self.startIndex...self.index(self.endIndex,
                                              offsetBy: -subsequence.count) {
      if self[index..<self.index(index,
                                 offsetBy: subsequence.count)]
                          .elementsEqual(subsequence) {
        return true
      }
    }
    return false
  }
}

extension Array where Element == Job {
  /// Utility to drop autolink-extract jobs, which helps avoid introducing
  /// platform-specific conditionals in tests unrelated to autolinking.
  func removingAutolinkExtractJobs() -> Self {
    var filtered = self
    filtered.removeAll(where: { $0.kind == .autolinkExtract })
    return filtered
  }

  /// Returns true if a job with the given Kind is contained in the array.
  func containsJob(_ kind: Job.Kind) -> Bool {
    return contains(where: { $0.kind == kind })
  }

  /// Finds the first job with the given kind, or throws if one cannot be found.
  func findJob(_ kind: Job.Kind) throws -> Job {
    return try #require(first(where: { $0.kind == kind }))
  }

  func findJobs(_ kind: Job.Kind) throws -> [Job] {
    return filter({ $0.kind == kind })
  }
}
