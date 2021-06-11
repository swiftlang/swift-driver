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

@_spi(Testing) public struct InputDependencySourceMap: Equatable {
  
  /// Maps input files (e.g. .swift) to and from the DependencySource object.
  ///
  // This map caches the same information as in the `OutputFileMap`, but it
  // optimizes the reverse lookup, and includes path interning via `DependencySource`.
  // Once created, it does not change.
  
  public typealias BiMap = BidirectionalMap<TypedVirtualPath, DependencySource>
  @_spi(Testing) public let biMap: BiMap

  private let simulateGetInputFailure: Bool

  /// Based on entries in the `OutputFileMap`, create the bidirectional map to map each source file
  /// path to- and from- the corresponding swiftdeps file path.
  ///
  /// - Returns: the map, or nil if error
  init?(_ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup) {
    self.simulateGetInputFailure = info.simulateGetInputFailure

    let outputFileMap = info.outputFileMap
    let diagnosticEngine = info.diagnosticEngine

    assert(outputFileMap.onlySourceFilesHaveSwiftDeps())
    var hadError = false
    self.biMap = info.inputFiles.reduce(into: BiMap()) { biMap, input in
      guard input.type == .swift else {return}
      guard let dependencySource = outputFileMap.getDependencySource(for: input)
       else {
         // The legacy driver fails silently here.
         diagnosticEngine.emit(
           .remarkDisabled("\(input.file.basename) has no swiftDeps file")
         )
         hadError = true
         // Don't stop at the first problem.
         return
       }
       if let sameSourceForInput = biMap.updateValue(dependencySource, forKey: input) {
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
  @_spi(Testing) public func sourceIfKnown(for input: TypedVirtualPath) -> DependencySource? {
    biMap[input]
  }

  @_spi(Testing) public func inputIfKnown(for source: DependencySource) -> TypedVirtualPath? {
    simulateGetInputFailure ? nil : biMap[source]
  }

  @_spi(Testing) public func enumerateToSerializePriors(
    _ eachFn: (TypedVirtualPath, DependencySource) -> Void
  ) {
    biMap.forEach(eachFn)
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
