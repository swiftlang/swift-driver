//===--------------- GenericUnixToolchain+LinkerSupport.swift -------------===//
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

extension GenericUnixToolchain {
  private func defaultLinker(for targetTriple: Triple) -> String? {
    switch targetTriple.arch {
    case .arm, .aarch64, .armeb, .thumb, .thumbeb:
      // BFD linker has issues wrt relocation of the protocol conformance
      // section on these targets, it also generates COPY relocations for
      // final executables, as such, unless specified, we default to gold
      // linker.
      return "gold"
    case .x86, .x86_64, .ppc64, .ppc64le, .systemz:
      // BFD linker has issues wrt relocations against protected symbols.
      return "gold"
    default:
      // Otherwise, use the default BFD linker.
      return ""
    }
  }

  private func majorArchitectureName(for triple: Triple) -> String {
    // The concept of a "major" arch name only applies to Linux triples
    guard triple.os == .linux else { return triple.archName }

    // HACK: We don't wrap LLVM's ARM target architecture parsing, and we should
    //       definitely not try to port it. This check was only normalizing
    //       "armv7a/armv7r" and similar variants for armv6 to 'armv7' and
    //       'armv6', so just take a brute-force approach
    if triple.archName.contains("armv7") { return "armv7" }
    if triple.archName.contains("armv6") { return "armv6" }
    return triple.archName
  }

  public func addPlatformSpecificLinkerArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    linkerOutputType: LinkOutputType,
    inputs: [TypedVirtualPath],
    outputFile: VirtualPath,
    sdkPath: String?,
    sanitizers: Set<Sanitizer>,
    targetInfo: FrontendTargetInfo
  ) throws -> AbsolutePath {
    let targetTriple = targetInfo.target.triple
    switch linkerOutputType {
    case .dynamicLibrary:
      // Same options as an executable, just with '-shared'
      commandLine.appendFlag("-shared")
      fallthrough
    case .executable:
      if !targetTriple.triple.isEmpty {
        commandLine.appendFlag("-target")
        commandLine.appendFlag(targetTriple.triple)
      }

        // Select the linker to use.
      var linker: String?
      if let arg = parsedOptions.getLastArgument(.useLd) {
        linker = arg.asSingle
      } else {
        linker = defaultLinker(for: targetTriple)
      }

      if let linker = linker {
        #if os(Haiku)
        // For now, passing -fuse-ld on Haiku doesn't work as swiftc doesn't
        // recognise it. Passing -use-ld= as the argument works fine.
        commandLine.appendFlag("-use-ld=\(linker)")
        #else
        commandLine.appendFlag("-fuse-ld=\(linker)")
        #endif
      }

      // Configure the toolchain.
      //
      // By default use the system `clang` to perform the link.  We use `clang` for
      // the driver here because we do not wish to select a particular C++ runtime.
      // Furthermore, until C++ interop is enabled, we cannot have a dependency on
      // C++ code from pure Swift code.  If linked libraries are C++ based, they
      // should properly link C++.  In the case of static linking, the user can
      // explicitly specify the C++ runtime to link against.  This is particularly
      // important for platforms like android where as it is a Linux platform, the
      // default C++ runtime is `libstdc++` which is unsupported on the target but
      // as the builds are usually cross-compiled from Linux, libstdc++ is going to
      // be present.  This results in linking the wrong version of libstdc++
      // generating invalid binaries.  It is also possible to use different C++
      // runtimes than the default C++ runtime for the platform (e.g. libc++ on
      // Windows rather than msvcprt).  When C++ interop is enabled, we will need to
      // surface this via a driver flag.  For now, opt for the simpler approach of
      // just using `clang` and avoid a dependency on the C++ runtime.
      var clangPath = try getToolPath(.clang)
      if let toolsDirPath = parsedOptions.getLastArgument(.toolsDirectory) {
        // FIXME: What if this isn't an absolute path?
        let toolsDir = try AbsolutePath(validating: toolsDirPath.asSingle)

        // If there is a clang in the toolchain folder, use that instead.
        if let tool = lookupExecutablePath(filename: "clang", searchPaths: [toolsDir]) {
          clangPath = tool
        }

        // Look for binutils in the toolchain folder.
        commandLine.appendFlag("-B")
        commandLine.appendPath(toolsDir)
      }

      // Executables on Linux get -pie
      if targetTriple.os == .linux && linkerOutputType == .executable {
        commandLine.appendFlag("-pie")
      }

      let staticStdlib = parsedOptions.hasFlag(positive: .staticStdlib,
                                               negative: .noStaticStdlib,
                                                   default: false)
      let staticExecutable = parsedOptions.hasFlag(positive: .staticExecutable,
                                                   negative: .noStaticExecutable,
                                                  default: false)
      let hasRuntimeArgs = !(staticStdlib || staticExecutable)

      let runtimePaths = try runtimeLibraryPaths(
        for: targetTriple,
        parsedOptions: &parsedOptions,
        sdkPath: sdkPath,
        isShared: hasRuntimeArgs
      )

      if hasRuntimeArgs && targetTriple.environment != .android {
        // FIXME: We probably shouldn't be adding an rpath here unless we know
        //        ahead of time the standard library won't be copied.
        for path in runtimePaths {
          commandLine.appendFlag(.Xlinker)
          commandLine.appendFlag("-rpath")
          commandLine.appendFlag(.Xlinker)
          commandLine.appendPath(path)
        }
      }

      let sharedResourceDirPath = try computeResourceDirPath(
        for: targetTriple,
        parsedOptions: &parsedOptions,
        isShared: true
      )

      let swiftrtPath = sharedResourceDirPath
        .appending(
          components: String(majorArchitectureName(for: targetTriple)), "swiftrt.o"
        )
      commandLine.appendPath(swiftrtPath)

      let inputFiles: [Job.ArgTemplate] = inputs.compactMap { input in
        // Autolink inputs are handled specially
        if input.type == .autolink {
          return .responseFilePath(input.file)
        } else if input.type == .object {
          return .path(input.file)
        } else {
          return nil
        }
      }
      commandLine.append(contentsOf: inputFiles)

      let fSystemArgs = parsedOptions.arguments(for: .F, .Fsystem)
      for opt in fSystemArgs {
        if opt.option == .Fsystem {
          commandLine.appendFlag("-iframework")
        } else {
          commandLine.appendFlag(.F)
        }
        commandLine.appendPath(try VirtualPath(path: opt.argument.asSingle))
      }

      if let path = sdkPath {
        commandLine.appendFlag("--sysroot")
        commandLine.appendFlag(path)
      }

      // Add the runtime library link paths.
      for path in runtimePaths {
        commandLine.appendFlag(.L)
        commandLine.appendPath(path)
      }

      // Link the standard library. In two paths, we do this using a .lnk file
      // if we're going that route, we'll set `linkFilePath` to the path to that
      // file.
      var linkFilePath: AbsolutePath? = try computeResourceDirPath(
        for: targetTriple,
        parsedOptions: &parsedOptions,
        isShared: false
      )

      if staticExecutable {
        linkFilePath = linkFilePath?.appending(component: "static-executable-args.lnk")
      } else if staticStdlib {
        linkFilePath = linkFilePath?.appending(component: "static-stdlib-args.lnk")
      } else {
        linkFilePath = nil
        commandLine.appendFlag("-lswiftCore")
      }

      if let linkFile = linkFilePath {
        guard fileSystem.isFile(linkFile) else {
          fatalError("\(linkFile.pathString) not found")
        }
        commandLine.append(.responseFilePath(.absolute(linkFile)))
      }

      // Explicitly pass the target to the linker
      commandLine.appendFlag("--target=\(targetTriple.triple)")

      // Delegate to Clang for sanitizers. It will figure out the correct linker
      // options.
      if linkerOutputType == .executable && !sanitizers.isEmpty {
        let sanitizerNames = sanitizers
          .map { $0.rawValue }
          .sorted() // Sort so we get a stable, testable order
          .joined(separator: ",")
        commandLine.appendFlag("-fsanitize=\(sanitizerNames)")

        // The TSan runtime depends on the blocks runtime and libdispatch.
        if sanitizers.contains(.thread) {
          commandLine.appendFlag("-lBlocksRuntime")
          commandLine.appendFlag("-ldispatch")
        }
      }

      if parsedOptions.hasArgument(.profileGenerate) {
        let libProfile = sharedResourceDirPath
          .parentDirectory // remove platform name
          .appending(components: "clang", "lib", targetTriple.osName,
                                 "libclangrt_profile-\(targetTriple.archName).a")
        commandLine.appendPath(libProfile)

        // HACK: Hard-coded from llvm::getInstrProfRuntimeHookVarName()
        commandLine.appendFlag("-u__llvm_profile_runtime")
      }

      // Run clang++ in verbose mode if "-v" is set
      try commandLine.appendLast(.v, from: &parsedOptions)

      // These custom arguments should be right before the object file at the
      // end.
      try commandLine.append(
        contentsOf: parsedOptions.arguments(in: .linkerOption)
      )
      try commandLine.appendAllArguments(.Xlinker, from: &parsedOptions)
      try commandLine.appendAllArguments(.XclangLinker, from: &parsedOptions)

        // This should be the last option, for convenience in checking output.
      commandLine.appendFlag(.o)
      commandLine.appendPath(outputFile)
      return clangPath
    case .staticLibrary:
      // We're using 'ar' as a linker
      commandLine.appendFlag("crs")
      commandLine.appendPath(outputFile)

      commandLine.append(contentsOf: inputs.map { .path($0.file) })
      return try getToolPath(.staticLinker)
    }

  }
}
