//===--------------- Toolchain+LinkerSupport.swift - Swift Linker Support -===//
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

import SwiftOptions

import protocol TSCBasic.FileSystem

extension Toolchain {
  // MARK: - Path computation

  func computeSecondaryResourceDirPath(for triple: Triple, primaryPath: VirtualPath) -> VirtualPath? {
    guard triple.isMacCatalyst else { return nil }
    return primaryPath.parentDirectory.appending(component: "macosx")
  }

  func clangLibraryPath(
    for targetInfo: FrontendTargetInfo,
    parsedOptions: inout ParsedOptions
  ) throws -> VirtualPath {
    var platform = targetInfo.target.triple.platformName(conflatingDarwin: true)!
    // compiler-rt moved these Android sanitizers into `lib/linux/` a couple
    // years ago, llvm/llvm-project@a68ccba, so look for them there instead.
    if platform == "android" {
      platform = "linux"
    }

    // NOTE(compnerd) Windows uses the per-target runtime directory for the
    // Windows runtimes. This should also be done for the other platforms, but
    // is not critical. This is done to allow for the Windows runtimes to be
    // co-located for all the currently supported architectures: x86, x64, arm64.
    let bIsWindows = targetInfo.target.triple.isWindows
    return VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
      .appending(components: "clang", "lib", bIsWindows ? targetInfo.target.triple.triple : platform)
  }

  func runtimeLibraryPaths(
    for targetInfo: FrontendTargetInfo,
    parsedOptions: inout ParsedOptions,
    sdkPath: VirtualPath.Handle?,
    isShared: Bool
  ) throws -> [VirtualPath] {
    let triple = targetInfo.target.triple
    let resourceDirPath = VirtualPath.lookup(targetInfo.runtimeResourcePath.path).appending(component: triple.platformName() ?? "")
    var result = [resourceDirPath]

    let secondaryResourceDir = computeSecondaryResourceDirPath(for: triple, primaryPath: resourceDirPath)
    if let path = secondaryResourceDir {
      result.append(path)
    }

    // Only Darwin places libraries directly in /sdk/usr/lib/swift/.
    if triple.isDarwin, let sdkPath = sdkPath.map(VirtualPath.lookup) {
      // If we added the secondary resource dir, we also need the iOSSupport directory.
      if secondaryResourceDir != nil {
        result.append(sdkPath.appending(components: "System", "iOSSupport", "usr", "lib", "swift"))
      }

      result.append(sdkPath.appending(components: "usr", "lib", "swift"))
    }

    return result
  }

  func runtimeLibraryExists(
    for sanitizer: Sanitizer,
    targetInfo: FrontendTargetInfo,
    parsedOptions: inout ParsedOptions,
    isShared: Bool
  ) throws -> Bool {
    let runtimeName = try runtimeLibraryName(
      for: sanitizer,
      targetTriple: targetInfo.target.triple,
      isShared: isShared
    )
    let path = try clangLibraryPath(
      for: targetInfo,
      parsedOptions: &parsedOptions
    ).appending(component: runtimeName)
    return try fileSystem.exists(path)
  }

  func addLinkedLibArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions
  ) {
    for match in parsedOptions.arguments(for: .l) {
      commandLine.appendFlag(match.option.spelling + match.argument.asSingle)
    }
  }

  func addExtraClangLinkerArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions
  ) throws {
    // Because we invoke `clang` as the linker executable, we must still
    // use `-Xlinker` for linker-specific arguments.
    for linkerOpt in parsedOptions.arguments(for: .Xlinker) {
      commandLine.appendFlag(.Xlinker)
      commandLine.appendFlag(linkerOpt.argument.asSingle)
    }
    try commandLine.appendAllArguments(.XclangLinker, from: &parsedOptions)
  }
}

// MARK: - Common argument routines

