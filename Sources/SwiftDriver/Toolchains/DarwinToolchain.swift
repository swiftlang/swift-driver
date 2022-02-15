//===--------------- DarwinToolchain.swift - Swift Darwin Toolchain -------===//
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
import Foundation
import SwiftOptions

import struct TSCUtility.Version

/// Toolchain for Darwin-based platforms, such as macOS and iOS.
///
/// FIXME: This class is not thread-safe.
public final class DarwinToolchain: Toolchain {
  public let env: [String: String]

  /// Doubles as path cache and point for overriding normal lookup
  private var toolPaths = [Tool: AbsolutePath]()

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for any file operations.
  public let fileSystem: FileSystem

  // An externally provided path from where we should find compiler
  public let compilerExecutableDir: AbsolutePath?

  // An externally provided path from where we should find tools like ld
  public let toolDirectory: AbsolutePath?

  public let dummyForTestingObjectFormat = Triple.ObjectFormat.macho

  public init(env: [String: String], executor: DriverExecutor, fileSystem: FileSystem = localFileSystem,
              compilerExecutableDir: AbsolutePath? = nil, toolDirectory: AbsolutePath? = nil) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
    self.compilerExecutableDir = compilerExecutableDir
    self.toolDirectory = toolDirectory
  }

  /// Retrieve the absolute path for a given tool.
  public func getToolPath(_ tool: Tool) throws -> AbsolutePath {
    // Check the cache
    if let toolPath = toolPaths[tool] {
      return toolPath
    }
    let path = try lookupToolPath(tool)
    // Cache the path
    toolPaths[tool] = path
    return path
  }

  private func lookupToolPath(_ tool: Tool) throws -> AbsolutePath {
    switch tool {
    case .swiftCompiler:
      return try lookup(executable: "swift-frontend")
    case .dynamicLinker:
      return try lookup(executable: "ld")
    case .staticLinker:
      return try lookup(executable: "libtool")
    case .dsymutil:
      return try lookup(executable: "dsymutil")
    case .clang:
      return try lookup(executable: "clang")
    case .swiftAutolinkExtract:
      return try lookup(executable: "swift-autolink-extract")
    case .lldb:
      return try lookup(executable: "lldb")
    case .dwarfdump:
      return try lookup(executable: "dwarfdump")
    case .swiftHelp:
      return try lookup(executable: "swift-help")
    case .swiftAPIDigester:
      return try lookup(executable: "swift-api-digester")
    }
  }

  public func overrideToolPath(_ tool: Tool, path: AbsolutePath) {
    toolPaths[tool] = path
  }

  public func clearKnownToolPath(_ tool: Tool) {
    toolPaths.removeValue(forKey: tool)
  }

  /// Path to the StdLib inside the SDK.
  public func sdkStdlib(sdk: AbsolutePath) -> AbsolutePath {
    sdk.appending(RelativePath("usr/lib/swift"))
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return moduleName
    case .dynamicLibrary: return "lib\(moduleName).dylib"
    case .staticLibrary: return "lib\(moduleName).a"
    }
  }

  public func defaultSDKPath(_ target: Triple?) throws -> AbsolutePath? {
    let hostIsMacOS: Bool
    #if os(macOS)
    hostIsMacOS = true
    #else
    hostIsMacOS = false
    #endif

    if target?.isMacOSX == true || hostIsMacOS {
      let result = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path",
        environment: env
      ).spm_chomp()
      return AbsolutePath(result)
    }

    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool {
    // This matches the behavior in Clang.
    !(env["RC_DEBUG_OPTIONS"]?.isEmpty ?? true)
  }

  public var globalDebugPathRemapping: String? {
    // This matches the behavior in Clang.
    if let map = env["RC_DEBUG_PREFIX_MAP"] {
      if map.contains("=") {
        return map
      }
    }
    return nil
  }

  public func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String {
    return """
    libclang_rt.\(sanitizer.libraryName)_\
    \(targetTriple.darwinPlatform!.libraryNameSuffix)\
    \(isShared ? "_dynamic.dylib" : ".a")
    """
  }

  public enum ToolchainValidationError: Error, DiagnosticData {
    case osVersionBelowMinimumDeploymentTarget(String)
    case argumentNotSupported(String)
    case invalidDeploymentTargetForIR(String, String)
    case unsupportedTargetVariant(variant: Triple)
    case darwinOnlySupportsLibCxx

    public var description: String {
      switch self {
      case .osVersionBelowMinimumDeploymentTarget(let target):
        return "Swift requires a minimum deployment target of \(target)"
      case .invalidDeploymentTargetForIR(let target, let archName):
        return
          "\(target) and above does not support emitting binaries or IR for \(archName)"
      case .unsupportedTargetVariant(variant: let variant):
        return "unsupported '\(variant.isiOS ? "-target-variant" : "-target")' value '\(variant.triple)'; use 'ios-macabi' instead"
      case .argumentNotSupported(let argument):
        return "\(argument) is no longer supported for Apple platforms"
      case .darwinOnlySupportsLibCxx:
        return "The only C++ standard library supported on Apple platforms is libc++"
      }
    }
  }

  public func validateArgs(_ parsedOptions: inout ParsedOptions,
                           targetTriple: Triple,
                           targetVariantTriple: Triple?,
                           compilerOutputType: FileType?,
                           diagnosticsEngine: DiagnosticsEngine) throws {
    // On non-darwin hosts, libArcLite won't be found and a warning will be emitted
    // Guard for the sake of tests running on all platforms
    #if canImport(Darwin)
    // Validating arclite library path when link-objc-runtime.
    validateLinkObjcRuntimeARCLiteLib(&parsedOptions,
                                      targetTriple: targetTriple,
                                      diagnosticsEngine: diagnosticsEngine)
    #endif
    // Validating apple platforms deployment targets.
    try validateDeploymentTarget(&parsedOptions, targetTriple: targetTriple, 
                                 compilerOutputType: compilerOutputType)
    if let targetVariantTriple = targetVariantTriple,
       !targetTriple.isValidForZipperingWithTriple(targetVariantTriple) {
      throw ToolchainValidationError.unsupportedTargetVariant(variant: targetVariantTriple)
    }
    // Validating darwin unsupported -static-stdlib argument.
    if parsedOptions.hasArgument(.staticStdlib) {
      throw ToolchainValidationError.argumentNotSupported("-static-stdlib")
    }
    // Validating darwin unsupported -static-executable argument.
    if parsedOptions.hasArgument(.staticExecutable) {
      throw ToolchainValidationError.argumentNotSupported("-static-executable")
    }
    // If a C++ standard library is specified, it has to be libc++.
    if let cxxLib = parsedOptions.getLastArgument(.experimentalCxxStdlib) {
        if cxxLib.asSingle != "libc++" {
            throw ToolchainValidationError.darwinOnlySupportsLibCxx
        }
    }
  }

  func validateDeploymentTarget(_ parsedOptions: inout ParsedOptions,
                                targetTriple: Triple, compilerOutputType: FileType?) throws {
    // Check minimum supported OS versions.
    if targetTriple.isMacOSX,
       targetTriple.version(for: .macOS) < Triple.Version(10, 9, 0) {
      throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("OS X 10.9")
    }
    // tvOS triples are also iOS, so check it first.
    else if targetTriple.isTvOS,
            targetTriple.version(for: .tvOS(.device)) < Triple.Version(9, 0, 0) {
      throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("tvOS 9.0")
    } else if targetTriple.isiOS {
      if targetTriple.version(for: .iOS(.device)) < Triple.Version(7, 0, 0) {
        throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("iOS 7")
      }
      if targetTriple.arch?.is32Bit == true,
         targetTriple.version(for: .iOS(.device)) >= Triple.Version(11, 0, 0), 
         compilerOutputType != .swiftModule {
        throw
            ToolchainValidationError
              .invalidDeploymentTargetForIR("iOS 11", targetTriple.archName)
      }
    } else if targetTriple.isWatchOS,
              targetTriple.version(for: .watchOS(.device)) < Triple.Version(2, 0, 0) {
      throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("watchOS 2.0")
    }
  }
    
  func validateLinkObjcRuntimeARCLiteLib(_ parsedOptions: inout ParsedOptions,
                                           targetTriple: Triple,
                                           diagnosticsEngine: DiagnosticsEngine) {
    guard parsedOptions.hasFlag(positive: .linkObjcRuntime,
                                negative: .noLinkObjcRuntime,
                                default: !targetTriple.supports(.nativeARC))
    else {
      return
    }

    guard let _ = try? findARCLiteLibPath() else {
        diagnosticsEngine.emit(.warn_arclite_not_found_when_link_objc_runtime)
        return
    }
  }

  struct DarwinSDKInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
      case version = "Version"
      case versionMap = "VersionMap"
      case canonicalName = "CanonicalName"
    }

    public enum SDKPlatformKind: String, CaseIterable {
      case macosx
      case iphoneos
      case iphonesimulator
      case watchos
      case watchsimulator
      case appletvos
      case appletvsimulator
      case unknown
    }

    struct VersionMap: Decodable {
      private enum CodingKeys: String, CodingKey {
        case macOSToCatalystMapping = "macOS_iOSMac"
      }

      var macOSToCatalystMapping: [Version: Version] = [:]

      init() {}
      init(from decoder: Decoder) throws {
        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)

        let mappingDict = try keyedContainer.decode([String: String].self, forKey: .macOSToCatalystMapping)
        self.macOSToCatalystMapping = [:]
        try mappingDict.forEach { key, value in
          guard let newKey = try? Version(versionString: key, usesLenientParsing: true) else {
            throw DecodingError.dataCorruptedError(forKey: .macOSToCatalystMapping,
                                                   in: keyedContainer,
                                                   debugDescription: "Malformed version string")
          }
          guard let newValue = try? Version(versionString: value, usesLenientParsing: true) else {
            throw DecodingError.dataCorruptedError(forKey: .macOSToCatalystMapping,
                                                   in: keyedContainer,
                                                   debugDescription: "Malformed version string")
          }
          self.macOSToCatalystMapping[newKey] = newValue
        }
      }
    }
    public let versionString: String
    public let platformKind: SDKPlatformKind
    private var version: Version
    private var versionMap: VersionMap
    let canonicalName: String
    init(from decoder: Decoder) throws {
      let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)

      self.versionString = try keyedContainer.decode(String.self, forKey: .version)
      let canonicalName = try keyedContainer.decode(String.self, forKey: .canonicalName)
      self.platformKind = SDKPlatformKind.allCases.first { canonicalName.hasPrefix($0.rawValue) } ?? SDKPlatformKind.unknown
      self.canonicalName = canonicalName
      guard let version = try? Version(versionString: versionString, usesLenientParsing: true) else {
        throw DecodingError.dataCorruptedError(forKey: .version,
                                               in: keyedContainer,
                                               debugDescription: "Malformed version string")
      }
      self.version = version
      if self.canonicalName.hasPrefix("macosx") {
        self.versionMap = try keyedContainer.decode(VersionMap.self, forKey: .versionMap)
      } else {
        self.versionMap = VersionMap()
      }
    }


    func sdkVersion(for triple: Triple) -> Version {
      if triple.isMacCatalyst {
        // For the Mac Catalyst environment, we have a macOS SDK with a macOS
        // SDK version. Map that to the corresponding iOS version number to pass
        // down to the linker.
        return versionMap.macOSToCatalystMapping[version.withoutBuildNumbers] ?? Version(0, 0, 0)
      }
      return version
    }
  }

  // SDK info is computed lazily. This should not generally be accessed directly.
  private var _sdkInfo: DarwinSDKInfo? = nil

  static func readSDKInfo(_ fileSystem: FileSystem, _ sdkPath: VirtualPath.Handle) -> DarwinSDKInfo? {
    let sdkSettingsPath = VirtualPath.lookup(sdkPath).appending(component: "SDKSettings.json")
    guard let contents = try? fileSystem.readFileContents(sdkSettingsPath) else { return nil }
    guard let sdkInfo = try? JSONDecoder().decode(DarwinSDKInfo.self,
                                                  from: Data(contents.contents)) else { return nil }
    return sdkInfo
  }

  func getTargetSDKInfo(sdkPath: VirtualPath.Handle) -> DarwinSDKInfo? {
    if let info = _sdkInfo {
      return info
    } else {
      self._sdkInfo = DarwinToolchain.readSDKInfo(fileSystem, sdkPath)
      return self._sdkInfo
    }
  }

  public func addPlatformSpecificCommonFrontendOptions(
    commandLine: inout [Job.ArgTemplate],
    inputs: inout [TypedVirtualPath],
    frontendTargetInfo: FrontendTargetInfo,
    driver: Driver
  ) throws {
    guard let sdkPath = frontendTargetInfo.sdkPath?.path,
          let sdkInfo = getTargetSDKInfo(sdkPath: sdkPath) else { return }

    commandLine.append(.flag("-target-sdk-version"))
    commandLine.append(.flag(sdkInfo.sdkVersion(for: frontendTargetInfo.target.triple).sdkVersionString))

    if let targetVariantTriple = frontendTargetInfo.targetVariant?.triple {
      commandLine.append(.flag("-target-variant-sdk-version"))
      commandLine.append(.flag(sdkInfo.sdkVersion(for: targetVariantTriple).sdkVersionString))
    }

    if driver.isFrontendArgSupported(.targetSdkName) &&
       env["ENABLE_RESTRICT_SWIFTMODULE_SDK"] != nil {
      commandLine.append(.flag(Option.targetSdkName.spelling))
      commandLine.append(.flag(sdkInfo.canonicalName))
    }

    // We should be able to pass down prebuilt module dir for all other SDKs.
    // For macCatalyst, doing so is specifically necessary because -target-sdk-version
    // doesn't always match the macosx sdk version so the compiler may fail to find
    // the prebuilt module in the versioned sub-dir.
    if frontendTargetInfo.target.triple.isMacCatalyst {
      commandLine.appendFlag(.prebuiltModuleCachePath)
      commandLine.appendPath(try getToolPath(.swiftCompiler).parentDirectory/*bin*/
        .parentDirectory/*usr*/
        .appending(component: "lib").appending(component: "swift")
        .appending(component: "macosx").appending(component: "prebuilt-modules")
        .appending(component: sdkInfo.versionString))
    }
  }
}

extension Diagnostic.Message {
    static var warn_arclite_not_found_when_link_objc_runtime: Diagnostic.Message {
      .warning(
        "unable to find Objective-C runtime support library 'arclite'; " +
        "pass '-no-link-objc-runtime' to silence this warning"
      )
    }
}

private extension Version {
  var sdkVersionString: String {
    if patch == 0 && prereleaseIdentifiers.isEmpty && buildMetadataIdentifiers.isEmpty {
      return "\(major).\(minor)"
    }
    return self.description
  }
}
