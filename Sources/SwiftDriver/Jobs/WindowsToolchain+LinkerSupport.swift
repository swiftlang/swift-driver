//===--------------- WindowsToolchain+LinkerSupport.swift -----------------===//
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

extension WindowsToolchain {
  public func addPlatformSpecificLinkerArgs(to commandLine: inout [Job.ArgTemplate],
                                            parsedOptions: inout ParsedOptions,
                                            linkerOutputType: LinkOutputType,
                                            inputs: [TypedVirtualPath],
                                            outputFile: VirtualPath,
                                            shouldUseInputFileList: Bool,
                                            lto: LTOKind?,
                                            sanitizers: Set<Sanitizer>,
                                            targetInfo: FrontendTargetInfo)
      throws -> AbsolutePath {
    let targetTriple = targetInfo.target.triple

    if !targetTriple.triple.isEmpty {
      commandLine.appendFlag("-target")
      commandLine.appendFlag(targetTriple.triple)
    }

    switch linkerOutputType {
    case .staticLibrary:
      break
    case .dynamicLibrary:
      commandLine.appendFlag("-shared")
    case .executable:
      break
    }

    // Select the linker to use.
    if let arg = parsedOptions.getLastArgument(.useLd) {
      commandLine.appendFlag("-fuse-ld=\(arg.asSingle)")
    } else if lto != nil {
      commandLine.appendFlag("-fuse-ld=lld")
    }

    switch lto {
    case .some(.llvmThin):
      commandLine.appendFlag("-flto=thin")
    case .some(.llvmFull):
      commandLine.appendFlag("-flto=full")
    case .none:
      break
    }

    // FIXME(compnerd): render `-Xlinker /DEBUG` or `-Xlinker /DEBUG:DWARF` with
    // DWARF + lld

    // Rely on `-libc` to correctly identify the MSVC Runtime Library.  We use
    // `-nostartfiles` as that limits the difference to just the
    // `-defaultlib:libcmt` which is passed unconditionally with the `clang`
    // driver rather than the `clang-cl` driver.
    commandLine.appendFlag("-nostartfiles")

    // TODO(compnerd) investigate the proper way to port this logic over from
    // the C++ driver.

    // Since Windows has separate libraries per architecture, link against the
    // architecture specific version of the static library.
    commandLine.appendFlag(.L)
    commandLine.appendPath(VirtualPath.lookup(targetInfo.runtimeLibraryImportPaths.last!.path))

    // FIXME(compnerd) figure out how to ensure that the SDK relative path is
    // the last one
    commandLine.appendPath(VirtualPath.lookup(targetInfo.runtimeLibraryImportPaths.last!.path)
                              .appending(component: "swiftrt.obj"))

    commandLine.append(contentsOf: inputs.compactMap { (input: TypedVirtualPath) -> Job.ArgTemplate? in
      switch input.type {
      case .object, .llvmBitcode:
        return .path(input.file)
      default:
        return nil
      }
    })

    for framework in parsedOptions.arguments(for: .F, .Fsystem) {
      commandLine.appendFlag(framework.option == .Fsystem ? "-iframework" : "-F")
      try commandLine.appendPath(VirtualPath(path: framework.argument.asSingle))
    }

    if let sdkPath = targetInfo.sdkPath?.path {
      commandLine.appendFlag("-I")
      commandLine.appendPath(VirtualPath.lookup(sdkPath))
    }

    if let stdlib = parsedOptions.getLastArgument(.experimentalCxxStdlib) {
      commandLine.appendFlag("-stdlib=\(stdlib.asSingle)")
    }

    // FIXME(compnerd) render asan/ubsan runtime link for executables

    if parsedOptions.contains(.profileGenerate) {
      commandLine.appendFlag("-Xlinker")
      // FIXME(compnerd) wrap llvm::getInstrProfRuntimeHookVarName()
      commandLine.appendFlag("-include:__llvm_profile_runtime")
      commandLine.appendFlag("-lclang_rt.profile")
    }

    for option in parsedOptions.arguments(for: .Xlinker) {
      commandLine.appendFlag(.Xlinker)
      commandLine.appendFlag(option.argument.asSingle)
    }
    // TODO(compnerd) is there a separate equivalent to OPT_linker_option_group?
    try commandLine.appendAllArguments(.XclangLinker, from: &parsedOptions)

    if parsedOptions.contains(.v) {
      commandLine.appendFlag("-v")
    }

    commandLine.appendFlag("-o")
    commandLine.appendPath(outputFile)

    addLinkedLibArgs(to: &commandLine, parsedOptions: &parsedOptions)

    // TODO(compnerd) handle static libraries
    return try getToolPath(.clang)
  }
}
