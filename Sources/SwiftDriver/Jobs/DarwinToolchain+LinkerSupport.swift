import TSCBasic
import TSCUtility

extension DarwinToolchain {
  private func findARCLiteLibPath() throws -> AbsolutePath? {
    let path = try getToolPath(.swiftCompiler)
      .parentDirectory // 'swift'
      .parentDirectory // 'bin'
      .appending(components: "lib", "arc")

    if localFileSystem.exists(path) { return path }

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

  private func addProfileGenerationArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetTriple: Triple
  ) throws {
    guard parsedOptions.hasArgument(.profile_generate) else { return }
    let clangPath = try clangLibraryPath(for: targetTriple,
                                         parsedOptions: &parsedOptions)

    let runtime: String
    if targetTriple.os.isiOS {
      runtime = targetTriple.os.isTvOS ? "tvos" : "ios"
    } else if targetTriple.os.isWatchOS {
      runtime = "watchos"
    } else {
      assert(targetTriple.os.isMacOSX)
      runtime = "osx"
    }

    var sim = ""
    if targetTriple.isSimulatorEnvironment {
      sim = "sim"
    }

    var clangRTPath = clangPath
      .appending(component: "libclang_rt.profile_\(runtime)\(sim).a")

    // FIXME: Continue accepting the old path for simulator libraries for now.
    if targetTriple.isSimulatorEnvironment &&
      !localFileSystem.exists(clangRTPath) {
      clangRTPath = clangRTPath.parentDirectory
        .appending(component: "libclang_rt.profile_\(runtime).a")
    }

    commandLine.appendPath(clangRTPath)
  }

  private func addDeploymentTargetArgs(
    to commandLine: inout [Job.ArgTemplate],
    targetTriple: Triple
  ) {
    // FIXME: Properly handle deployment targets.
    assert(targetTriple.os.isiOS || targetTriple.os.isWatchOS || targetTriple.os.isMacOSX)

    if (targetTriple.os.isiOS) {
      if (targetTriple.os.isTvOS) {
        if targetTriple.isSimulatorEnvironment {
          commandLine.appendFlag("-tvos_simulator_version_min")
        } else {
          commandLine.appendFlag("-tvos_version_min")
        }
      } else {
        if targetTriple.isSimulatorEnvironment {
          commandLine.appendFlag("-ios_simulator_version_min")
        } else {
          commandLine.appendFlag("-iphoneos_version_min")
        }
      }
      commandLine.appendFlag(targetTriple.iOSVersion().description)
    } else if targetTriple.os.isWatchOS {
      if targetTriple.isSimulatorEnvironment {
        commandLine.appendFlag("-watchos_simulator_version_min")
      } else {
        commandLine.appendFlag("-watchos_version_min")
      }
      commandLine.appendFlag(targetTriple.watchOSVersion().description)
    } else {
      commandLine.appendFlag("-macosx_version_min")
      commandLine.appendFlag(targetTriple.getMacOSXVersion().1.description)
    }
  }

  /// Returns true if the compiler depends on features provided by the ObjC
  /// runtime that are not present on the deployment target indicated by
  /// `triple`.
  private func wantsObjCRuntime(triple: Triple) -> Bool {
    // When updating the versions listed here, please record the most recent
    // feature being depended on and when it was introduced:
    //
    // - Make assigning 'nil' to an NSMutableDictionary subscript delete the
    //   entry, like it does for Swift.Dictionary, rather than trap.
    if triple.os.isiOS {
      return triple.iOSVersion() < Triple.Version(9, 0, 0)
    } else if triple.os.isMacOSX {
      return triple.getMacOSXVersion().1 < Triple.Version(10, 11, 0)
    } else if triple.os.isWatchOS {
      return false
    }
    fatalError("unknown Darwin OS")
  }

  private func addArgsToLinkARCLite(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetTriple: Triple
  ) throws {
    if !parsedOptions.hasFlag(positive: .link_objc_runtime,
                              negative: .no_link_objc_runtime,
                              default: wantsObjCRuntime(triple: targetTriple)) {
      return
    }

    guard let arcLiteLibPath = try findARCLiteLibPath(),
      let platformName = targetTriple.platformName else {
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
    targetTriple: Triple
  ) throws -> AbsolutePath {

    // FIXME: If we used Clang as a linker instead of going straight to ld,
    // we wouldn't have to replicate a bunch of Clang's logic here.

    // Always link the regular compiler_rt if it's present.
    //
    // Note: Normally we'd just add this unconditionally, but it's valid to build
    // Swift and use it as a linker without building compiler_rt.
    let darwinPlatformSuffix =
      targetTriple.darwinLibraryNameSuffix(distinguishSimulator: false)!
    let compilerRTPath =
      try clangLibraryPath(
        for: targetTriple, parsedOptions: &parsedOptions)
      .appending(component: "libclang_rt.\(darwinPlatformSuffix).a")
    if localFileSystem.exists(compilerRTPath) {
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
      let fSystemArgs = parsedOptions.filter {
        $0.option == .F || $0.option == .Fsystem
      }
      for opt in fSystemArgs {
        commandLine.appendFlag(.F)
        commandLine.appendPath(try VirtualPath(path: opt.argument.asSingle))
      }

      // FIXME: Sanitizer args

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
        contentsOf: parsedOptions.filter { $0.option.group == .linker_option }
      )
      try commandLine.appendAllArguments(.Xlinker, from: &parsedOptions)

    case .staticLibrary:
      linkerTool = .staticLinker
      commandLine.appendFlag(.static)
      break
    }

    try addArgsToLinkARCLite(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      targetTriple: targetTriple
    )
    addDeploymentTargetArgs(
      to: &commandLine,
      targetTriple: targetTriple
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

    if parsedOptions.contains(.embed_bitcode) ||
      parsedOptions.contains(.embed_bitcode_marker) {
      commandLine.appendFlag("-bitcode_bundle")
    }

    if parsedOptions.contains(.enable_app_extension) {
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
