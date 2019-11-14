//===--------------- GeneratePCHJob.swift - Generate PCH Job ----===//
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

import Foundation
import TSCBasic
import TSCUtility

extension Driver {
  mutating func generatePCHJob(input: TypedVirtualPath) throws -> Job {
    var inputs = [TypedVirtualPath]()
    var outputs = [TypedVirtualPath]()
    
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    
    inputs.append(input)
    commandLine.appendPath(input.file)
    commandLine.appendFlag(.emitPch)
    
    try addCommonFrontendOptions(commandLine: &commandLine)

    if let importedObjCHeader = importedObjCHeader {
      commandLine.appendFlag(.importObjcHeader)
      commandLine.appendPath(importedObjCHeader)
    }
    
    try commandLine.appendLast(.indexStorePath, from: &parsedOptions)
    
    if parsedOptions.hasArgument(.serializeDiagnostics), let outputDirectory = parsedOptions.getLastArgument(.pchOutputDir)?.asSingle {
      commandLine.appendFlag(.serializeDiagnosticsPath)
      let path: VirtualPath
      if let modulePath = parsedOptions.getLastArgument(.emitModulePath) {
        var outputBase = (outputDirectory as NSString).appendingPathComponent(input.file.basenameWithoutExt)
        outputBase.append("-")
        // TODO: does this hash need to be persistent?
        let code = UInt(bitPattern: modulePath.asSingle.hashValue)
        outputBase.append(String(code, radix: 36))
        path = try VirtualPath(path: outputBase.appendingFileTypeExtension(.diagnostics))
      } else {
        // FIXME: should have '-.*' at the end of the filename, similar to llvm::sys::fs::createTemporaryFile
        path = .temporary(RelativePath(input.file.basenameWithoutExt.appendingFileTypeExtension(.diagnostics)))
      }
      commandLine.appendPath(path)
      outputs.append(.init(file: path, type: .diagnostics))
    }
    
    // FIXME: should have '-.*' at the end of the filename, similar to llvm::sys::fs::createTemporaryFile
    let pchFileName = input.file.basenameWithoutExt.appendingFileTypeExtension(.pch)
    let output: VirtualPath
    if let outputDirectory = parsedOptions.getLastArgument(.pchOutputDir)?.asSingle {
      let outputPath = (outputDirectory as NSString).appendingPathComponent(pchFileName)
      output = try VirtualPath(path: outputPath)
      try commandLine.appendLast(.pchOutputDir, from: &parsedOptions)
    } else {
      output = .temporary(RelativePath(pchFileName))
      commandLine.appendFlag(.o)
      commandLine.appendPath(output)
    }
    outputs.append(.init(file: output, type: .pch))
    bridgingPrecompiledHeader = output
    
    return Job(
      kind: .generatePCH,
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      outputs: outputs
    )
  }
}
