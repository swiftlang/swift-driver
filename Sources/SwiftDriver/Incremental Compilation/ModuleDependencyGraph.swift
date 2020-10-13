//===------- ModuleDependencyGraph.swift ----------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import TSCBasic
import SwiftOptions


// MARK: - ModuleDependencyGraph

@_spi(Testing) public final class ModuleDependencyGraph {
  
  internal var nodeFinder = NodeFinder()
  
  /// When integrating a change, want to find untraced nodes so we can kick off jobs that have not been
  /// kicked off yet
  private var tracedNodes = Set<Node>()
  
  @_spi(Testing) public var sourceSwiftDepsMap = BidirectionalMap<TypedVirtualPath, SwiftDeps>()

  // Supports requests from the driver to getExternalDependencies.
  @_spi(Testing) public internal(set) var externalDependencies = Set<ExternalDependency>()
  
  let verifyDependencyGraphAfterEveryImport: Bool
  let emitDependencyDotFileAfterEveryImport: Bool
  let traceDependencies: Bool
  
  @_spi(Testing) public let diagnosticEngine: DiagnosticsEngine
  
  public init(
    diagnosticEngine: DiagnosticsEngine,
    traceDependencies: Bool,
    emitDependencyDotFileAfterEveryImport: Bool,
    verifyDependencyGraphAfterEveryImport: Bool)
  {
    self.verifyDependencyGraphAfterEveryImport = verifyDependencyGraphAfterEveryImport
    self.emitDependencyDotFileAfterEveryImport = emitDependencyDotFileAfterEveryImport
    self.traceDependencies = traceDependencies
    self.diagnosticEngine = diagnosticEngine
  }
}
// MARK: - initial build only
extension ModuleDependencyGraph {
  static func buildInitialGraph<Inputs: Sequence>(
    diagnosticEngine: DiagnosticsEngine,
    inputs: Inputs,
    outputFileMap: OutputFileMap?,
    parsedOptions: inout ParsedOptions,
    remarkDisabled: (String) -> Diagnostic.Message,
    traceDependencies: Bool
  ) -> Self?
  where Inputs.Element == TypedVirtualPath
  {
    let emitOpt = Option.driverEmitFineGrainedDependencyDotFileAfterEveryImport
    let veriOpt = Option.driverVerifyFineGrainedDependencyGraphAfterEveryImport
    let r = Self (
      diagnosticEngine: diagnosticEngine,
      traceDependencies: traceDependencies,
      emitDependencyDotFileAfterEveryImport: parsedOptions.contains(emitOpt),
      verifyDependencyGraphAfterEveryImport: parsedOptions.contains(veriOpt))
    for input in inputs {
      guard let swiftDepsFile = outputFileMap?.existingOutput(
              inputFile: input.file,
              outputType: .swiftDeps)
      else {
        diagnosticEngine.emit(
          remarkDisabled("\(input.file.basename) has no swiftDeps file")
        )
        return nil
      }
      let swiftDeps = SwiftDeps(swiftDepsFile)
      r.sourceSwiftDepsMap[input] = swiftDeps
      _ = Integrator.integrate(swiftDeps: swiftDeps,
                               into: r,
                               diagnosticEngine: diagnosticEngine)
    }
    return r
  }
}
// MARK: - Scheduling the first wave
extension ModuleDependencyGraph {
  /// Find all the sources that depend on `sourceFile`. For some source files, these will be
  /// speculatively scheduled in the first wave.
  @_spi(Testing) public func findDependentSourceFiles(
    of sourceFile: TypedVirtualPath,
    _ reportIncrementalDecision: (String) -> Void
  ) -> [TypedVirtualPath] {
    var allSwiftDepsToRecompile = Set<SwiftDeps>()

    let swiftDeps = sourceSwiftDepsMap[sourceFile]

    for swiftDepsToRecompile in
      findSwiftDepsToRecompileWhenWholeSwiftDepsChanges( swiftDeps ) {
      if swiftDepsToRecompile != swiftDeps {
        allSwiftDepsToRecompile.insert(swiftDepsToRecompile)
      }
    }
    return allSwiftDepsToRecompile.map {
     let dependentSource = sourceSwiftDepsMap[$0]
      reportIncrementalDecision(
        "Found dependent of \(sourceFile.file.basename): \(dependentSource.file.basename)")
      return dependentSource
    }
  }

