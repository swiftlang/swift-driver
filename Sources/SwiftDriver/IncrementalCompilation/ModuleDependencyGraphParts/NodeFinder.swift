//===-------------------- NodeFinder.swift --------------------------------===//
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

  // Shorthands

  /// The core information for the ModuleDependencyGraph
  /// Isolate in a sub-structure in order to facilitate invariant maintenance
  public struct NodeFinder {
    @_spi(Testing) public typealias Graph = ModuleDependencyGraph

    /// Maps definition locations and DependencyKeys to Nodes
    fileprivate typealias NodeMap = TwoDMap<DefinitionLocation, DependencyKey, Node>
    fileprivate var nodeMap = NodeMap()

    /// Since dependency keys use baseNames, they are coarser than individual
    /// decls. So two decls might map to the same key. Given a use, which is
    /// denoted by a node, the code needs to find the files to recompile. So, the
    /// key indexes into the nodeMap, and that yields a submap of nodes keyed by
    /// definition location. The set of keys in the submap are the files that must be recompiled
    /// for the use.
    /// (In a given file, only one node exists with a given key, but in the future
    /// that would need to change if/when we can recompile a smaller unit than a
    /// source file.)

    /// Tracks def-use relationships by DependencyKey.
    @_spi(Testing) public private(set) var usesByDef = Multidictionary<DependencyKey, Node>()
  }
}
// MARK: - finding

extension ModuleDependencyGraph.NodeFinder {
  public typealias DefinitionLocation = ModuleDependencyGraph.DefinitionLocation

  @_spi(Testing) public func findNode(_ mapKey: (DefinitionLocation, DependencyKey)) -> Graph.Node? {
    nodeMap[mapKey]
  }
  func findCorrespondingImplementation(of n: Graph.Node) -> Graph.Node? {
    n.key.correspondingImplementation
      .flatMap {findNode((n.definitionLocation, $0))}
  }

  @_spi(Testing) public func findNodes(for definitionLocation: DefinitionLocation)
  -> [DependencyKey: Graph.Node]? {
    nodeMap[definitionLocation]
  }
  @_spi(Testing) public func findNodes(for key: DependencyKey) -> [DefinitionLocation: Graph.Node]? {
    nodeMap[key]
  }

  /// Calls the given closure on each node in this dependency graph.
  ///
  /// - Note: The order of iteration between successive runs of the driver is
  ///         not guaranteed.
  ///
  /// - Parameter visit: The closure to call with each graph node.
  @_spi(Testing) public func forEachNode(_ visit: (Graph.Node) -> Void) {
    nodeMap.forEach { visit($1) }
  }

  /// Retrieves the set of uses corresponding to a given node.
  ///
  /// - Warning: The order of uses is not defined. It is not sound to iterate
  ///            over the set of uses, use `Self.orderedUses(of:)` instead.
  ///
  /// - Parameter def: The node to look up.
  /// - Returns: A set of nodes corresponding to the uses of the given
  ///            definition node.
  func uses(of def: Graph.Node) -> Set<Graph.Node> {
    var uses = usesByDef[def.key, default: Set()]
    if let impl = findCorrespondingImplementation(of: def) {
      uses.insert(impl)
    }
    #if DEBUG
    for use in uses {
      assert(self.verifyOKTODependUponSomeKey(use))
    }
    #endif
    return uses
  }

  func mappings(of n: Graph.Node) -> [(DefinitionLocation, DependencyKey)] {
    nodeMap.compactMap { k, _ in
      guard k.0 == n.definitionLocation && k.1 == n.key else {
        return nil
      }
      return k
    }
  }

  func defsUsing(_ n: Graph.Node) -> Set<DependencyKey> {
    usesByDef.keysContainingValue(n)
  }
}

fileprivate extension ModuleDependencyGraph.Node {
  var mapKey: (DefinitionLocation, DependencyKey) {
    return (definitionLocation, key)
  }
}

// MARK: - inserting

extension ModuleDependencyGraph.NodeFinder {

  /// Add `node` to the structure, return the old node if any at those coordinates.
  @discardableResult
  mutating func insert(_ n: Graph.Node) -> Graph.Node? {
    nodeMap.updateValue(n, forKey: n.mapKey)
  }