extension DarwinToolchain {
  func addArgsToLinkStdlib(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetInfo: FrontendTargetInfo,
    linkerOutputType: LinkOutputType,
    fileSystem: FileSystem
  ) throws {
    let targetTriple = targetInfo.target.triple

    // Link compatibility libraries, if we're deploying back to OSes that
    // have an older Swift runtime.
    func addArgsForBackDeployLib(_ libName: String, forceLoad: Bool) throws {
      let backDeployLibPath = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
        .appending(components: targetTriple.platformName() ?? "", libName)
      if try fileSystem.exists(backDeployLibPath) {
        if forceLoad {
          commandLine.append(.flag("-force_load"))
        }
        commandLine.appendPath(backDeployLibPath)
      }
    }

    let experimentalFeatures = parsedOptions.arguments(for: .enableExperimentalFeature)
    let embeddedEnabled = experimentalFeatures.map(\.argument).map(\.asSingle).contains("Embedded")

    if !embeddedEnabled {
      for compatibilityLib in targetInfo.target.compatibilityLibraries {
        let shouldLink: Bool
        switch compatibilityLib.filter {
        case .all:
          shouldLink = true
          break

        case .executable:
          shouldLink = linkerOutputType == .executable
        }

        if shouldLink {
          // Old frontends don't set forceLoad at all; assume it's true in that case
          try addArgsForBackDeployLib("lib" + compatibilityLib.libraryName + ".a",
                                      forceLoad: compatibilityLib.forceLoad ?? true)
        }
      }
    }

    // Add the runtime library link path, which is platform-specific and found
    // relative to the compiler.
    let runtimePaths = try runtimeLibraryPaths(
      for: targetInfo,
      parsedOptions: &parsedOptions,
      sdkPath: targetInfo.sdkPath?.path,
      isShared: true
    )
    for path in runtimePaths {
      commandLine.appendFlag(.L)
      commandLine.appendPath(path)
    }

    let rpaths = StdlibRpathRule(
      parsedOptions: &parsedOptions,
      targetInfo: targetInfo
    )
    for path in try rpaths.paths(runtimeLibraryPaths: runtimePaths) {
      commandLine.appendFlag("-rpath")
      commandLine.appendPath(path)
    }
  }

  /// Represents the rpaths we need to add in order to find the
  /// desired standard library at runtime.
  fileprivate enum StdlibRpathRule {
    /// Add a set of rpaths that will allow the compiler resource directory
    /// to override Swift-in-the-OS dylibs.
    case toolchain

    /// Add an rpath that will search Swift-in-the-OS dylibs, but not
    /// compiler resource directory dylibs.
    case os

    /// Do not add any rpaths at all.
    case none

    /// Determines the appropriate rule for the given set of options.
    init(parsedOptions: inout ParsedOptions, targetInfo: FrontendTargetInfo) {
      if parsedOptions.hasFlag(
        positive: .toolchainStdlibRpath,
        negative: .noToolchainStdlibRpath,
        default: false
        ) {
        // If the user has explicitly asked for a toolchain stdlib, we should
        // provide one using -rpath. This used to be the default behaviour but it
        // was considered annoying in at least the SwiftPM scenario (see
        // https://bugs.swift.org/browse/SR-1967) and is obsolete in all scenarios
        // of deploying for Swift-in-the-OS. We keep it here as an optional
        // behaviour so that people downloading snapshot toolchains for testing new
        // stdlibs will be able to link to the stdlib bundled in that toolchain.
        self = .toolchain
      }
      else if !targetInfo.target.librariesRequireRPath ||
        parsedOptions.hasArgument(.noStdlibRpath) {
        // If targeting an OS with Swift in /usr/lib/swift, the LC_ID_DYLIB
        // install_name the stdlib will be an absolute path like
        // /usr/lib/swift/libswiftCore.dylib, and we do not need to provide an rpath
        // at all.
        //
        // Also, if the user explicitly asks for no rpath entry, we assume they know
        // what they're doing and do not add one here.
        self = .none
      }
      else {
        // The remaining cases are back-deploying (to OSs predating
        // Swift-in-the-OS). In these cases, the stdlib will be giving us (via
        // stdlib/linker-support/magic-symbols-for-install-name.c) an LC_ID_DYLIB
        // install_name that is rpath-relative, like @rpath/libswiftCore.dylib.
        //
        // If we're linking an app bundle, it's possible there's an embedded stdlib
        // in there, in which case we'd want to put @executable_path/../Frameworks
        // in the rpath to find and prefer it, but (a) we don't know when we're
        // linking an app bundle and (b) we probably _never_ will be because Xcode
        // links using clang, not the swift driver.
        //
        // So that leaves us with the case of linking a command-line app. These are
        // only supported by installing a secondary package that puts some frozen
        // Swift-in-OS libraries in the /usr/lib/swift location. That's the best we
        // can give for rpath, though it might fail at runtime if the support
        // package isn't installed.
        self = .os
      }
    }

    func paths(runtimeLibraryPaths: [VirtualPath]) throws -> [VirtualPath] {
      switch self {
      case .toolchain:
        return runtimeLibraryPaths
      case .os:
        return [.absolute(try .init(validating: "/usr/lib/swift"))]
      case .none:
        return []
      }
    }
  }

}
