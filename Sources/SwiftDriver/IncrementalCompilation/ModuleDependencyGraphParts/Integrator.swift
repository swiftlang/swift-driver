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

extension ModuleDependencyGraph {

  // MARK: Integrator - state & creation

  /// Integrates a \c SourceFileDependencyGraph into a \c ModuleDependencyGraph. See ``Integrator/integrate(from:dependencySource:into:)``
  public struct Integrator {

    // Shorthands
    /*@_spi(Testing)*/ public typealias Graph = ModuleDependencyGraph
    typealias DefinitionLocation = Graph.DefinitionLocation

    public private(set) var invalidatedNodes = DirectlyInvalidatedNodeSet()

    /// If integrating from an .swift file in the build, refers to the .swift file
    /// Otherwise, refers to a .swiftmodule file
    let dependencySource: DependencySource

    /// the graph to be integrated
    let sourceGraph: SourceFileDependencyGraph

    /// the graph to be integrated into
    let destination: ModuleDependencyGraph

    /// Starts with all nodes in the `DependencySource` to be integrated.
    /// Then as nodes are found in this source, they are removed from here.
    /// After integration is complete, this dictionary contains the nodes that have disappeared from this `DependencySource`.
    var disappearedNodes = [DependencyKey: Graph.Node]()

    init(sourceGraph: SourceFileDependencyGraph,
         dependencySource: DependencySource,
         destination: ModuleDependencyGraph)
    {
      self.sourceGraph = sourceGraph
      self.dependencySource = dependencySource
      self.destination = destination
      self.disappearedNodes = destination.nodeFinder
      .findNodes(for: .known(dependencySource))
        ?? [:]
    }

    var reporter: IncrementalCompilationState.Reporter? {
      destination.info.reporter
    }

    var sourceType: FileType {
      dependencySource.typedFile.type
    }

    var isUpdating: Bool {
      destination.phase.isUpdating
    }
  }
}
// MARK: - integrate a graph
extension ModuleDependencyGraph.Integrator {
  /// Integrate a SourceFileDepGraph into the receiver.
  ///
  /// Integration happens when the driver needs to read SourceFileDepGraph.
  /// Common to scheduling both waves.
  /// - Parameters:
  ///   - g: the graph to be integrated from
  ///   - dependencySource: holds the .swift or .swifmodule file containing the dependencies to be integrated that were read into `g`
  ///   - destination: the graph to be integrated into
  /// - Returns: all nodes directly affected by the integration, plus nodes transitively affected by integrated external dependencies.
  /// Because external dependencies may have transitive effects not captured by the frontend, changes from them are always transitively closed.
  public static func integrate(
    from g: SourceFileDependencyGraph,
    dependencySource: DependencySource,
    into destination: Graph
  ) -> DirectlyInvalidatedNodeSet {
    precondition(g.internedStringTable === destination.internedStringTable)
    var integrator = Self(sourceGraph: g,
                          dependencySource: dependencySource,
                          destination: destination)
    integrator.integrate()

    if destination.info.verifyDependencyGraphAfterEveryImport {
      integrator.verifyAfterImporting()
    }
    destination.dotFileWriter?.write(g, for: dependencySource.typedFile,
                                     internedStringTable: destination.internedStringTable)
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
    guard integrand.definitionVsUse == .definition else {
      // Uses are captured by recordWhatIsDependedUpon below.
      return
    }

    let integratedNode = destination.nodeFinder.findNodes(for: integrand.key)
      .flatMap {
        integrateWithNodeDefinedHere(    integrand, $0) ??
        integrateWithNodeDefinedNowhere( integrand, $0)
      }
    ?? integrateWithNewNode(integrand)

    recordDefsForThisUse(integrand, integratedNode)
  }

