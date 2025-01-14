//===--------------- PhasedModule.swift - Swift Testing -----------------===//
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
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities
import XCTest

/// Represents a module to be compiled.
/// Thus, stores everything needed to invoke the compiler, and how to invoke the compiler.
public struct Module {
  /// Does this module produce an executable applications or a library?
  public enum Product {
    case executable, library
  }
  /// The name, used for files and imports.
  /// Two modules may have the same  name. You might do this to test a situation where the user adds
  /// a file to a module. Both would  have the same name, but different sources.  One `Step` would compile
  /// one module, and the next would compile the module with the additional  `Source`.
  public let name: String

  /// The `Source`s to be compiled when building this module.
  public let sources: [Source]

  /// The `Module`s imported by this module.
  let imports: [Module]

  /// What kind of thing this module produces.
  let product: Product

  /// A handy internal cache.
  /// E.g. "foo.swift: <source named: "foo">
  private let sourceMap: [String: Source]

  /// Create a `Module`
  /// - Parameters:
  ///   - named: The name to be used for directories, and imports.
  ///   - containing: The sources to be compiled.
  ///   - importing: The modules this one imports
  ///   - producing: The kind of thing produced.
  /// - Returns: A new `Module`
  public init(named name: String,
              containing sources: [Source],
              importing imports: [Module] = [],
              producing product: Product) {
    self.name = name
    self.sources = sources
    self.imports = imports
    self.product = product
    self.sourceMap = sources.spm_createDictionary { source in (source.name + ".swift", source)}
  }

  /// Compile this module
  /// - Parameters:
  ///   - addOns: The additional code to send to the compiler.
  ///   - in: The context
  /// - Returns: The `Source`s actually compiled.
  func compile(addOns: [AddOn], in context: Context) throws -> [Source] {
    if context.verbose {
      print("\n*** compiling \(name) ***")
    }
    try createFiles(adding: addOns, in: context)
    let compiledBasenames = try invokeDriver(in: context)
    return try sources(for: compiledBasenames)
  }
}
// MARK: - creating files
extension Module {

  private func createFiles(adding addOns: [AddOn], in context: Context) throws {
    try createOrRemoveSources(adding: addOns, in: context)
    try createDerivedDataDirIfMissing(in: context)
    createOutputFileMap(in: context)
  }
  /// Since the source directory may have been previously populated by a module with the same name but
  /// different `sources`, old ones must be removed, new ones added, and changed ones changes.
  private func createOrRemoveSources(adding addOns: [AddOn], in context: Context) throws {
    let dir = context.sourceRoot(for: self)
    func createSourceDir() throws {
      if !localFileSystem.exists(dir) {
        try localFileSystem.createDirectory(dir, recursive: true)
      }
    }
    func removeUnwantedSources() throws {
      for existingBasename in try localFileSystem.getDirectoryContents(dir)
      where existingBasename.hasSuffix(".swift") && sourceMap[existingBasename] == nil {
        try localFileSystem.removeFileTree(dir.appending(component: existingBasename))
      }
    }
    func addNeededSources() throws {
      for source in sources {
        let contentsWithAdditions = addOns.adjust(source.contents)
        try localFileSystem.writeIfChanged(path: context.swiftFilePath(for: source, in: self),
                                           bytes: ByteString(encodingAsUTF8: contentsWithAdditions))
      }
    }
    try createSourceDir()
    try removeUnwantedSources()
    Thread.sleep(forTimeInterval: 1)
    try addNeededSources()
  }

  private func createDerivedDataDirIfMissing(in context: Context) throws {
    let dir = context.buildRoot(for: self)
    if !localFileSystem.exists(dir) {
      try localFileSystem.createDirectory(dir, recursive: true)
    }
  }

  private func createOutputFileMap(in context: Context) {
    OutputFileMapCreator.write(
      module: name,
      inputPaths: sources.map {context.swiftFilePath(for: $0, in: self)},
      derivedData: context.buildRoot(for: self),
      to: context.outputFileMapPath(for: self))
  }
}

// MARK: - invoking the driver
extension Module {
  /// Invoke the driver to perform the compilation.
  /// - Returns: the basenames of recompiled source files.
  private func invokeDriver(in context: Context) throws -> [String] {
    var collector = CompiledSourceCollector()
    let handlers = [
      {collector.handle(diagnostic: $0)},
      context.verbose ? Driver.stderrDiagnosticsHandler : nil
    ].compactMap { $0 }
    let diagnosticsEngine = DiagnosticsEngine(handlers: handlers)

    let args = try arguments(in: context)
    var driver = try Driver(args: args, diagnosticsEngine: diagnosticsEngine)
    let jobs = try driver.planBuild()
    try driver.run(jobs: jobs)

    return collector.compiledBasenames
  }

  /// - Returns the arguments to pass to the `Driver`.
  private func arguments(in context: Context) throws -> [String] {
    let boilerPlateArgs = [
      "swiftc",
      "-no-color-diagnostics",
      "-incremental",
      "-driver-show-incremental",
      "-driver-show-job-lifecycle"]

    var searchPaths: [String] {
      let swiftModules = self.imports.map {
        context.swiftmodulePath(for: $0).parentDirectory.pathString
      }
      return swiftModules.flatMap { ["-I", $0, "-F", $0] }
        + ["-o", context.executablePath(for: self).pathString]
    }

    var libraryArgs: [String] {
      [
        "-c",
        "-parse-as-library",
        "-emit-module-path", context.swiftmodulePath(for: self).pathString,
      ] + searchPaths
    }

    var importedObjs: [String] {
      self.imports.flatMap { `import` in
        `import`.sources.map { source in
          context.objectFilePath(for: source, in: `import`).pathString
        }
      } .flatMap { ["-Xlinker", $0] }
    }

    let sdkArguments = try? Driver.sdkArgumentsForTesting()

    let interestingArgs = [
      ["-module-name", self.name],
      ["-output-file-map", context.outputFileMapPath(for: self).pathString],
      self.product == .library ? libraryArgs : searchPaths,
      sources.map { context.swiftFilePath(for: $0, in: self).pathString },
      importedObjs,
      sdkArguments ?? [],
    ].joined()

    if context.verbose {
      let withoutRootDir = interestingArgs
        .map {$0.replacingOccurrences(of: context.rootDir.pathString, with: "<rootDir>")}
      print("abridged arguments: ", withoutRootDir.joined(separator: " "), "\n")
    }

    return boilerPlateArgs + interestingArgs
  }

  func run(step: Step, in context: Context) throws -> ProcessResult? {
    let proc = Process(arguments: [context.executablePath(for: self).pathString])
    try proc.launch()
    return try proc.waitUntilExit()
  }
}
// MARK: - Reporting
extension Module {
  enum Errors: LocalizedError {
    case unexpectedCompilation(Module, String)

    var errorDescription: String? {
      switch self {
      case let .unexpectedCompilation(module, basename):
        return "\(module.name) compiled non-member \(basename).swift"
      }
    }
  }

  /// Translate source file base names to `Source` objects.
  func sources(for basenames: [String]) throws -> [Source] {
    try basenames.map { basename in
      guard let source = sourceMap[basename] else {
        throw Errors.unexpectedCompilation(self, basename)
      }
      return source
    }
  }
}

public extension Array where Element == Module {
  var allSources: [Source] {
    Set(flatMap {$0.sources}).sorted()
  }
  var allSourcesToCompile: ExpectedCompilations {
    ExpectedCompilations(allSourcesOf: self)
  }
}
