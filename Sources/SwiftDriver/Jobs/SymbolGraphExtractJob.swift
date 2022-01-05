//===---------- SymbolGraphExtractJob.swift - Symbol Graph Emission Job ---===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftOptions

extension Driver {
    mutating func symbolGraphExtractJob(inputs: [TypedVirtualPath]) throws -> Job? {
        guard parsedOptions.contains(.emitSymbolGraph) else { return nil }

        guard let outputDir = parsedOptions.getLastArgument(.emitSymbolGraphDir) else {
            return nil
        }

        let outputPath = try VirtualPath(path: outputDir.asSingle).appending(component: "\(moduleOutputInfo.name).symbols.json")
        let outputs: [TypedVirtualPath] = [.init(file: outputPath.intern(), type: .symbolGraphJson)]

        var commandLine = [Job.ArgTemplate]()

        commandLine += [.flag(Option.outputDir.spelling), .flag(outputDir.asSingle)]
        commandLine += [.flag(Option.target.spelling), .flag(targetTriple.triple)]
        commandLine += [.flag(Option.moduleName.spelling), .flag(moduleOutputInfo.name)]

        try commandLine.appendAll(.Xcc, .F, .Fsystem, .I, .L, .v,
                                  .swiftVersion, .sdk, .moduleCachePath,
                                  .includeSpiSymbols, .skipInheritedDocs, from: &parsedOptions)

        if let accessLevel = parsedOptions.getLastArgument(.symbolGraphMinimumAccessLevel) {
            commandLine += [.flag(Option.minimumAccessLevel.spelling), .flag(accessLevel.asSingle)]
        }

        return Job(
          moduleName: moduleOutputInfo.name,
          kind: .symbolGraphExtract,
          tool: .absolute(try toolchain.getToolPath(.swiftSymbolGraphExtract)),
          commandLine: commandLine,
          inputs: inputs,
          primaryInputs: [],
          outputs: outputs,
          supportsResponseFiles: true
        )
    }
}
