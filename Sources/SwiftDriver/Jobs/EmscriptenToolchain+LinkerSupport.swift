//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import SwiftOptions

import func TSCBasic.lookupExecutablePath
import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath

extension EmscriptenToolchain {
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
      // `guard` throws, so ordering vs. `linkerPath` computation is semantically equivalent
      guard !parsedOptions.hasArgument(.noStaticStdlib, .noStaticExecutable) else {
        throw Error.dynamicLibrariesUnsupportedForTarget(targetTriple.triple)
      }

      // Use `emcc` (the Emscripten compiler driver) as the linker. `emcc` wraps
      // `wasm-ld` and also generates JavaScript runtime glue. `emcc` already targets
      // Emscripten, so `--target` and linker selection flags are not emitted.
      var linkerPath = try getToolPath(.emcc)
      if let toolsDirPath = parsedOptions.getLastArgument(.toolsDirectory) {
        let toolsDir = try AbsolutePath(validating: toolsDirPath.asSingle)
        if let tool = lookupExecutablePath(filename: "emcc", searchPaths: [toolsDir]) {
          linkerPath = tool
        }
        // `emcc` manages its own tool search paths and doesn't support
        // the `-B` flag like `clang` does, so don't forward it.
      }

      let runtimePaths = try addSharedWebAssemblyLinkerPreamble(
        to: &commandLine,
        parsedOptions: &parsedOptions,
        inputs: inputs,
        lto: lto,
        targetInfo: targetInfo
      )

      // `emcc` manages its own sysroot, so `--sysroot` is not emitted.

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

      // WebAssembly doesn't reserve low addresses as its ABI. But without
      // "extra inhabitants" of the pointer representation, runtime performance
      // and memory footprint are significantly degraded. So we reserve the
      // low addresses to use them as extra inhabitants by telling the lowest
      // valid address to the linker.
      // The value of lowest valid address, called "global base", must be always
      // synchronized with `SWIFT_ABI_WASM32_LEAST_VALID_POINTER` defined in
      // apple/swift's runtime library.
      //
      // Use `emcc` settings instead of raw `wasm-ld` flags. Setting `-sGLOBAL_BASE`
      // prevents `emcc` from auto-enabling `--stack-first`, which would place the
      // stack at address 0 and violate Swift's assumption that addresses below
      // `LEAST_VALID_POINTER` are unused.
      let SWIFT_ABI_WASM32_LEAST_VALID_POINTER = 4096
      commandLine.appendFlag("-sGLOBAL_BASE=\(SWIFT_ABI_WASM32_LEAST_VALID_POINTER)")
      commandLine.appendFlag("-sTABLE_BASE=\(SWIFT_ABI_WASM32_LEAST_VALID_POINTER)")

      // Set slightly higher than the default (64K) stack size so that basic
      // workflows like Swift Testing can run within this limited stack space.
      let SWIFT_WASM_DEFAULT_STACK_SIZE = 1024 * 128
      commandLine.appendFlag("-sSTACK_SIZE=\(SWIFT_WASM_DEFAULT_STACK_SIZE)")

      try addSharedWebAssemblyLinkerTail(
        to: &commandLine,
        parsedOptions: &parsedOptions,
        sanitizers: sanitizers,
        lto: lto,
        targetInfo: targetInfo
      )

      // `emcc` supports `-Xlinker` for passing flags to `wasm-ld`. `-Xclang-linker`
      // is intentionally not forwarded here; `EmscriptenToolchain.validateArgs`
      // emits a warning at parse time directing users to `-Xemcc-linker` instead.
      for linkerOpt in parsedOptions.arguments(for: .Xlinker) {
        commandLine.appendFlag(.Xlinker)
        commandLine.appendFlag(linkerOpt.argument.asSingle)
      }
      // `-Xemcc-linker` passes arguments directly to `emcc`.
      try commandLine.appendAllArguments(.XemccLinker, from: &parsedOptions)

      // This should be the last option, for convenience in checking output.
      commandLine.appendFlag(.o)
      commandLine.appendPath(outputFile)
      return try resolvedTool(.emcc, pathOverride: linkerPath)
    case .staticLibrary:
      // We're using `ar` as a linker
      commandLine.appendFlag("crs")
      commandLine.appendPath(outputFile)

      commandLine.append(contentsOf: inputs.lazy.filter { $0.type != .autolink }.map { .path($0.file) })
      return try resolvedTool(.staticLinker(lto))
    }
  }
}
