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

import protocol TSCBasic.FileSystem
import class Foundation.JSONDecoder
import struct TSCBasic.AbsolutePath
import class TSCBasic.DiagnosticsEngine

/// Swift versions are major.minor.
struct SwiftVersion {
  var major: Int
  var minor: Int

  init?(string: String) {
    let components = string.split(
          separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
          .compactMap { Int($0)}
    guard components.count == 2 else { return nil }

    self.major = components[0]
    self.minor = components[1]
  }

  init(major: Int, minor: Int) {
    self.major = major
    self.minor = minor
  }
}

extension SwiftVersion: Comparable {
  static func < (lhs: SwiftVersion, rhs: SwiftVersion) -> Bool {
    (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
  }
}

extension SwiftVersion: CustomStringConvertible {
  var description: String { "\(major).\(minor)" }
}

extension SwiftVersion: Codable {
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)

    guard let version = SwiftVersion(string: string) else {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Invalid Swift version string \(string)"))
    }

    self = version
  }
}

/// Describes information about the target as provided by the Swift frontend.
@dynamicMemberLookup
public struct FrontendTargetInfo: Codable {
  struct CompatibilityLibrary: Codable {
    enum Filter: String, Codable {
      case all
      case executable
    }

    let libraryName: String
    let filter: Filter
    let forceLoad: Bool?
  }

  struct Target: Codable {
    /// The target triple
    let triple: Triple

    /// The target triple without any version information.
    let unversionedTriple: Triple

    /// The triple used for module names.
    let moduleTriple: Triple

    /// The version of the Swift runtime that is present in the runtime
    /// environment of the target.
    var swiftRuntimeCompatibilityVersion: SwiftVersion?

    /// The set of compatibility libraries that one needs to link against
    /// for this particular target.
    let compatibilityLibraries: [CompatibilityLibrary]

    /// Whether the Swift libraries need to be referenced in their system
    /// location (/usr/lib/swift) via rpath.
    let librariesRequireRPath: Bool

    let openbsdBTCFIEnabled: Bool?
  }

  @_spi(Testing) public struct Paths: Codable {
    /// The path to the SDK, if provided.
    public let sdkPath: TextualVirtualPath?
    public let runtimeLibraryPaths: [TextualVirtualPath]
    public let runtimeLibraryImportPaths: [TextualVirtualPath]
    public let runtimeResourcePath: TextualVirtualPath
  }

  var compilerVersion: String
  var target: Target
  var targetVariant: Target?
  let paths: Paths
}

// Make members of `FrontendTargetInfo.Paths` accessible on `FrontendTargetInfo`.
extension FrontendTargetInfo {
  @_spi(Testing) public subscript<T>(dynamicMember dynamicMember: KeyPath<FrontendTargetInfo.Paths, T>) -> T {
    self.paths[keyPath: dynamicMember]
  }
}

