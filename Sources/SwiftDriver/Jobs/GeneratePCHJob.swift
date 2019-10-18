//===--------------- GeneratePCHJob.swift - Swift Autolink Extract ----===//
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
        
        if let outputDirectory = parsedOptions.getLastArgument(.pchOutputDir)?.asSingle {
            outputs.append(.init(file: try VirtualPath(path: outputDirectory), type: .pch))
            try commandLine.appendLast(.pchOutputDir, from: &parsedOptions)
        }
        
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
