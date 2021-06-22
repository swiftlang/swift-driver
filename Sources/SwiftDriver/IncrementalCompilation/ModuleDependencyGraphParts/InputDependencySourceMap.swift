//===------------- InputDependencySourceMap.swift ---------------- --------===//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import TSCBasic

/// Maps input files (e.g. .swift) to and from the DependencySource object.
///
/// This map caches the same information as in the `OutputFileMap`, but it
/// optimizes the reverse lookup, and includes path interning via `DependencySource`.
@_spi(Testing) public struct InputDependencySourceMap: Equatable {
  /// Maps input files (e.g. .swift) to and from the DependencySource object.
  @_spi(Testing) public let reverseMapping: [DependencySource: TypedVirtualPath]

  /// A copy of the output file map that provides the forward mapping.
  @_spi(Testing) public let outputFileMap: OutputFileMap

  /// Based on entries in the `OutputFileMap`, create the bidirectional map to map each source file
  /// path to- and from- the corresponding swiftdeps file path.
  ///
  /// - Returns: the map, or nil if error
  init?(_ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup) {
    self.outputFileMap = info.outputFileMap
    let diagnosticEngine = info.diagnosticEngine

    assert(outputFileMap.onlySourceFilesHaveSwiftDeps())
    var hadError = false
    self.reverseMapping = info.inputFiles.reduce(into: [DependencySource: TypedVirtualPath]()) { backMap, input in
      guard input.type == .swift else { return }
      guard
        let dependencySource = info.outputFileMap.getDependencySource(for: input)
      else {
         // The legacy driver fails silently here.
         diagnosticEngine.emit(
           .remarkDisabled("\(input.file.basename) has no swiftDeps file")
         )
         hadError = true
         // Don't stop at the first problem.
         return
       }

       if let sameSourceForInput = backMap.updateValue(input, forKey: dependencySource) {
         diagnosticEngine.emit(
           .remarkDisabled(
             "\(dependencySource) and \(sameSourceForInput) have the same input file in the output file map: \(input)")
         )
         hadError = true
       }
     }

     if hadError {
       return nil
     }
   }
}

// MARK: - Accessing

extension InputDependencySourceMap {
  @_spi(Testing) public func source(for input: TypedVirtualPath) -> DependencySource? {
    self.outputFileMap.getDependencySource(for: input)
  }

  @_spi(Testing) public func input(for source: DependencySource) -> TypedVirtualPath? {
    self.reverseMapping[source]
  }
}

extension OutputFileMap {
  @_spi(Testing) public func getDependencySource(
    for sourceFile: TypedVirtualPath
  ) -> DependencySource? {
    assert(sourceFile.type == FileType.swift)
    guard let swiftDepsPath = existingOutput(inputFile: sourceFile.fileHandle,
                                             outputType: .swiftDeps)
    else {
      return nil
   }
    assert(VirtualPath.lookup(swiftDepsPath).extension == FileType.swiftDeps.rawValue)
    let typedSwiftDepsFile = TypedVirtualPath(file: swiftDepsPath, type: .swiftDeps)
    return DependencySource(typedSwiftDepsFile)
  }
}
