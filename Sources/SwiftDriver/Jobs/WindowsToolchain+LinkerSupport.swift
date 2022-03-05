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

private func architecture(for triple: Triple) -> String {
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
    // Special case static linking as clang cannot drive the operation.
    if linkerOutputType == .staticLibrary {
      let librarian: String
      switch parsedOptions.getLastArgument(.useLd)?.asSingle {
      case .none:
        librarian = lto == nil ? "link.exe" : "lld-link.exe"
      case .some("lld"), .some("lld.exe"), .some("lld-link"), .some("lld-link.exe"):
        librarian = "lld-link.exe"
      case let .some(linker):
        librarian = linker
      }

      commandLine.appendFlag("/LIB")
      commandLine.appendFlag("/NOLOGO")
      commandLine.appendFlag("/OUT:\(outputFile.name.spm_shellEscaped())")

      let types: [FileType] = lto == nil ? [.object] : [.object, .llvmBitcode]
      commandLine.append(contentsOf: inputs.lazy.filter { types.contains($0.type) }
                                                .map { .path($0.file) })

      return try lookup(executable: librarian)
    }

    var clang = try parsedOptions.hasArgument(.enableExperimentalCxxInterop)
                    ? getToolPath(.clangxx)
                    : getToolPath(.clang)

    let targetTriple = targetInfo.target.triple
    if !targetTriple.triple.isEmpty {
      commandLine.appendFlag("-target")
      commandLine.appendFlag(targetTriple.triple)
    }

    switch linkerOutputType {
    case .staticLibrary:
      fatalError(".staticLibrary should not be reached")
    case .dynamicLibrary:
      commandLine.appendFlag("-shared")
    case .executable:
      break
    }

    if let arg = parsedOptions.getLastArgument(.toolsDirectory) {
      let path = try AbsolutePath(validating: arg.asSingle)

      if let tool = lookupExecutablePath(filename: executableName("clang"),
                                         searchPaths: [path]) {
        clang = tool
      }

      commandLine.appendFlag("-B")
      commandLine.appendPath(path)
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

    // Locate the Swift registration helper by honouring any explicit
    // `-resource-dir`, `-sdk`, or the `SDKROOT` environment variable, and
    // finally falling back to the target information.
    let rsrc: VirtualPath
    if let resourceDir = parsedOptions.getLastArgument(.resourceDir) {
      rsrc = try VirtualPath(path: resourceDir.asSingle)
    } else if let sdk = parsedOptions.getLastArgument(.sdk)?.asSingle ?? env["SDKROOT"], !sdk.isEmpty {
      rsrc = try VirtualPath(path: AbsolutePath(validating: sdk)
                                      .appending(components: "usr", "lib", "swift",
                                                 targetTriple.platformName() ?? "",
                                                 architecture(for: targetTriple))
                                      .pathString)
    } else {
      rsrc = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
    }
    commandLine.appendPath(rsrc.appending(component: "swiftrt.obj"))

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

    try commandLine.appendAllExcept(includeList: [.linkerOption],
                                    excludeList: [.l],
                                    from: &parsedOptions)

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
    return clang
  }
}