  /// Find all the swiftDeps files that depend on `swiftDeps`.
  /// Really private, except for testing.
  @_spi(Testing) public func findSwiftDepsToRecompileWhenWholeSwiftDepsChanges(
    _ swiftDeps: SwiftDeps
  ) -> Set<SwiftDeps> {
    let nodes = nodeFinder.findNodes(for: swiftDeps) ?? [:]
    /// Tests expect this to be reflexive
    return findSwiftDepsToRecompileWhenNodesChange(nodes.values)
  }
}
// MARK: - Scheduling the 2nd wave
extension ModuleDependencyGraph {
  /// After `source` has been compiled, figure out what other source files need compiling.
  /// Used to schedule the 2nd wave.
  /// Return nil in case of an error.
  @_spi(Testing) public func findSourcesToCompileAfterCompiling(
    _ source: TypedVirtualPath
  ) -> [TypedVirtualPath]? {
    findSourcesToCompileAfterIntegrating( sourceSwiftDepsMap[source] )
  }

  /// After a compile job has finished, read its swiftDeps file and return the source files needing
  /// recompilation.
  /// Return nil in case of an error.
  private func findSourcesToCompileAfterIntegrating(
    _ swiftDeps: SwiftDeps
  ) -> [TypedVirtualPath]? {
    Integrator.integrate(swiftDeps: swiftDeps,
                         into: self,
                         diagnosticEngine: diagnosticEngine)
      .map {
        findSwiftDepsToRecompileWhenNodesChange($0)
          .subtracting([swiftDeps])
          .map {sourceSwiftDepsMap[$0]}
      }
  }
}

// MARK: - Scheduling either wave
extension ModuleDependencyGraph {
  /// Find all the swiftDeps affected when the nodes change.
  @_spi(Testing) public func findSwiftDepsToRecompileWhenNodesChange<Nodes: Sequence>(
    _ nodes: Nodes
  ) -> Set<SwiftDeps>
  where Nodes.Element == Node
  {
    let affectedNodes = Tracer.findPreviouslyUntracedUsesOf(defs: nodes, in: self)
      .tracedUses
    return Set(affectedNodes.compactMap {$0.swiftDeps})
  }

  @_spi(Testing) public  func forEachUntracedSwiftDepsDirectlyDependent(
    on externalSwiftDeps: ExternalDependency,
    _ fn: (SwiftDeps) -> Void
  ) {
    // These nodes will depend on the *interface* of the external Decl.
    let key = DependencyKey(interfaceFor: externalSwiftDeps)
    nodeFinder.forEachUse(of: key) { use, useSwiftDeps in
      if isUntraced(use) {
        fn(useSwiftDeps)
      }
    }
  }
}
fileprivate extension DependencyKey {
  init(interfaceFor dep: ExternalDependency ) {
    self.init(aspect: .interface, designator: .externalDepend(dep))
  }
}
// MARK: - tracking traced nodes
extension ModuleDependencyGraph {

  func isUntraced(_ n: Node) -> Bool {
    !isTraced(n)
  }
  func isTraced(_ n: Node) -> Bool {
    tracedNodes.contains(n)
  }
  func amTracing(_ n: Node) {
    tracedNodes.insert(n)
  }
  func ensureGraphWillRetraceDependents<Nodes: Sequence>(of nodes: Nodes)
  where Nodes.Element == Node
  {
    nodes.forEach { tracedNodes.remove($0) }
  }
}

// MARK: - utilities for unit testing
extension ModuleDependencyGraph {
  /// Testing only
  @_spi(Testing) public func haveAnyNodesBeenTraversed(inMock i: Int) -> Bool {
    let swiftDeps = SwiftDeps(mock: i)
    // optimization
    if let fileNode = nodeFinder.findFileInterfaceNode(forMock: swiftDeps),
       isTraced(fileNode) {
      return true
    }
    if let nodes = nodeFinder.findNodes(for: swiftDeps)?.values,
       nodes.contains(where: isTraced) {
      return true
    }
    return false
  }
}
// MARK: - verification
extension ModuleDependencyGraph {
  @discardableResult
  func verifyGraph() -> Bool {
    nodeFinder.verify()
  }
}
// MARK: - debugging
extension ModuleDependencyGraph {
  func emitDotFile(_ g: SourceFileDependencyGraph, _ swiftDeps: SwiftDeps) {
    // TODO: Incremental emitDotFIle
    fatalError("unimplmemented, writing dot file of dependency graph")
  }
}
