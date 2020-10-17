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

// On ELF/WASM platforms there's no built in autolinking mechanism, so we
// pull the info we need from the .o files directly and pass them as an
// argument input file to the linker.
// FIXME: Also handle Cygwin and MinGW
extension Driver {
  @_spi(Testing) public var isAutolinkExtractJobNeeded: Bool {
    [.elf, .wasm].contains(targetTriple.objectFormat) && lto == nil
  }

  mutating func autolinkExtractJob(inputs: [TypedVirtualPath]) throws -> Job? {
    guard inputs.count > 0 && isAutolinkExtractJobNeeded else {
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
      primaryInputs: [],
      outputs: [.init(file: output, type: .autolink)],
      supportsResponseFiles: true
    )
  }
}
