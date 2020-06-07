//===--------------- DarwinToolchain+LinkerSupport.swift ------------------===//
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
import SwiftOptions

extension DarwinToolchain {
  private func findARCLiteLibPath() throws -> AbsolutePath? {
    let path = try getToolPath(.swiftCompiler)
      .parentDirectory // 'swift'
      .parentDirectory // 'bin'
      .appending(components: "lib", "arc")

    if fileSystem.exists(path) { return path }

    // If we don't have a 'lib/arc/' directory, find the "arclite" library
    // relative to the Clang in the active Xcode.
    if let clangPath = try? getToolPath(.clang) {
      return clangPath
        .parentDirectory // 'clang'
        .parentDirectory // 'bin'
        .appending(components: "lib", "arc")
    }
    return nil
  }

  func addLinkRuntimeLibraryRPath(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetTriple: Triple,
    darwinLibName: String
  ) throws {
    // Adding the rpaths might negatively interact when other rpaths are involved,
    // so we should make sure we add the rpaths last, after all user-specified
    // rpaths. This is currently true from this place, but we need to be
    // careful if this function is ever called before user's rpaths are emitted.
    assert(darwinLibName.hasSuffix(".dylib"), "must be a dynamic library")

    // Add @executable_path to rpath to support having the dylib copied with
    // the executable.
    commandLine.appendFlag("-rpath")
    commandLine.appendFlag("@executable_path")

    // Add the path to the resource dir to rpath to support using the dylib
    // from the default location without copying.


    let clangPath = try clangLibraryPath(
      for: targetTriple,
      parsedOptions: &parsedOptions)
    commandLine.appendFlag("-rpath")
    commandLine.appendPath(clangPath)
  }

  func addLinkSanitizerLibArgsForDarwin(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetTriple: Triple,
    sanitizer: Sanitizer,
    isShared: Bool
  ) throws {
    // Sanitizer runtime libraries requires C++.
    commandLine.appendFlag("-lc++")
    // Add explicit dependency on -lc++abi, as -lc++ doesn't re-export
    // all RTTI-related symbols that are used.
    commandLine.appendFlag("-lc++abi")

    let sanitizerName = try runtimeLibraryName(
      for: sanitizer,
      targetTriple: targetTriple,
      isShared: isShared
    )
    try addLinkRuntimeLibrary(
      named: sanitizerName,
      to: &commandLine,
      for: targetTriple,
      parsedOptions: &parsedOptions
    )

    if isShared {
      try addLinkRuntimeLibraryRPath(
        to: &commandLine,
        parsedOptions: &parsedOptions,
        targetTriple: targetTriple,
        darwinLibName: sanitizerName
      )
    }
  }

