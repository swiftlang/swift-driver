import TSCBasic

extension Driver {
  /// Returns true if the compiler depends on features provided by the ObjC
  /// runtime that are not present on the deployment target indicated by
  /// `triple`.
  func wantsObjCRuntime(triple: Triple) -> Bool {
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

  /// Compute the output file for an image output.
  private func outputFileForImage(inputs: [TypedVirtualPath]) -> VirtualPath {
    // FIXME: The check for __bad__ here, is
    if inputs.count == 1 && moduleName == "__bad__" && inputs.first!.file != .standardInput {
      // FIXME: llvm::sys::path::stem(BaseInput);
    }

    let outputName = toolchain.makeLinkerOutputFilename(moduleName: moduleName, type: linkerOutputType!)
    return .relative(RelativePath(outputName))
  }

  // MARK: - Path computation

  func findARCLiteLibPath() throws -> AbsolutePath? {
    let path = try toolchain.getToolPath(.swiftCompiler)
      .parentDirectory // 'swift'
      .parentDirectory // 'bin'
      .appending(components: "lib", "arc")

    if localFileSystem.exists(path) { return path }

    // If we don't have a 'lib/arc/' directory, find the "arclite" library
    // relative to the Clang in the active Xcode.
    if let clangPath = try? toolchain.getToolPath(.clang) {
      return clangPath
        .parentDirectory // 'clang'
        .parentDirectory // 'bin'
        .appending(components: "lib", "arc")
    }
    return nil
  }

  mutating func computeResourceDirPath(for triple: Triple, isShared: Bool) throws -> AbsolutePath {
    // FIXME: This almost certainly won't be an absolute path in practice...
    let resourceDirBase: AbsolutePath
    if let resourceDir = parsedOptions.getLastArgument(.resource_dir) {
      resourceDirBase = try AbsolutePath(validating: resourceDir.asSingle)
    } else if let sdk = parsedOptions.getLastArgument(.sdk), !triple.os.isDarwin {
      resourceDirBase = try AbsolutePath(validating: sdk.asSingle)
        .appending(components: "usr", "lib",
                   isShared ? "swift" : "swift_static")
    } else {
      resourceDirBase = try toolchain.getToolPath(.swiftCompiler)
        .parentDirectory // remove /swift
        .parentDirectory // remove /bin
        .appending(components: "lib", isShared ? "swift" : "swift_static")
    }
    return resourceDirBase.appending(components: triple.platformName ?? "")
  }

  mutating func clangLibraryPath(for triple: Triple) throws -> AbsolutePath {
    return try computeResourceDirPath(for: triple, isShared: true)
      .parentDirectory // Remove platform name.
      .appending(components: "clang", "lib",
                 triple.os.isDarwin ? "darwin" : triple.platformName!)
  }

  mutating func runtimeLibraryPaths(for triple: Triple, isShared: Bool) throws -> [AbsolutePath] {
    var result = [try computeResourceDirPath(for: triple, isShared: isShared)]

    if let path = sdkPath {
      result.append(AbsolutePath(path).appending(RelativePath("usr/lib/swift")))
    }

    return result
  }

  // MARK: - Common argument routines

  mutating func addProfileGenerationArgs(_ commandLine: inout [Job.ArgTemplate]) throws {
    guard parsedOptions.hasArgument(.profile_generate) else { return }
    let clangPath = try clangLibraryPath(for: targetTriple)

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

  mutating func addDeploymentTargetArgs(_ commandLine: inout [Job.ArgTemplate]) {
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

  mutating func addArgsToLinkARCLite(_ commandLine: inout [Job.ArgTemplate]) throws {
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
    commandLine.appendFlag("-framework")
    commandLine.appendFlag("CoreFoundation")
  }

  mutating func addArgsToLinkStdlib(_ commandLine: inout [Job.ArgTemplate]) throws {

    // Link compatibility libraries, if we're deploying back to OSes that
    // have an older Swift runtime.
//    let sharedResourceDirPath = try computeResourceDirPath(for: targetTriple,
//                                                           isShared: true)
//    Optional<llvm::VersionTuple> runtimeCompatibilityVersion;
//
//    if (context.Args.hasArg(options::OPT_runtime_compatibility_version)) {
//      auto value = context.Args.getLastArgValue(
//                                      options::OPT_runtime_compatibility_version);
//      if (value.equals("5.0")) {
//        runtimeCompatibilityVersion = llvm::VersionTuple(5, 0);
//      } else if (value.equals("none")) {
//        runtimeCompatibilityVersion = None;
//      } else {
//        // TODO: diagnose unknown runtime compatibility version?
//      }
//    } else if (job.getKind() == LinkKind::Executable) {
//      runtimeCompatibilityVersion
//                     = getSwiftRuntimeCompatibilityVersionForTarget(getTriple());
//    }
//
//    if (runtimeCompatibilityVersion) {
//      if (*runtimeCompatibilityVersion <= llvm::VersionTuple(5, 0)) {
//        // Swift 5.0 compatibility library
//        SmallString<128> BackDeployLib;
//        BackDeployLib.append(SharedResourceDirPath);
//        llvm::sys::path::append(BackDeployLib, "libswiftCompatibility50.a");
//
//        if (llvm::sys::fs::exists(BackDeployLib)) {
//          Arguments.push_back("-force_load");
//          Arguments.push_back(context.Args.MakeArgString(BackDeployLib));
//        }
//      }
//    }
//
//    if (job.getKind() == LinkKind::Executable) {
//      if (runtimeCompatibilityVersion)
//        if (*runtimeCompatibilityVersion <= llvm::VersionTuple(5, 0)) {
//          // Swift 5.0 dynamic replacement compatibility library.
//          SmallString<128> BackDeployLib;
//          BackDeployLib.append(SharedResourceDirPath);
//          llvm::sys::path::append(BackDeployLib,
//                                  "libswiftCompatibilityDynamicReplacements.a");
//
//          if (llvm::sys::fs::exists(BackDeployLib)) {
//            Arguments.push_back("-force_load");
//            Arguments.push_back(context.Args.MakeArgString(BackDeployLib));
//          }
//        }
//    }

    // Add the runtime library link path, which is platform-specific and found
    // relative to the compiler.
    let runtimePaths = try runtimeLibraryPaths(for: targetTriple, isShared: true)
    for path in runtimePaths {
      commandLine.appendFlag(.L)
      commandLine.appendPath(path)
    }

    if parsedOptions.hasFlag(positive: .toolchain_stdlib_rpath,
                             negative: .no_toolchain_stdlib_rpath,
                             default: false) {
      // If the user has explicitly asked for a toolchain stdlib, we should
      // provide one using -rpath. This used to be the default behaviour but it
      // was considered annoying in at least the SwiftPM scenario (see
      // https://bugs.swift.org/browse/SR-1967) and is obsolete in all scenarios
      // of deploying for Swift-in-the-OS. We keep it here as an optional
      // behaviour so that people downloading snapshot toolchains for testing new
      // stdlibs will be able to link to the stdlib bundled in that toolchain.
      for path in runtimePaths {
        commandLine.appendFlag("-rpath")
        commandLine.appendPath(path)
      }
    } else if !targetTriple.requiresRPathForSwiftInTheOS || parsedOptions.hasArgument(.no_stdlib_rpath) {
      // If targeting an OS with Swift in /usr/lib/swift, the LC_ID_DYLIB
      // install_name the stdlib will be an absolute path like
      // /usr/lib/swift/libswiftCore.dylib, and we do not need to provide an rpath
      // at all.
      //
      // Also, if the user explicitly asks for no rpath entry, we assume they know
      // what they're doing and do not add one here.
    } else {
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
      commandLine.appendFlag("-rpath")
      commandLine.appendPath(.absolute(AbsolutePath("/usr/lib/swift")))
    }
  }

  // MARK: - Construct link job

  /// Link the given inputs.
  mutating func linkJob(inputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = []

    // FIXME: If we used Clang as a linker instead of going straight to ld,
    // we wouldn't have to replicate a bunch of Clang's logic here.

    // Always link the regular compiler_rt if it's present.
    //
    // Note: Normally we'd just add this unconditionally, but it's valid to build
    // Swift and use it as a linker without building compiler_rt.
    if let darwinPlatformSuffix =
      targetTriple.darwinLibraryNameSuffix(distinguishSimulator: false) {
      let compilerRTPath = try clangLibraryPath(for: targetTriple)
        .appending(component: "libclang_rt.\(darwinPlatformSuffix).a")
      if localFileSystem.exists(compilerRTPath) {
        commandLine.append(.path(.absolute(compilerRTPath)))
      }
    }

    // Set up for linking.
    let linkerTool: Tool
    switch linkerOutputType! {
    case .dynamicLibrary:
      // Same options as an executable, just with the '-dylib' flag passed
      commandLine.appendFlag("-dylib")
      fallthrough
    case .executable:
      linkerTool = .dynamicLinker

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

      commandLine.appendFlags(
        "-lobjc",
        "-lSystem",
        "-no_objc_category_merging"
      )

      try addArgsToLinkStdlib(&commandLine)
      try addArgsToLinkARCLite(&commandLine)
      addDeploymentTargetArgs(&commandLine)
      try addProfileGenerationArgs(&commandLine)

      // These custom arguments should be right before the object file at the end.
      try commandLine.append(
        contentsOf: parsedOptions.filter { $0.option.group == .linker_option }
      )
      try commandLine.appendAllArguments(.Xlinker, from: &parsedOptions)

    case .staticLibrary:
      commandLine.appendFlag("-static")
      linkerTool = .staticLinker
      break
    }

    // Add inputs.
    let inputFiles = inputs
    commandLine.append(contentsOf: inputFiles.map { .path($0.file) })

    // Add the output
    commandLine.appendFlag("-o")
    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = outputFileForImage(inputs: inputs)
    }
    commandLine.appendPath(outputFile)

    return Job(
      kind: .link,
      tool: .absolute(try toolchain.getToolPath(linkerTool)),
      commandLine: commandLine,
      inputs: inputFiles,
      outputs: [.init(file: outputFile, type: .object)]
    )
  }
}
