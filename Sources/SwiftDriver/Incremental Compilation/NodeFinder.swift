//===------------------ NodesAndUses.swift --------------------------------===//
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
  
  /// The core information for the ModuleDependencyGraph
  /// Isolate in a sub-structure in order to faciliate invariant maintainance
  struct NodeFinder {

    /// Maps swiftDeps files and DependencyKeys to Nodes
    fileprivate typealias NodeMap = TwoDMap<String?, DependencyKey, ModuleDepGraphNode>
    fileprivate var nodeMap = NodeMap()

    /// Since dependency keys use baseNames, they are coarser than individual
    /// decls. So two decls might map to the same key. Given a use, which is
    /// denoted by a node, the code needs to find the files to recompile. So, the
    /// key indexes into the nodeMap, and that yields a submap of nodes keyed by
    /// file. The set of keys in the submap are the files that must be recompiled
    /// for the use.
    /// (In a given file, only one node exists with a given key, but in the future
    /// that would need to change if/when we can recompile a smaller unit than a
    /// source file.)

    /// Tracks def-use relationships by DependencyKey.
    private(set)var usesByDef = Multidictionary<DependencyKey, ModuleDepGraphNode>()
  }
}
// MARK: - finding
extension ModuleDependencyGraph.NodeFinder {
  func findFileInterfaceNode(forSwiftDeps swiftDeps: String) -> ModuleDepGraphNode?  {
    let fileKey = DependencyKey(interfaceForSourceFile: swiftDeps)
    return findNode((swiftDeps, fileKey))
  }
  func findNode(_ mapKey: (String?, DependencyKey)) -> ModuleDepGraphNode? {
    nodeMap[mapKey]
  }

  func findNodes(for swiftDeps: String?) -> [DependencyKey: ModuleDepGraphNode]? {
    nodeMap[swiftDeps]
  }
  func findNodes(for key: DependencyKey) -> [String?: ModuleDepGraphNode]? {
    nodeMap[key]
  }

  /// Since uses must be somewhere, pass inthe swiftDeps to the function here
  func forEachUse(_ fn: (DependencyKey, ModuleDepGraphNode, String) -> Void) {
    usesByDef.forEach {
      def, use in
      fn(def, use, useMustHaveSwiftDeps(use))
    }
  }
  func forEachUse(of def: DependencyKey, _ fn: (ModuleDepGraphNode, String) -> Void) {
    usesByDef[def].map {
      $0.values.forEach { use in
        fn(use, useMustHaveSwiftDeps(use))
      }
    }
  }

  func mappings(of n: ModuleDepGraphNode) -> [(String?, DependencyKey)]
  {
    nodeMap.compactMap {
      k, _ in
      k.0 == n.swiftDeps && k.1 == n.dependencyKey
        ? k
        : nil
    }
  }

  func defsUsing(_ n: ModuleDepGraphNode) -> [DependencyKey] {
    usesByDef.keysContainingValue(n)
  }
}

fileprivate extension ModuleDepGraphNode {
  var mapKey: (String?, DependencyKey) {
    return (swiftDeps, dependencyKey)
  }
}

// MARK: - inserting

extension ModuleDependencyGraph.NodeFinder {

  /// Add \c node to the structure, return the old node if any at those coordinates.
  @discardableResult
  mutating func insert(_ n: ModuleDepGraphNode)
  -> ModuleDepGraphNode?
  {
    nodeMap.updateValue(n, forKey: n.mapKey)
  }

   /// record def-use, return if is new use
  mutating func record(def: DependencyKey, use: ModuleDepGraphNode)
  -> Bool {
    verifyUseIsOK(use)
    return usesByDef.addValue(use, forKey: def)
  }
}

// MARK: - removing
extension ModuleDependencyGraph.NodeFinder {
  mutating func remove(_ nodeToErase: ModuleDepGraphNode) {
    // uses first preserves invariant that every used node is in nodeMap
    removeUsings(of: nodeToErase)
    removeMapping(of: nodeToErase)
  }

  private mutating func removeUsings(of nodeToNotUse: ModuleDepGraphNode) {
    usesByDef.removeValue(nodeToNotUse)
    assert(defsUsing(nodeToNotUse).isEmpty)
  }

  private mutating func removeMapping(of nodeToNotMap: ModuleDepGraphNode) {
    let old = nodeMap.removeValue(forKey: nodeToNotMap.mapKey)
    assert(old == nodeToNotMap, "Should have been there")
    assert(mappings(of: nodeToNotMap).isEmpty)
  }
}

// MARK: - moving
extension ModuleDependencyGraph.NodeFinder {
  /// When integrating a SourceFileDepGraph, there might be a node representing
  /// a Decl that had previously been read as an expat, that is a node
  /// representing a Decl in no known file (to that point). (Recall the the
  /// Frontend processes name lookups as dependencies, but does not record in
  /// which file the name was found.) In such a case, it is necessary to move
  /// the node to the proper collection.
  ///
  /// Now that nodes are immutable, this function needs to replace the node
  mutating func replace(_ original: ModuleDepGraphNode,
                        newSwiftDeps: String,
                        newFingerprint: String?)
  -> ModuleDepGraphNode
  {
    let replacement = ModuleDepGraphNode(key: original.dependencyKey,
                                         fingerprint: newFingerprint,
                                         swiftDeps: newSwiftDeps)
    usesByDef.replace(original, with: replacement, forKey: original.dependencyKey)
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
    var nodes = [Set<ModuleDepGraphNode>(), Set<ModuleDepGraphNode>()]
    nodeMap.verify {
      _, v, submapIndex in
      if let prev = nodes[submapIndex].update(with: v) {
        fatalError("\(v) is also in nodeMap at \(prev), submap: \(submapIndex)")
      }
      v.verify()
    }
  }

  private func verifyUsesByDef() {
    usesByDef.forEach {
      def, use in
      // def may have disappeared from graph, nothing to do
      verifyUseIsOK(use)
    }
  }

  private func useMustHaveSwiftDeps(_ n: ModuleDepGraphNode)  -> String {
    assert(verifyUseIsOK(n))
    return n.swiftDeps!
  }

  @discardableResult
  private func verifyUseIsOK(_ n: ModuleDepGraphNode) -> Bool {
    verifyUsedIsNotExpat(n)
    verifyNodeIsMapped(n)
    return true
  }

  private func verifyNodeIsMapped(_ n: ModuleDepGraphNode) {
    if findNode(n.mapKey) == nil {
      fatalError("\(n) should be mapped")
    }
  }

  @discardableResult
  private func verifyUsedIsNotExpat(_ use: ModuleDepGraphNode) -> Bool {
    guard use.isExpat else { return true }
    fatalError("An expat is not defined anywhere and thus cannot be used")
  }
}
// MARK: - key helpers

fileprivate extension DependencyKey {
  init(interfaceForSourceFile swiftDeps: String) {
    self.init(aspect: .interface,
              designator: .sourceFileProvide(name: swiftDeps))
  }
}