  /// record def-use, return if is new use
  mutating func record(def: DependencyKey, use: Graph.Node) -> Bool {
    assert(verifyOKTODependUponSomeKey(use))
    return usesByDef.insertValue(use, forKey: def)
  }
}

// MARK: - removing
extension ModuleDependencyGraph.NodeFinder {
  mutating func remove(_ nodeToErase: Graph.Node) {
    // uses first preserves invariant that every used node is in nodeMap
    removeUsings(of: nodeToErase)
    removeMapping(of: nodeToErase)
  }

  private mutating func removeUsings(of nodeToNotUse: Graph.Node) {
    usesByDef.removeOccurrences(of: nodeToNotUse)
    assert(defsUsing(nodeToNotUse).isEmpty)
  }

  private mutating func removeMapping(of nodeToNotMap: Graph.Node) {
    let old = nodeMap.removeValue(forKey: nodeToNotMap.mapKey)
    assert(old == nodeToNotMap, "Should have been there")
    assert(mappings(of: nodeToNotMap).isEmpty)
  }
}

// MARK: - moving
extension ModuleDependencyGraph.NodeFinder {
  /// When integrating a SourceFileDepGraph, there might be a node representing
  /// a Decl that previously no known definition location.
  /// (Recall the the Frontend processes name lookups as dependencies, but does not record in
  /// which file the name was found.) When the definition is found in a `SourceFileDepGraph`
  /// it is necessary to "move" the node to the proper collection.
  ///
  /// Now that nodes are immutable, this function needs to replace the node
  mutating func replace(_ original: Graph.Node,
                        newDependencySource: DependencySource,
                        newFingerprint: InternedString?
  ) -> Graph.Node {
    let replacement = Graph.Node(key: original.key,
                                 fingerprint: newFingerprint,
                                 definitionLocation: .known(newDependencySource))
    assert(original.definitionLocation == .unknown,
           "Would have to search every use in usesByDef if original could be a use.")
    if usesByDef.removeValue(original, forKey: original.key) != nil {
      usesByDef.insertValue(replacement, forKey: original.key)
    }
    nodeMap.removeValue(forKey: original.mapKey)
    nodeMap.updateValue(replacement, forKey: replacement.mapKey)
    return replacement
  }
}

// MARK: - asserting & verifying
extension ModuleDependencyGraph.NodeFinder {
  func verify() -> Bool {
    verifyNodeMap()
    verifyUsesByDef()
    return true
  }

  private func verifyNodeMap() {
    var nodes = [Set<Graph.Node>(), Set<Graph.Node>()]
    nodeMap.verify {
      _, v, submapIndex in
      if let prev = nodes[submapIndex].update(with: v) {
        fatalError("\(v) is also in nodeMap at \(prev), submap: \(submapIndex)")
      }
      v.verify()
    }
  }

  private func verifyUsesByDef() {
    usesByDef.forEach { someKey, nodesDependingUponKey in
      for nodeDependingUponKey in nodesDependingUponKey {
        verifyOKTODependUponSomeKey(nodeDependingUponKey)
      }
    }
  }

  @discardableResult
  private func verifyOKTODependUponSomeKey(_ n: Graph.Node) -> Bool {
    verifyDependentNodeHasKnownDefinitionLocation(n)
    verifyNodeCanBeFoundFromItsKey(n)
    return true
  }

  private func verifyNodeCanBeFoundFromItsKey(_ n: Graph.Node) {
    precondition(findNode(n.mapKey) == n)
  }

  @discardableResult
  private func verifyDependentNodeHasKnownDefinitionLocation(_ use: Graph.Node) -> Bool {
    guard case .unknown = use.definitionLocation else { return true }
    fatalError("This declaration is not defined anywhere and thus cannot depend upon anything.")
  }
}

// MARK: - Checking Serialization
extension ModuleDependencyGraph.NodeFinder {
  func matches(_ other: Self) -> Bool {
    nodeMap == other.nodeMap && usesByDef == other.usesByDef
  }
}
