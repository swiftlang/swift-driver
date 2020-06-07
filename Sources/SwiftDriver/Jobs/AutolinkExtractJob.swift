//===--------------- AutolinkExtractJob.swift - Swift Autolink Extract ----===//
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

extension Driver {
  mutating func autolinkExtractJob(inputs: [TypedVirtualPath]) throws -> Job? {
    // On ELF platforms there's no built in autolinking mechanism, so we
    // pull the info we need from the .o files directly and pass them as an
    // argument input file to the linker.
    // FIXME: Also handle Cygwin and MinGW
    guard inputs.count > 0 && targetTriple.objectFormat == .elf else {
      return nil
    }

    var commandLine = [Job.ArgTemplate]()
    let output = VirtualPath.temporary(RelativePath("\(moduleOutputInfo.name).autolink"))

    commandLine.append(contentsOf: inputs.map { .path($0.file) })
    commandLine.appendFlag(.o)
    commandLine.appendPath(output)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .autolinkExtract,
      tool: .absolute(try toolchain.getToolPath(.swiftAutolinkExtract)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: [.init(file: output, type: .autolink)],
      supportsResponseFiles: true
    )
  }
}
