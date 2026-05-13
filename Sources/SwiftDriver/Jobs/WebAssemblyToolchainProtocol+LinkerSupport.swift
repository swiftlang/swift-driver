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

extension WebAssemblyToolchainProtocol {
  /// Emits the segment of the WebAssembly link command that precedes the
  /// WASI-specific `--sysroot` and the `-L <runtimePaths>` loop. Returns the
  /// runtime library paths so the caller can emit `-L` entries in the correct
  /// position relative to `--sysroot`.
  func addSharedWebAssemblyLinkerPreamble(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    inputs: [TypedVirtualPath],
    lto: LTOKind?,
    targetInfo: FrontendTargetInfo
  ) throws -> [VirtualPath] {
    let targetTriple = targetInfo.target.triple

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

    return runtimePaths
  }

  /// Emits the tail of the WebAssembly link command, shared byte-for-byte
  /// between the WASI (`wasm-ld`) and Emscripten (`emcc`) paths. The caller is
  /// responsible for everything past `addLinkedLibArgs` — linker-option
  /// forwarding and the `-o outputFile` pair — because those diverge between
  /// the two toolchains.
  func addSharedWebAssemblyLinkerTail(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    sanitizers: Set<Sanitizer>,
    lto: LTOKind?,
    targetInfo: FrontendTargetInfo,
    linkerOutputType: LinkOutputType
  ) throws {
    let targetTriple = targetInfo.target.triple

    // Delegate to Clang for sanitizers. It will figure out the correct linker
    // options.
    if linkerOutputType == .executable && !sanitizers.isEmpty {
      let sanitizerNames = sanitizers
        .map { $0.rawValue }
        .sorted() // Sort so we get a stable, testable order
        .joined(separator: ",")
      commandLine.appendFlag("-fsanitize=\(sanitizerNames)")
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

    // Run `clang++` in verbose mode if `-v` is set
    try commandLine.appendLast(.v, from: &parsedOptions)

    // These custom arguments should be right before the object file at the
    // end.
    try commandLine.appendAllExcept(
      includeList: [.linkerOption],
      excludeList: [.l],
      from: &parsedOptions
    )
    addLinkedLibArgs(to: &commandLine, parsedOptions: &parsedOptions)
  }
}
