//===--------------- ModuleDependencyScanning.swift -----------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import TSCBasic

extension Driver {
  // TODO: Instead of directly invoking the frontend,
  // treat this as any other `Job`.
  /// Precompute the dependencies for a given Swift compilation, producing a
  /// complete dependency graph including all Swift and C module files and
  /// source files.
  mutating func computeModuleDependencyGraph() throws -> InterModuleDependencyGraph? {
    // Grab the swift compiler
    let resolver = try ArgsResolver()
    let compilerPath = VirtualPath.absolute(try toolchain.getToolPath(.swiftCompiler))
    let tool = try resolver.resolve(.path(compilerPath))
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    if parsedOptions.hasArgument(.parseStdlib) {
       commandLine.appendFlag(.disableObjcAttrRequiresFoundationModule)
    }
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)
    // FIXME: MSVC runtime flags

    // Pass on the input files
    commandLine.append(contentsOf: inputFiles.map { .path($0.file)})

    // Execute dependency scanner and decode its output
    let arguments = [tool] + (try commandLine.map { try resolver.resolve($0) })
    let scanProcess = try Process.launchProcess(arguments: arguments, env: env)
    let result = try scanProcess.waitUntilExit()
    // Error on dependency scanning failure
    if (result.exitStatus != .terminated(code: 0)) {
      var returnCode = 0
      switch result.exitStatus {
        case .terminated(let code):
          returnCode = Int(code)
        case .signalled(let signal):
          returnCode = Int(signal)
      }
      throw Error.dependencyScanningFailure(returnCode, try result.utf8stderrOutput())
    }
    guard let outputData = try? Data(result.utf8Output().utf8) else {
      return nil
    }
    return try JSONDecoder().decode(InterModuleDependencyGraph.self, from: outputData)
  }
}
