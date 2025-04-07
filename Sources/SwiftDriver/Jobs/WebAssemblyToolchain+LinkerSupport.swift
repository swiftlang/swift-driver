//===--------------- WebAssemblyToolchain+LinkerSupport.swift -------------===//
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

import SwiftOptions

import func TSCBasic.lookupExecutablePath
import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath

extension WebAssemblyToolchain {
  public func addPlatformSpecificLinkerArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    linkerOutputType: LinkOutputType,
    inputs: [TypedVirtualPath],
    outputFile: VirtualPath,
    shouldUseInputFileList: Bool,
    lto: LTOKind?,
    sanitizers: Set<Sanitizer>,
    targetInfo: FrontendTargetInfo
  ) throws -> ResolvedTool {
    let targetTriple = targetInfo.target.triple
    switch linkerOutputType {
    case .dynamicLibrary:
      throw Error.dynamicLibrariesUnsupportedForTarget(targetTriple.triple)
    case .executable:
      if !targetTriple.triple.isEmpty {
        commandLine.appendFlag("-target")
        commandLine.appendFlag(targetTriple.triple)
      }

      // Select the linker to use.
      if let linkerArg = parsedOptions.getLastArgument(.useLd)?.asSingle {
        commandLine.appendFlag("-fuse-ld=\(linkerArg)")
      }

      if let arg = parsedOptions.getLastArgument(.ldPath)?.asSingle {
        commandLine.append(.joinedOptionAndPath("--ld-path=", try VirtualPath(path: arg)))
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

      guard !parsedOptions.hasArgument(.noStaticStdlib, .noStaticExecutable) else {
        throw Error.dynamicLibrariesUnsupportedForTarget(targetTriple.triple)
      }

      let runtimePaths = try runtimeLibraryPaths(
        for: targetInfo,
        parsedOptions: &parsedOptions,
        sdkPath: targetInfo.sdkPath?.path,
        isShared: false
      )

      if !parsedOptions.hasArgument(.nostartfiles) && !parsedOptions.isEmbeddedEnabled {
        let swiftrtPath = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
          .appending(
            components: targetTriple.platformName() ?? "",
            targetTriple.archName,
            "swiftrt.o"
          )
        commandLine.appendPath(swiftrtPath)
      }

      let inputFiles: [Job.ArgTemplate] = inputs.compactMap { input in
        // Autolink inputs are handled specially
        if input.type == .autolink {
          return .responseFilePath(input.file)
        } else if input.type == .object {
          return .path(input.file)
        } else if lto != nil && input.type == .llvmBitcode {
          return .path(input.file)
        } else {
          return nil
        }
      }
      commandLine.append(contentsOf: inputFiles)

      if let path = targetInfo.sdkPath?.path {
        commandLine.appendFlag("--sysroot")
        commandLine.appendPath(VirtualPath.lookup(path))
      }

      // Add the runtime library link paths.
      for path in runtimePaths {
        commandLine.appendFlag(.L)
        commandLine.appendPath(path)
      }

      let runtimeResourcePath = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
      if parsedOptions.isEmbeddedEnabled {
        // Allow linking certain standard library modules (`_Concurrency` etc)
        let embeddedLibrariesPath: VirtualPath = runtimeResourcePath.appending(
          components: "embedded", targetTriple.triple
        )
        commandLine.append(.flag("-Xlinker"))
        commandLine.append(.joinedOptionAndPath("-L", embeddedLibrariesPath))
      } else {
        // Link the standard library and dependencies.
        let linkFilePath: VirtualPath = runtimeResourcePath
          .appending(components: targetTriple.platformName() ?? "",
                     "static-executable-args.lnk")
        guard try fileSystem.exists(linkFilePath) else {
          throw Error.missingExternalDependency(linkFilePath.name)
        }
        commandLine.append(.responseFilePath(linkFilePath))
      }

      // Pass down an optimization level
      if let optArg = mapOptimizationLevelToClangArg(from: &parsedOptions) {
        commandLine.appendFlag(optArg)
      }

      // Explicitly pass the target to the linker
      commandLine.appendFlag("--target=\(targetTriple.triple)")

      // WebAssembly doesn't reserve low addresses as its ABI. But without
      // "extra inhabitants" of the pointer representation, runtime performance
      // and memory footprint are significantly degraded. So we reserve the
      // low addresses to use them as extra inhabitants by telling the lowest
      // valid address to the linker.
      // The value of lowest valid address, called "global base", must be always
      // synchronized with `SWIFT_ABI_WASM32_LEAST_VALID_POINTER` defined in
      // apple/swift's runtime library.
      commandLine.appendFlag(.Xlinker)
      commandLine.appendFlag("--global-base=4096")

      // Delegate to Clang for sanitizers. It will figure out the correct linker
      // options.
      guard sanitizers.isEmpty else {
        throw Error.sanitizersUnsupportedForTarget(targetTriple.triple)
      }

      if parsedOptions.hasArgument(.profileGenerate) {
        let libProfile = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
          .appending(components: "clang", "lib", targetTriple.osName,
                                 "libclang_rt.profile-\(targetTriple.archName).a")
        commandLine.appendPath(libProfile)
      }

      if let lto = lto {
        switch lto {
        case .llvmFull:
          commandLine.appendFlag("-flto=full")
        case .llvmThin:
          commandLine.appendFlag("-flto=thin")
        }
      }

      // Run clang++ in verbose mode if "-v" is set
      try commandLine.appendLast(.v, from: &parsedOptions)

      // These custom arguments should be right before the object file at the
      // end.
      try commandLine.appendAllExcept(
        includeList: [.linkerOption],
        excludeList: [.l],
        from: &parsedOptions
      )
      addLinkedLibArgs(to: &commandLine, parsedOptions: &parsedOptions)
      try addExtraClangLinkerArgs(to: &commandLine, parsedOptions: &parsedOptions)

        // This should be the last option, for convenience in checking output.
      commandLine.appendFlag(.o)
      commandLine.appendPath(outputFile)
      return try resolvedTool(.clang, pathOverride: clangPath)
    case .staticLibrary:
      // We're using 'ar' as a linker
      commandLine.appendFlag("crs")
      commandLine.appendPath(outputFile)

      commandLine.append(contentsOf: inputs.lazy.filter { $0.type != .autolink }.map { .path($0.file) })
      return try resolvedTool(.staticLinker(lto))
    }
  }
}