extension Toolchain {
  @_spi(Testing) public func printTargetInfoJob(target: Triple?,
                                                targetVariant: Triple?,
                                                sdkPath: VirtualPath? = nil,
                                                resourceDirPath: VirtualPath? = nil,
                                                runtimeCompatibilityVersion: String? = nil,
                                                requiresInPlaceExecution: Bool = false,
                                                useStaticResourceDir: Bool = false,
                                                swiftCompilerPrefixArgs: [String]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.append(contentsOf: [.flag("-frontend"),
                                    .flag("-print-target-info")])
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

    if let runtimeCompatibilityVersion = runtimeCompatibilityVersion {
      commandLine += [
        .flag("-runtime-compatibility-version"),
        .flag(runtimeCompatibilityVersion)
      ]
    }

    if useStaticResourceDir {
       commandLine += [.flag("-use-static-resource-dir")]
     }

    return Job(
      moduleName: "",
      kind: .printTargetInfo,
      tool: try resolvedTool(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [],
      inputs: [],
      primaryInputs: [],
      outputs: [.init(file: .standardOutput, type: .jsonTargetInfo)],
      requiresInPlaceExecution: requiresInPlaceExecution
    )
  }
}

extension Driver {
  @_spi(Testing) public static func queryTargetInfoInProcess(libSwiftScanInstance: SwiftScan,
                                                             toolchain: Toolchain,
                                                             fileSystem: FileSystem,
                                                             workingDirectory: AbsolutePath?,
                                                             invocationCommand: [String]) throws -> FrontendTargetInfo {
    let cwd = try workingDirectory ?? fileSystem.currentWorkingDirectory ?? fileSystem.tempDirectory
    let compilerExecutablePath = try toolchain.resolvedTool(.swiftCompiler).path
    let targetInfoData =
    try libSwiftScanInstance.queryTargetInfoJSON(workingDirectory: cwd,
                                                 compilerExecutablePath: compilerExecutablePath,
                                                 invocationCommand: invocationCommand)
    do {
      return try JSONDecoder().decode(FrontendTargetInfo.self, from: targetInfoData)
    } catch let decodingError as DecodingError {
      let stringToDecode = String(data: targetInfoData, encoding: .utf8)
      let errorDesc: String
      switch decodingError {
      case let .typeMismatch(type, context):
        errorDesc = "type mismatch: \(type), path: \(context.codingPath)"
      case let .valueNotFound(type, context):
        errorDesc = "value missing: \(type), path: \(context.codingPath)"
      case let .keyNotFound(key, context):
        errorDesc = "key missing: \(key), path: \(context.codingPath)"
      case let .dataCorrupted(context):
        errorDesc = "data corrupted at path: \(context.codingPath)"
      @unknown default:
        errorDesc = "unknown decoding error"
      }
      throw Error.unableToDecodeFrontendTargetInfo(
        stringToDecode,
        invocationCommand,
        errorDesc)
    }
  }

  static func computeTargetInfo(target: Triple?,
                                targetVariant: Triple?,
                                sdkPath: VirtualPath? = nil,
                                resourceDirPath: VirtualPath? = nil,
                                runtimeCompatibilityVersion: String? = nil,
                                requiresInPlaceExecution: Bool = false,
                                useStaticResourceDir: Bool = false,
                                swiftCompilerPrefixArgs: [String],
                                libSwiftScan: SwiftScan?,
                                toolchain: Toolchain,
                                fileSystem: FileSystem,
                                workingDirectory: AbsolutePath?,
                                diagnosticsEngine: DiagnosticsEngine,
                                executor: DriverExecutor) throws -> FrontendTargetInfo {
    let frontendTargetInfoJob =
      try toolchain.printTargetInfoJob(target: target, targetVariant: targetVariant,
                                       sdkPath: sdkPath, resourceDirPath: resourceDirPath,
                                       runtimeCompatibilityVersion: runtimeCompatibilityVersion,
                                       requiresInPlaceExecution: requiresInPlaceExecution,
                                       useStaticResourceDir: useStaticResourceDir,
                                       swiftCompilerPrefixArgs: swiftCompilerPrefixArgs)
    if let libSwiftScanInstance = libSwiftScan,
       libSwiftScanInstance.canQueryTargetInfo() {
      do {
        var command = try Self.itemizedJobCommand(of: frontendTargetInfoJob,
                                                  useResponseFiles: .disabled,
                                                  using: executor.resolver)
        Self.sanitizeCommandForLibScanInvocation(&command)
        return try Self.queryTargetInfoInProcess(libSwiftScanInstance: libSwiftScanInstance, toolchain: toolchain,
                                                 fileSystem: fileSystem, workingDirectory: workingDirectory,
                                                 invocationCommand: command)
      } catch {
        diagnosticsEngine.emit(.remark_inprocess_target_info_query_failed(error.localizedDescription))
      }
    }

    // Fallback: Invoke `swift-frontend -print-target-info` and decode the output
    return try executor.execute(
      job: frontendTargetInfoJob,
      capturingJSONOutputAs: FrontendTargetInfo.self,
      forceResponseFiles: false,
      recordedInputModificationDates: [:])
  }
}