  /// If a node to be integrated corresponds to one already in the destination graph for the same source, integrate it.
  ///
  /// - Parameters:
  ///   - integrand: the node to be integrated
  ///   - nodesMatchingKey: all nodes in the destination graph with matching `DependencyKey`
  ///  - Returns: nil if a corresponding node did *not* already exist for the same source,
  ///  Otherwise, the integrated corresponding node.
  ///  If the integrated node was changed by the integration, it is added to ``invalidatedNodes``.
  private mutating func integrateWithNodeDefinedHere(
    _ integrand: SourceFileDependencyGraph.Node,
    _ nodesMatchingKey: [DefinitionLocation: Graph.Node]
  ) -> Graph.Node? {
    guard let matchHere = nodesMatchingKey[.known(dependencySource)] else {
      return nil
    }
    assert(matchHere.definitionLocation == .known(dependencySource))
    // Node was and still is. Do not remove it.
    disappearedNodes.removeValue(forKey: matchHere.key)
    enum FingerprintDisposition: String {
      case missing, changed, stable
      init(_ integrand: SourceFileDependencyGraph.Node,
           _ matchHere: ModuleDependencyGraph.Node) {
        switch (integrand.fingerprint, matchHere.fingerprint) {
        case (nil, _):
          self = .missing
        case (_?, nil):
          self = .changed
        case let (integrandFingerprint?, matchHereFingerprint?):
          self = integrandFingerprint == matchHereFingerprint
          ? .stable : .changed
        }
      }
    }
    let disposition = FingerprintDisposition(integrand, matchHere)
    switch disposition {
    case .stable:
      break
    case .missing:
      // Since we only put fingerprints in enums, structs, classes, etc.,
      // the driver really lacks the information to do much here.
      // Just report it.
      reporter?.report("Fingerprint \(disposition.rawValue) for existing \(matchHere.description(in: destination))")
      break
    case .changed:
      matchHere.setFingerprint(integrand.fingerprint)
      addChanged(matchHere)
      reporter?.report("Fingerprint \(disposition.rawValue) for existing \(matchHere.description(in: destination))")
    }
    return matchHere
  }

  /// If a node to be integrated correspnds with a node in the graph belonging to no dependency source read as yet, integrate it.
  /// The node to be integrated represents the definition of a declaration whose uses have already been seen.
  /// The existing node is "moved" to its proper place in the graph, corresponding to the location of the definition of the declaration.
  ///
  /// - Parameters:
  ///   - integrand: the node to be integrated
  ///   - nodesMatchingKey: all nodes in the destination graph with matching `DependencyKey`
  /// - Returns: nil if a corresponding node *did* have a definition location, or the integrated corresponding node if it did not.
  ///  If the integrated node was changed by the integration, it is added to ``invalidatedNodes``.
  private mutating func integrateWithNodeDefinedNowhere(
    _ integrand: SourceFileDependencyGraph.Node,
    _ nodesMatchingKey: [DefinitionLocation: Graph.Node]
  ) -> Graph.Node? {
    guard let nodeWithNoDefinitionLocation = nodesMatchingKey[.unknown] else {
      return nil
    }
    assert(nodesMatchingKey.count == 1,
           "The graph never holds more than one node for a given key that has no definition location")
    let integratedNode = destination.nodeFinder
      .replace(nodeWithNoDefinitionLocation,
               newDependencySource: self.dependencySource,
               newFingerprint: integrand.fingerprint)
    addPatriated(integratedNode)
    return integratedNode
  }

  /// Integrate a node that correspnds with no known node.
  ///
  /// - Parameters:
  ///   - integrand: the node to be integrated
  /// - Returns: the integrated node
  /// Since the integrated nodeis a change, it is added to ``invalidatedNodes``.
 private mutating func integrateWithNewNode(
    _ integrand: SourceFileDependencyGraph.Node
  ) -> Graph.Node {
    precondition(integrand.definitionVsUse == .definition,
                 "Dependencies are arcs in the module graph")
    let newNode = Graph.Node(
      key: integrand.key,
      fingerprint: integrand.fingerprint,
      definitionLocation: .known(dependencySource))
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
      let isNewUse = destination.nodeFinder.record(def: def.key,
                                                   use: moduleUseNode)
      guard
        isNewUse,
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
    let integrand = ModuleDependencyGraph.ExternalIntegrand(externalDependency, in: destination)
    let invalidated = destination.findNodesInvalidated(by: integrand)
    recordUsesOfSomeExternal(invalidated)
  }
}

// MARK: - Results {
extension ModuleDependencyGraph.Integrator {
  /*@_spi(Testing)*/
    mutating func recordUsesOfSomeExternal(_ invalidated: DirectlyInvalidatedNodeSet)
    {
      invalidatedNodes.formUnion(invalidated)
    }
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
      reporter?.report("Discovered a definition for \(node.description(in: destination))")
      invalidatedNodes.insert(node)
    }
  }
  mutating func addNew(_ node: Graph.Node) {
    if isUpdating {
      reporter?.report("New definition: \(node.description(in: destination))")
      invalidatedNodes.insert(node)
    }
  }
}

// MARK: - verification
extension ModuleDependencyGraph.Integrator {
  @discardableResult
  func verifyAfterImporting() -> Bool {
    guard let nodesInFile = destination.nodeFinder.findNodes(for: .known(dependencySource)),
          !nodesInFile.isEmpty
    else {
      fatalError("Just imported \(dependencySource), should have nodes")
    }
    return destination.verifyGraph()
  }
}