  private func addProfileGenerationArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetTriple: Triple
  ) throws {
    guard parsedOptions.hasArgument(.profileGenerate) else { return }
    let clangPath = try clangLibraryPath(for: targetTriple,
                                         parsedOptions: &parsedOptions)

    let runtime = targetTriple.darwinPlatform!.libraryNameSuffix

    let clangRTPath = clangPath
      .appending(component: "libclang_rt.profile_\(runtime).a")

    commandLine.appendPath(clangRTPath)
  }

  private func addDeploymentTargetArgs(
    to commandLine: inout [Job.ArgTemplate],
    targetTriple: Triple,
    targetVariantTriple: Triple?
  ) {
    // FIXME: Properly handle deployment targets.

    let flag: String

    switch targetTriple.darwinPlatform! {
    case .iOS(.device):
      flag = "-iphoneos_version_min"
    case .iOS(.simulator):
      flag = "-ios_simulator_version_min"
    case .iOS(.catalyst):
      flag = "-maccatalyst_version_min"
    case .macOS:
      flag = "-macosx_version_min"
    case .tvOS(.device):
      flag = "-tvos_version_min"
    case .tvOS(.simulator):
      flag = "-tvos_simulator_version_min"
    case .watchOS(.device):
      flag = "-watchos_version_min"
    case .watchOS(.simulator):
      flag = "-watchos_simulator_version_min"
    }

    commandLine.appendFlag(flag)
    commandLine.appendFlag(targetTriple.version().description)

    if let variant = targetVariantTriple {
      if targetTriple.isiOS {
        assert(targetTriple.isValidForZipperingWithTriple(variant))
        assert(variant.isMacOSX)
        commandLine.appendFlag("-macosx_version_min")
        commandLine.appendFlag(variant.version().description)
      } else {
        assert(targetTriple.isValidForZipperingWithTriple(variant))
        assert(variant.isMacCatalyst)
        commandLine.appendFlag("-maccatalyst_version_min")
        commandLine.appendFlag(variant.version().description)
      }
    }
  }

  private func addArgsToLinkARCLite(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetTriple: Triple
  ) throws {
    guard parsedOptions.hasFlag(
      positive: .linkObjcRuntime,
      negative: .noLinkObjcRuntime,
      default: !targetTriple.supports(.compatibleObjCRuntime)
    ) else {
      return
    }

    guard let arcLiteLibPath = try findARCLiteLibPath(),
      let platformName = targetTriple.platformName() else {
        return
    }
    let fullLibPath = arcLiteLibPath
      .appending(components: "libarclite_\(platformName).a")

    commandLine.appendFlag("-force_load")
    commandLine.appendPath(fullLibPath)

    // Arclite depends on CoreFoundation.
    commandLine.appendFlag(.framework)
    commandLine.appendFlag("CoreFoundation")
  }

  /// Adds the arguments necessary to link the files from the given set of
  /// options for a Darwin platform.
  public func addPlatformSpecificLinkerArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    linkerOutputType: LinkOutputType,
    inputs: [TypedVirtualPath],
    outputFile: VirtualPath,
    sdkPath: String?,
    sanitizers: Set<Sanitizer>,
    targetTriple: Triple,
    targetVariantTriple: Triple?
  ) throws -> AbsolutePath {

    // FIXME: If we used Clang as a linker instead of going straight to ld,
    // we wouldn't have to replicate a bunch of Clang's logic here.

    // Always link the regular compiler_rt if it's present. Note that the
    // regular libclang_rt.a uses a fat binary for device and simulator; this is
    // not true for all compiler_rt build products.
    //
    // Note: Normally we'd just add this unconditionally, but it's valid to build
    // Swift and use it as a linker without building compiler_rt.
    let darwinPlatformSuffix =
        targetTriple.darwinPlatform!.with(.device)!.libraryNameSuffix
    let compilerRTPath =
      try clangLibraryPath(
        for: targetTriple,
        parsedOptions: &parsedOptions)
      .appending(component: "libclang_rt.\(darwinPlatformSuffix).a")
    if fileSystem.exists(compilerRTPath) {
      commandLine.append(.path(.absolute(compilerRTPath)))
    }

    // Set up for linking.
    let linkerTool: Tool
    switch linkerOutputType {
    case .dynamicLibrary:
      // Same as an executable, but with the -dylib flag
      commandLine.appendFlag("-dylib")
      fallthrough
    case .executable:
      linkerTool = .dynamicLinker
      let fSystemArgs = parsedOptions.arguments(for: .F, .Fsystem)
      for opt in fSystemArgs {
        commandLine.appendFlag(.F)
        commandLine.appendPath(try VirtualPath(path: opt.argument.asSingle))
      }

      // Linking sanitizers will add rpaths, which might negatively interact when
      // other rpaths are involved, so we should make sure we add the rpaths after
      // all user-specified rpaths.
      for sanitizer in sanitizers {
        if sanitizer == .fuzzer {
          guard linkerOutputType == .executable else { continue }
        }
        try addLinkSanitizerLibArgsForDarwin(
          to: &commandLine,
          parsedOptions: &parsedOptions,
          targetTriple: targetTriple,
          sanitizer: sanitizer,
          isShared: sanitizer != .fuzzer
        )
      }

      commandLine.appendFlag("-arch")
      commandLine.appendFlag(targetTriple.archName)

      try addArgsToLinkStdlib(
        to: &commandLine,
        parsedOptions: &parsedOptions,
        sdkPath: sdkPath,
        targetTriple: targetTriple
      )

      // These custom arguments should be right before the object file at the
      // end.
      try commandLine.append(
        contentsOf: parsedOptions.arguments(in: .linkerOption)
      )
      try commandLine.appendAllArguments(.Xlinker, from: &parsedOptions)

    case .staticLibrary:
      linkerTool = .staticLinker
      commandLine.appendFlag(.static)
    }

    try addArgsToLinkARCLite(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      targetTriple: targetTriple
    )
    addDeploymentTargetArgs(
      to: &commandLine,
      targetTriple: targetTriple,
      targetVariantTriple: targetVariantTriple
    )
    try addProfileGenerationArgs(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      targetTriple: targetTriple
    )

    commandLine.appendFlags(
      "-lobjc",
      "-lSystem",
      "-no_objc_category_merging"
    )

    // Add the SDK path
    if let sdkPath = sdkPath {
      commandLine.appendFlag("-syslibroot")
      commandLine.appendPath(try VirtualPath(path: sdkPath))
    }

    if parsedOptions.contains(.embedBitcode) ||
      parsedOptions.contains(.embedBitcodeMarker) {
      commandLine.appendFlag("-bitcode_bundle")
    }

    if parsedOptions.contains(.enableAppExtension) {
      commandLine.appendFlag("-application_extension")
    }

    // Add inputs.
    commandLine.append(contentsOf: inputs.map { .path($0.file) })

    // Add the output
    commandLine.appendFlag("-o")
    commandLine.appendPath(outputFile)

    return try getToolPath(linkerTool)
  }
}
