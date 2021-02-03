//===------------------ Integrator.swift ----------------------------------===//
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

import TSCBasic

extension ModuleDependencyGraph {

  // MARK: Integrator - state & creation

  /// Integrates a \c SourceFileDependencyGraph into a \c ModuleDependencyGraph
  /*@_spi(Testing)*/ public struct Integrator {

    // Shorthands
    /*@_spi(Testing)*/ public typealias Graph = ModuleDependencyGraph

    /*@_spi(Testing)*/ public typealias Changes = Set<Node>

    /// the graph to be integrated
    let source: SourceFileDependencyGraph

    /// the source (file) of the graph to be integrated
    let dependencySource: DependencySource

    /// the graph to be integrated into
     let destination: ModuleDependencyGraph

    /// When done, changedNodes contains a set of nodes that changed as a result of this integration.

    var changedNodes = Changes()

    /// Starts with all nodes in dependencySource. Nodes that persist will be removed.
    /// After integration is complete, contains the nodes that have disappeared.
    var disappearedNodes = [DependencyKey: Graph.Node]()

    init(source: SourceFileDependencyGraph,
         dependencySource: DependencySource,
         destination: ModuleDependencyGraph)
    {
      self.source = source
      self.dependencySource = dependencySource
      self.destination = destination
      self.disappearedNodes = destination.nodeFinder.findNodes(for: dependencySource)
        ?? [:]
    }
  }
}

// MARK: - integrate a file containing dependency information
extension ModuleDependencyGraph.Integrator {
  /// returns nil for error
  static func integrate(
    dependencySource: Graph.DependencySource,
    into destination: Graph,
    input: TypedVirtualPath,
    reporter: IncrementalCompilationState.Reporter?,
    diagnosticEngine: DiagnosticsEngine,
    fileSystem: FileSystem
  ) -> Changes? {
    guard let sfdg = try? SourceFileDependencyGraph.read(
            from: dependencySource, on: fileSystem)
    else {
      reporter?.report("Could not read \(dependencySource)", path: input)
      return nil
    }
    return integrate(from: sfdg,
                     dependencySource: dependencySource,
                     into: destination)
  }
}
// MARK: - integrate a graph

extension ModuleDependencyGraph.Integrator {
  /// Integrate a SourceFileDepGraph into the receiver.
  /// Integration happens when the driver needs to read SourceFileDepGraph.
  /// Returns changed nodes
  /*@_spi(Testing)*/ public static func integrate(
    from g: SourceFileDependencyGraph,
    dependencySource: Graph.DependencySource,
    into destination: Graph
  ) ->  Changes {
    var integrator = Self(source: g,
                          dependencySource: dependencySource,
                          destination: destination)
    integrator.integrate()

    if destination.verifyDependencyGraphAfterEveryImport {
      integrator.verifyAfterImporting()
    }
    if destination.emitDependencyDotFileAfterEveryImport {
      destination.emitDotFile(g, dependencySource)
    }
    return integrator.changedNodes
  }

  private mutating func integrate() {
    integrateEachSourceNode()
    handleDisappearedNodes()
    destination.ensureGraphWillRetraceDependents(of: changedNodes)
  }
  private mutating func integrateEachSourceNode() {
    source.forEachNode { integrate(oneNode: $0) }
  }
  private mutating func handleDisappearedNodes() {
    for (_, node) in disappearedNodes {
      changedNodes.insert(node)
      destination.nodeFinder.remove(node)
    }
  }
}
// MARK: - integrate one node
extension ModuleDependencyGraph.Integrator {
  private mutating func integrate(
    oneNode integrand: SourceFileDependencyGraph.Node)
  {
    guard integrand.isProvides else {
      // depends are captured by recordWhatIsDependedUpon below
      return
    }

    let integratedNode = destination.nodeFinder.findNodes(for: integrand.key)
      .flatMap {
        integrateWithNodeHere(integrand, $0) ??
        integrateWithExpat(   integrand, $0)
      }
    ?? integrateWithNewNode(integrand)

    recordDefsForThisUse(integrand, integratedNode)
  }

  /// If there is already a node in the graph for this dependencySource, merge the integrand into that,
  /// and return the merged node. Remember that the merged node has changed if it has.
  private mutating func integrateWithNodeHere(
    _ integrand: SourceFileDependencyGraph.Node,
    _ nodesMatchingKey: [Graph.DependencySource?: Graph.Node]
  ) -> Graph.Node? {
    guard let matchHere = nodesMatchingKey[dependencySource] else {
      return nil
    }
    assert(matchHere.dependencySource == dependencySource)
    // Node was and still is. Do not remove it.
    disappearedNodes.removeValue(forKey: matchHere.dependencyKey)
    if matchHere.fingerprint != integrand.fingerprint {
      changedNodes.insert(matchHere)
    }
    return matchHere
  }

  /// If there is an expat node with this key, replace it with a ndoe for this dependencySource
  /// and return the replacement. Remember that the replace has changed.
  private mutating func integrateWithExpat(
    _ integrand: SourceFileDependencyGraph.Node,
    _ nodesMatchingKey: [Graph.DependencySource?: Graph.Node]
  ) -> Graph.Node? {
    guard let expat = nodesMatchingKey[nil] else {
      return nil
    }
    assert(nodesMatchingKey.count == 1,
           "If an expat exists, then must not be any matches in other files")
    let integratedNode = destination.nodeFinder
      .replace(expat,
               newDependencySource: dependencySource,
               newFingerprint: integrand.fingerprint)
    changedNodes.insert(integratedNode)
    return integratedNode
  }

  /// Integrate by creating a whole new node. Remember that it has changed.
  private mutating func integrateWithNewNode(
    _ integrand: SourceFileDependencyGraph.Node
  ) -> Graph.Node {
    precondition(integrand.isProvides, "Dependencies are arcs in the module graph")
    let newNode = Graph.Node(
      key: integrand.key,
      fingerprint: integrand.fingerprint,
      dependencySource: dependencySource)
    let oldNode = destination.nodeFinder.insert(newNode)
    assert(oldNode == nil, "Should be new!")
    changedNodes.insert(newNode)
    return newNode
  }

  /// Find the keys of nodes used by this node, and record the def-use links.
  /// Also see if any of those keys are external dependencies, and if such is a new dependency,
  /// record the external dependency, and record the node as changed.
  private mutating func recordDefsForThisUse(
    _ sourceFileUseNode: SourceFileDependencyGraph.Node,
    _ moduleUseNode: Graph.Node
  ) {
    source.forEachDefDependedUpon(by: sourceFileUseNode) { def in
      let isNewUse = destination.nodeFinder.record(def: def.key,
                                                   use: moduleUseNode)
      if let externalDependency = def.key.designator.externalDependency,
         isNewUse {
        destination.externalDependencies.insert(externalDependency)
        changedNodes.insert(moduleUseNode)
      }
    }
  }
}

// MARK: - verification
extension ModuleDependencyGraph.Integrator {
  @discardableResult
  func verifyAfterImporting() -> Bool {
    guard let nodesInFile = destination.nodeFinder.findNodes(for: dependencySource),
          !nodesInFile.isEmpty
    else {
      fatalError("Just imported \(dependencySource), should have nodes")
    }
    return destination.verifyGraph()
  }
}
