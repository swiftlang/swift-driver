//===--------------- EmitModuleJob.swift - Swift Module Emission Job ------===//
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
extension Driver {
  /// Add options that are common to command lines that emit modules, e.g.,
  /// options for the paths of various module files.
  mutating func addCommonModuleOptions(
      commandLine: inout [Job.ArgTemplate],
      outputs: inout [TypedVirtualPath]
  ) throws {
    // Add supplemental outputs.
    func addSupplementalOutput(path: VirtualPath?, flag: String, type: FileType) {
      guard let path = path else { return }

      commandLine.appendFlag(flag)
      commandLine.appendPath(path)
      outputs.append(.init(file: path, type: type))
    }

    addSupplementalOutput(path: moduleDocOutputPath, flag: "-emit-module-doc-path", type: .swiftDocumentation)
    addSupplementalOutput(path: moduleSourceInfoPath, flag: "-emit-module-source-info-path", type: .swiftSourceInfoFile)
    addSupplementalOutput(path: swiftInterfacePath, flag: "-emit-module-interface-path", type: .swiftInterface)
    addSupplementalOutput(path: serializedDiagnosticsFilePath, flag: "-serialize-diagnostics-path", type: .diagnostics)
    addSupplementalOutput(path: objcGeneratedHeaderPath, flag: "-emit-objc-header-path", type: .objcHeader)
    addSupplementalOutput(path: tbdPath, flag: "-emit-tbd-path", type: .tbd)

    if let dependenciesFilePath = dependenciesFilePath {
      var path = dependenciesFilePath
      // FIXME: Hack to workaround the fact that SwiftPM/Xcode don't pass this path right now.
      if parsedOptions.getLastArgument(.emitDependenciesPath) == nil {
        path = try moduleOutputInfo.output!.outputPath.replacingExtension(with: .dependencies)
      }
      addSupplementalOutput(path: path, flag: "-emit-dependencies-path", type: .dependencies)
    }
  }

  /// Form a job that emits a single module
  mutating func emitModuleJob() throws -> Job {
    let moduleOutputPath = moduleOutputInfo.output!.outputPath
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: moduleOutputPath, type: .swiftModule)
    ]

    commandLine.appendFlags("-frontend", "-emit-module")

    let swiftInputFiles = inputFiles.filter { $0.type.isPartOfSwiftCompilation }

    // Add the inputs.
    for input in swiftInputFiles {
      commandLine.append(.path(input.file))
      inputs.append(input)
    }

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs)
    // FIXME: Add MSVC runtime library flags

    try addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs)

    commandLine.appendFlag(.o)
    commandLine.appendPath(moduleOutputPath)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .emitModule,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: outputs
    )
  }

  /// Returns true if the emit module job should be created.
  var shouldCreateEmitModuleJob: Bool {
    return forceEmitModuleInSingleInvocation
      && compilerOutputType != .swiftModule
      && moduleOutputInfo.output != nil
  }
}
