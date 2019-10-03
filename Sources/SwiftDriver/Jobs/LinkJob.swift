import TSCBasic

extension Driver {
  /// Compute the output file for an image output.
  private func outputFileForImage(inputs: [InputFile]) -> VirtualPath {
    // FIXME: The check for __bad__ here, is
    if inputs.count == 1 && moduleName == "__bad__" && inputs.first!.file != .standardInput {
      // FIXME: llvm::sys::path::stem(BaseInput);
    }

    let outputName = toolchain.makeLinkerOutputFilename(moduleName: moduleName, type: linkerOutputType!)
    return .relative(RelativePath(outputName))
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
    // Remove platform name.
      .parentDirectory
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
    commandLine.appendFlag("-L")
    commandLine.appendPath(path)
  }

  if parsedOptions.hasArgument(.toolchain_stdlib_rpath) {
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

  /// Link the given inputs.
  mutating func linkJob(inputs: [InputFile]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = []

    // FIXME: If we used Clang as a linker instead of going straight to ld,
    // we wouldn't have to replicate a bunch of Clang's logic here.

    // Always link the regular compiler_rt if it's present.
    //
    // Note: Normally we'd just add this unconditionally, but it's valid to build
    // Swift and use it as a linker without building compiler_rt.
    let darwinPlatformSuffix = targetTriple.darwinLibraryNameSuffix(distinguishSimulator: false)!
    let compilerRTPath = try clangLibraryPath(for: targetTriple)
      .appending(component: "libclang_rt.\(darwinPlatformSuffix).a")
    if localFileSystem.exists(compilerRTPath) {
      commandLine.append(.path(.absolute(compilerRTPath)))
    }

    // Set up for linking.
    let linkerTool: Tool
    switch linkerOutputType! {
    case .executable:
      linkerTool = .dynamicLinker
      break

    case .dynamicLibrary:
      commandLine.appendFlag("-dylib")
      linkerTool = .dynamicLinker

    case .staticLibrary:
      // FIXME: handle this, somehow
      linkerTool = .staticLinker
      break
    }

    // Add inputs.
    let inputFiles = inputs.map { $0.file }
    commandLine.append(contentsOf: inputFiles.map { .path($0) })

    // Add the output
    commandLine.appendFlag("-o")
    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = outputFileForImage(inputs: inputs)
    }
    commandLine.appendPath(outputFile)

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
      commandLine.appendFlag("-application_extension");
    }

    let fSystemArgs = parsedOptions.filter {
      $0.option == .F || $0.option == .Fsystem
    }
    for opt in fSystemArgs {
      commandLine.appendFlag("-F")
      commandLine.appendFlag(opt.argument.asSingle)
    }

    // FIXME: Sanitizer args

    // FIXME: We need Triple.archName or something along those lines,
    //        for now hard code x86_64 for testing
    commandLine.appendFlag("-arch")
    commandLine.appendFlag("x86_64")
//    commandLine.appendFlag(targetTriple.archName)

    commandLine.appendFlags(
      "-lobjc",
      "-lSystem",
      "-no_objc_category_merging"
    )

    try addArgsToLinkStdlib(&commandLine)

    // FIXME: Implement these
    //    addArgsToLinkARCLite(Arguments, context)
    //    addProfileGenerationArgs(Arguments, context)
    //    addDeploymentTargetArgs(Arguments, context)

    // These custom arguments should be right before the object file at the end.
    try commandLine.append(
      contentsOf: parsedOptions.filter { $0.option.group == .linker_option }
    )
    try commandLine.appendAllArguments(.Xlinker, from: &parsedOptions)

    return Job(
      tool: .absolute(try toolchain.getToolPath(linkerTool)),
      commandLine: commandLine,
      inputs: inputFiles,
      outputs: [outputFile]
    )
  }
}
