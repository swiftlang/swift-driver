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
import Foundation

extension ModuleDependencyGraph {

  // MARK: Integrator - state & creation

  /// Integrates a \c SourceFileDependencyGraph into a \c ModuleDependencyGraph
  /*@_spi(Testing)*/ public struct Integrator {

    // Shorthands
    /*@_spi(Testing)*/ public typealias Graph = ModuleDependencyGraph

    public private(set) var invalidatedNodes = DirectlyInvalidatedNodeSet()

    /// the graph to be integrated
    let sourceGraph: SourceFileDependencyGraph

    /// the graph to be integrated into
    let destination: ModuleDependencyGraph

    /// Starts with all nodes in dependencySource. Nodes that persist will be removed.
    /// After integration is complete, contains the nodes that have disappeared.
    var disappearedNodes = [DependencyKey: Graph.Node]()

    init(sourceGraph: SourceFileDependencyGraph,
         destination: ModuleDependencyGraph)
    {
      self.sourceGraph = sourceGraph
      self.destination = destination
      self.disappearedNodes = destination.nodeFinder
        .findNodes(for: sourceGraph.dependencySource)
        ?? [:]
    }
    
    var reporter: IncrementalCompilationState.Reporter? {
      destination.info.reporter
    }

    var sourceType: FileType {
      sourceGraph.dependencySource.typedFile.type
    }

    var isUpdating: Bool {
      destination.phase.isUpdating
    }
  }
}
// MARK: - integrate a graph
extension ModuleDependencyGraph.Integrator {
  /// Integrate a SourceFileDepGraph into the receiver.
  /// Integration happens when the driver needs to read SourceFileDepGraph.
  /// Returns all invalidated nodes and nodes only invalidated by externals.
  /// Should remove disappeared nodes
  /// Common to scheduling both waves.
  /*@_spi(Testing)*/ public static func integrate(
    from g: SourceFileDependencyGraph,
    into destination: Graph
  ) -> DirectlyInvalidatedNodeSet {
    var integrator = Self(sourceGraph: g, destination: destination)
    integrator.integrate()

    if destination.info.verifyDependencyGraphAfterEveryImport {
      integrator.verifyAfterImporting()
    }
    destination.dotFileWriter?.write(g)
    destination.dotFileWriter?.write(destination)
    return integrator.invalidatedNodes
  }

  private mutating func integrate() {
    integrateEachSourceNode()
    handleDisappearedNodes()
    // Ensure transitive closure will get started.
    destination.ensureGraphWillRetrace(invalidatedNodes)
  }
  private mutating func integrateEachSourceNode() {
    sourceGraph.forEachNode { integrate(oneNode: $0) }
  }
  private mutating func handleDisappearedNodes() {
    for (_, node) in disappearedNodes {
      addDisappeared(node)
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
    _ nodesMatchingKey: [DependencySource?: Graph.Node]
  ) -> Graph.Node? {
    guard let matchHere = nodesMatchingKey[sourceGraph.dependencySource] else {
      return nil
    }
    assert(matchHere.dependencySource == sourceGraph.dependencySource)
    // Node was and still is. Do not remove it.
    disappearedNodes.removeValue(forKey: matchHere.key)
    if matchHere.fingerprint != integrand.fingerprint {
      matchHere.setFingerprint(integrand.fingerprint)
      addChanged(matchHere)
      reporter?.report("Fingerprint changed for \(matchHere)")
    }
    return matchHere
  }

  /// If there is an expat node with this key, replace it with a node for this dependencySource
  /// and return the replacement. Remember that the replace has changed.
  private mutating func integrateWithExpat(
    _ integrand: SourceFileDependencyGraph.Node,
    _ nodesMatchingKey: [DependencySource?: Graph.Node]
  ) -> Graph.Node? {
    guard let expat = nodesMatchingKey[nil] else {
      return nil
    }
    assert(nodesMatchingKey.count == 1,
           "If an expat exists, then must not be any matches in other files")
    let integratedNode = destination.nodeFinder
      .replace(expat,
               newDependencySource: sourceGraph.dependencySource,
               newFingerprint: integrand.fingerprint)
    addPatriated(integratedNode)
    return integratedNode
  }

  /// Integrate by creating a whole new node. Remember that it has changed.
  private mutating func integrateWithNewNode(
    _ integrand: SourceFileDependencyGraph.Node
  ) -> Graph.Node {
    precondition(integrand.isProvides, "Dependencies are arcs in the module graph")
    let newNode = Graph.Node(key: integrand.key,
                             fingerprint: integrand.fingerprint,
                             dependencySource: sourceGraph.dependencySource)
    let oldNode = destination.nodeFinder.insert(newNode)
    assert(oldNode == nil, "Should be new!")
    addNew(newNode)
    return newNode
  }

  /// Find the keys of nodes used by this node, and record the def-use links.
  /// Also see if any of those keys are external dependencies, and if such is a new dependency,
  /// record the external dependency, and record the node as changed.
  private mutating func recordDefsForThisUse(
    _ sourceFileUseNode: SourceFileDependencyGraph.Node,
    _ moduleUseNode: Graph.Node
  ) {
    sourceGraph.forEachDefDependedUpon(by: sourceFileUseNode) { def in
      guard
        destination.nodeFinder.record(def: def.key, use: moduleUseNode),
        let externalDependency = def.key.designator.externalDependency
      else {
        return
      }

      recordInvalidations(
        from: FingerprintedExternalDependency(externalDependency, def.fingerprint))
    }
  }

  // A `moduleGraphUseNode` is used by an externalDependency key being integrated.
  // Remember the dependency for later processing in externalDependencies, and
  // also return it in results.
  // Also the use node has changed.
  private mutating func recordInvalidations(
    from externalDependency: FingerprintedExternalDependency
  ) {
    let invalidated = destination.integrateExternal(.unknown(externalDependency))
    invalidatedNodes.formUnion(invalidated)
  }
}

// MARK: - Results {
extension ModuleDependencyGraph.Integrator {
  mutating func addDisappeared(_ node: Graph.Node) {
    assert(isUpdating)
    invalidatedNodes.insert(node)
  }
  mutating func addChanged(_ node: Graph.Node) {
    assert(isUpdating)
    invalidatedNodes.insert(node)
  }
  mutating func addPatriated(_ node: Graph.Node) {
    if isUpdating {
      reporter?.report("Discovered a definition for \(node)")
      invalidatedNodes.insert(node)
    }
  }
  mutating func addNew(_ node: Graph.Node) {
    if isUpdating {
      reporter?.report("New definition: \(node)")
      invalidatedNodes.insert(node)
    }
  }
}

// MARK: - verification
extension ModuleDependencyGraph.Integrator {
  @discardableResult
  func verifyAfterImporting() -> Bool {
    guard let nodesInFile = destination.nodeFinder.findNodes(for: sourceGraph.dependencySource),
          !nodesInFile.isEmpty
    else {
      fatalError("Just imported \(sourceGraph.dependencySource), should have nodes")
    }
    return destination.verifyGraph()
  }
}
