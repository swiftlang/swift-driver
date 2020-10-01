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


fileprivate struct NodesAndUses {
  
  /// Maps swiftDeps files and DependencyKeys to Nodes
  fileprivate typealias NodeMap = TwoDMap<String, DependencyKey, ModuleDepGraphNode>
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
// MARK: - finding
extension NodesAndUses {
  func findNode(_ swiftDeps: String, _ key: DependencyKey) -> ModuleDepGraphNode? {
    nodeMap[(swiftDeps, key)]
  }
  
  func findNodes(for swiftDeps: String) -> [DependencyKey: ModuleDepGraphNode]? {
    nodeMap[swiftDeps]
  }
  func findNodes(for key: DependencyKey) -> [String: ModuleDepGraphNode]? {
    nodeMap[key]
  }
  
  func forEachUse(_ fn: (DependencyKey, ModuleDepGraphNode) -> Void) {
    usesByDef.forEach {
      def, use in
      assertUseIsOK(use)
      fn(def, use)
    }
  }
  func forEachUse(of def: DependencyKey, _ fn: (ModuleDepGraphNode) -> Void) {
    usesByDef[def].map {
      $0.values.forEach { use in
        assertUseIsOK(use)
        fn(use)
      }
    }
  }

  func mappings(of n: ModuleDepGraphNode) -> [(String, DependencyKey)]
  {
    // TODO: Incremental use keyForNodeMap
    nodeMap.compactMap {
      k, _ in
      k.0 == n.swiftDeps && k.1 == n.key
        ? k
        : nil
    }
  }

  func defsUsing(_ n: ModuleDepGraphNode) -> [DependencyKey] {
    usesByDef.keysContainingValue(n)
  }
}

// MARK: - inserting

extension NodesAndUses {

  /// Add \c node to the structure, return the old node if any at those coordinates.
  /// \c isUsed helps for assertion checking.
  /// TODO: Incremental clean up doxygens
  @discardableResult
  mutating func insert(_ n: ModuleDepGraphNode, isUsed: Bool?)
  -> ModuleDepGraphNode?
  {
    nodeMap.updateValue(n, forKey: (n.swiftDeps, n.key))
  }

  // TODO: Incremental consistent open { for fns

   /// record def-use, return if is new use
  mutating func record(def: DependencyKey, use: ModuleDepGraphNode)
  -> Bool {
    verifyUseIsOK(use)
    return usesByDef.addValue(use, forKey: def)
  }
}

// MARK: - removing
extension NodesAndUses {
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
    // TODO: Incremental use nodeMapKey
    let old = nodeMap.removeValue(forKey: (nodeToNotMap.swiftDeps, nodeToNotMap.key))
    assert(old == nodeToNotMap, "Should have been there")
    assert(mappings(of: nodeToNotMap).isEmpty)
  }
}

// MARK: - moving
extension NodesAndUses {
 /// When integrating a SourceFileDepGraph, there might be a node representing
  /// a Decl that had previously been read as an expat, that is a node
  /// representing a Decl in no known file (to that point). (Recall the the
  /// Frontend processes name lookups as dependencies, but does not record in
  /// which file the name was found.) In such a case, it is necessary to move
  /// the node to the proper collection.
   mutating func move(_ nodeToMove: ModuleDepGraphNode, toDifferentFile newFile: String) {
    removeMapping(of: nodeToMove)
    nodeToMove.swiftDeps = newFile
    insert(nodeToMove, isUsed: nil)
  }
}

// MARK: - asserting & verifying
extension NodesAndUses {
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

  private func assertUseIsOK(_ n: ModuleDepGraphNode) {
    assert(verifyUseIsOK(n))
  }

  @discardableResult
  private func verifyUseIsOK(_ n: ModuleDepGraphNode) -> Bool {
    verifyExpatsAreNotUses(n, isUsed: true)
    verifyNodeIsMapped(n)
    return true
  }

  private func verifyNodeIsMapped(_ n: ModuleDepGraphNode) {
    if findNode(n.swiftDeps, n.key) == nil {
      fatalError("\(n) should be mapped")
    }
  }

  /// isUsed is an optimization
  @discardableResult
  private func verifyExpatsAreNotUses(_ use: ModuleDepGraphNode, isUsed: Bool?) -> Bool {
    guard use.isExpat else {return true}
    let isReallyUsed = isUsed ?? !defsUsing(use).isEmpty
    if (isReallyUsed) {
      fatalError("An expat is not defined anywhere and thus cannot be used")
    }
    return false
  }
}

// TODO: Incremental UP TO HERE
// MARK: - ModuleDependencyGraph

@_spi(Testing) public final class ModuleDependencyGraph {

  private var nodesAndUses = NodesAndUses()

  // Supports requests from the driver to getExternalDependencies.
  @_spi(Testing) public private(set) var externalDependencies = Set<String>()

  /// Keyed by swiftdeps filename, so we can get back to Jobs.
  private var jobsBySwiftDeps: [String: Job] = [:]


  let verifyDependencyGraphAfterEveryImport: Bool
  let emitDependencyDotFileAfterEveryImport: Bool

  @_spi(Testing) public let diagnosticEngine: DiagnosticsEngine

  /// If tracing dependencies, holds a vector used to hold the current path
  /// def - use/def - use/def - ...
  private var currentPathIfTracing: [ModuleDepGraphNode]? = nil

  /// If tracing dependencies, holds the sequence of defs used to get to the job
  /// that is the key
  private var dependencyPathsToJobs = Multidictionary<Job, [ModuleDepGraphNode]>()

  static func buildInitialGraph(jobs: [Job],
                                verifyDependencyGraphAfterEveryImport: Bool,
                                emitDependencyDotFileAfterEveryImport: Bool,
                                diagnosticEngine: DiagnosticsEngine) -> Self {
    let r = Self(verifyDependencyGraphAfterEveryImport: verifyDependencyGraphAfterEveryImport,
                 emitDependencyDotFileAfterEveryImport: emitDependencyDotFileAfterEveryImport,
                 diagnosticEngine: diagnosticEngine)
    for job in jobs { _ = r.integrate(job: job) }
    return r
  }

  public init(
    verifyDependencyGraphAfterEveryImport: Bool,
    emitDependencyDotFileAfterEveryImport: Bool,
    diagnosticEngine: DiagnosticsEngine) {
    self.verifyDependencyGraphAfterEveryImport = verifyDependencyGraphAfterEveryImport
    self.emitDependencyDotFileAfterEveryImport = emitDependencyDotFileAfterEveryImport
    self.diagnosticEngine = diagnosticEngine
  }

  // nil means there was an error
  // TODO: Incremental use sets of Keys and SwiftDeps instead because
  // nodes should not exist anymore
  // And optimize first time
  @_spi(Testing) public  typealias Changes = Set<ModuleDepGraphNode>?

  func integrate(job: Job) -> Changes {
    registerJob(job)
    let graphsAndDeps = getSourceFileDependencyGraphs(job: job)
    let goodGraphsAndDeps = graphsAndDeps
      .compactMap {gd in gd.graph.map {(graph: $0, swiftDeps: gd.swiftDeps)}}

    let changedNodes = goodGraphsAndDeps
      .flatMap {integrate(graph: $0.graph, swiftDeps: $0.swiftDeps)}

    let hadError = graphsAndDeps.count != goodGraphsAndDeps.count

    return hadError ? nil : Set(changedNodes)
  }

  /// Integrate a SourceFileDepGraph into the receiver.
  /// Integration happens when the driver needs to read SourceFileDepGraph.
  /// Returns changed nodes
  @_spi(Testing) public func integrate(graph g: SourceFileDependencyGraph,
                                       swiftDeps: String)
  -> Set<ModuleDepGraphNode> {
    var disappearedNodes = nodesAndUses.findNodes(for: swiftDeps) ?? [:]

    // When done, changeDependencyKeys contains a list of keys that changed
    // as a result of this integration.
    // Or if the integration failed, None.
    var changedNodes = Set<ModuleDepGraphNode>()

    g.forEachNode {
      // TODO: Incremental pull out loop body and return instead of mutate dis and changed
      integrand in
      let key = integrand.key
      let preexistingMatch = PreexistingNode(
        matches: nodesAndUses.findNodes(for: key),
        integrand: integrand,
        swiftDeps: swiftDeps)
      if case let .here(node) = preexistingMatch {
        assert(node.key == key)
        disappearedNodes.removeValue(forKey: node.key)  // Node was and still is. Do not remove it.
      }

      let newOrChangedNode = integrateSourceFileDepGraphNode(
        g,
        integrand,
        preexistingMatch,
        swiftDeps)

      if let n = newOrChangedNode {
        changedNodes.insert(n)
      }
    }
    for (_, node) in disappearedNodes {
      changedNodes.insert(node)
      nodesAndUses.remove(node)
    }

    changedNodes.forEach {$0.clearHasBeenTraced()}

    if verifyDependencyGraphAfterEveryImport {
      verifyAfterImporting(g, swiftDeps, changedNodes)
    }
    if emitDependencyDotFileAfterEveryImport {
      emitDotFile(g, swiftDeps)
    }

    return changedNodes
  }


  @discardableResult
  func verifyAfterImporting(_ sfg: SourceFileDependencyGraph,
                            _ swiftDeps: String,
                            _ changedNodes: Set<ModuleDepGraphNode>)
  -> Bool {
    guard let nodesInFile = nodesAndUses.findNodes(for: swiftDeps),
          !nodesInFile.isEmpty
    else {
      fatalError("Just imported \(swiftDeps), should have nodes")
    }
    return verifyGraph()
  }

  @discardableResult
  func verifyGraph() -> Bool {
    nodesAndUses.verify()
  }

 /// nil graph for error
  private func getSourceFileDependencyGraphs(job: Job)
  -> [(graph: SourceFileDependencyGraph?, swiftDeps: String)] {
    let swiftDepsOutputs = job.outputs.filter {$0.type == .swiftDeps}
    return swiftDepsOutputs.map {
        do {
          return try SourceFileDependencyGraph.read(from: $0)
        }
        catch {
          diagnosticEngine.emit(
            .error_cannot_read_swiftdeps(file: $0, reason: error.localizedDescription)
          )
          return (graph: nil, swiftDeps: $0.file.name)
        }
      }
  }

  /// Returns a new or changed node
  /// TODO: Integration name vs integrate above
  private func integrateSourceFileDepGraphNode(
    _ g: SourceFileDependencyGraph,
    _ integrand: SourceFileDependencyGraph.Node,
    _ preexistingMatch: PreexistingNode,
    _ swiftDeps: String)
  -> ModuleDepGraphNode? {
    if !integrand.isProvides {
      // depends are captured by recordWhatUseDependsUpon below
      return nil
    }

    let (hasChange, integratedNode) = integrateSourceFileDeclNode(
      integrand, swiftDeps, preexistingMatch)

    let hasNewExternalDependency = recordWhatUseDependsUpon(g, integrand, integratedNode)

    let changedNode = hasChange || hasNewExternalDependency
      ? integratedNode
      : nil

    return changedNode
  }

  private func integrateSourceFileDeclNode(
    _ integrand: SourceFileDependencyGraph.Node,
    _ swiftDeps: String,
    _ preexistingMatch: PreexistingNode
  ) -> (foundChange: Bool, node: ModuleDepGraphNode) {
    switch preexistingMatch {
      case .none:
        /// Came from nowhere. (Goes to nowhere case is handled by dissapearedNodes.)
        return (true, integrateANewDef(integrand, swiftDeps))

      case .here(let n):
        return (
          foundChange: n.integrateFingerprintFrom(integrand),
          node: n)

      case .nowhere(let n):
        // Some other file depended on this, but didn't know where it was.
        nodesAndUses.move(n, toDifferentFile: swiftDeps)
        _ = n.integrateFingerprintFrom(integrand)
        return (foundChange: true, n) // New decl, assume changed

      case .elsewhere:
        // new node, same base name
        return (foundChange: true, integrateANewDef(integrand, swiftDeps)
        )
    }
  }

  private func integrateANewDef(
    _ integrand: SourceFileDependencyGraph.Node,
    _ swiftDeps: String)
  -> ModuleDepGraphNode
  {
    precondition(integrand.isProvides, "Dependencies are arcs in the module graph")
    let newNode = ModuleDepGraphNode(
      key: integrand.key,
      fingerprint: integrand.fingerprint,
      swiftDeps: swiftDeps)
    let oldNode = nodesAndUses.insert(newNode, isUsed: false)
    assert(oldNode == nil, "Should be new!")
    return newNode
  }


  func recordWhatUseDependsUpon(
    _ g: SourceFileDependencyGraph,
    _ sourceFileUseNode: SourceFileDependencyGraph.Node,
    _ moduleUseNode: ModuleDepGraphNode)
  -> Bool {
    var useHasNewExternalDependency = false
    // TODO: Incremental slow???
    g.forEachDefDependedUpon(by: sourceFileUseNode) {
      def in
      let isNewUse = nodesAndUses.record(def: def.key, use: moduleUseNode)
      if case let .externalDepend(name: externalSwiftDeps) = def.key.designator, isNewUse {
        externalDependencies.insert(externalSwiftDeps)
        useHasNewExternalDependency = true
      }
    }
    return useHasNewExternalDependency
  }
}


fileprivate extension ModuleDependencyGraph {
  enum PreexistingNode {
    case none,
         nowhere(ModuleDepGraphNode),
         here(ModuleDepGraphNode),
         elsewhere(ModuleDepGraphNode)

    var node: ModuleDepGraphNode? {
      switch self {
        case .none: return nil
        case let .nowhere(n),
             let .here(n),
             let .elsewhere(n):
          return n
      }
    }

    init( matches: [String: ModuleDepGraphNode]?,
          integrand: SourceFileDependencyGraph.Node,
          swiftDeps: String
    ) {
      guard let matches = matches else {
        self = .none
        return
      }
      if let expat = matches[ModuleDepGraphNode.expatSwiftDeps] {
        assert(matches.count == 1,
               "If an expat exists, then must not be any matches in other files")
        self = .nowhere(expat)
        return
      }
      if let preexistingNodeInPlace = matches[swiftDeps], integrand.isProvides {
        self = .here(preexistingNodeInPlace)
        return
      }
      self = matches.first.map {.elsewhere($0.value)} ?? .none
    }
  }

}







extension ModuleDependencyGraph {
  func emitDotFile(_ g: SourceFileDependencyGraph, _ swiftDeps: String) {
    // TODO: Incremental emitDotFIle
  }
}

// TODO: Incremental: move jobs out of here, reexamine how to deal with swiftdeps reading errors

extension ModuleDependencyGraph {
  @_spi(Testing) public func findJobsToRecompileWhenWholeJobChanges(_ jobToBeRecompiled: Job) -> [Job] {
    var allNodesInJob = [ModuleDepGraphNode]()
    for swiftDeps in jobToBeRecompiled.swiftDepsPaths {
      forEachNodeInJob(swiftDeps) { allNodesInJob.append($0) }
    }
    return findJobsToRecompileWhenNodesChange(allNodesInJob);
  }
  
  @_spi(Testing) public func findJobsToRecompileWhenNodesChange<Nodes: Sequence>(_ nodes: Nodes) -> [Job]
  where Nodes.Element == ModuleDepGraphNode
  {
    var usedNodes: [ModuleDepGraphNode] = []
    nodes.forEach {findPreviouslyUntracedDependents(of: $0, into: &usedNodes)}
    return jobsContaining(usedNodes);
  }
  
  /// Testing only
  @_spi(Testing) public func haveAnyNodesBeenTraversedIn(_ job: Job) -> Bool {
    let swiftDepsInBatch = job.swiftDepsPaths
    assert(swiftDepsInBatch.count == 1, "Only used for testing single-swiftdeps jobs")
    let swiftDeps = swiftDepsInBatch[0]
    // optimization
    let fileKey = DependencyKey(interfaceForSourceFile: swiftDeps)
    if let fileNode = nodesAndUses.findNode(swiftDeps, fileKey),
       fileNode.hasBeenTraced {
      return true
    }
    
    var result = false;
    forEachNodeInJob(swiftDeps) {
      result = result || $0.hasBeenTraced
    }
    return result;
  }
  
  private func forEachNodeInJob(_ swiftDeps: String, _ fn: (ModuleDepGraphNode) -> Void) {
    nodesAndUses.findNodes(for: swiftDeps)
      .map {$0.values.forEach(fn)}
  }
  
  
  @_spi(Testing) public func registerJob(_ job: Job) {
    // No need to create any nodes; that will happen when the swiftdeps file is
    // read. Just record the correspondence.
    job.swiftDepsPaths.forEach { jobsBySwiftDeps[$0] = job }
  }
  
  @_spi(Testing) public var allJobs: [Job] {
    Array(jobsBySwiftDeps.values)
  }
  
  // Add every (swiftdeps) use of the external dependency to foundJobs.
  // Can return duplicates, but it doesn't break anything, and they will be
  // canonicalized later.
  @_spi(Testing) public func findExternallyDependentUntracedJobs(_ externalDependency: String) -> [Job] {
    var foundJobs = [Job]()
    
    forEachUntracedJobDirectlyDependentOnExternalSwiftDeps(externalSwiftDeps: externalDependency) {
      job in
      foundJobs.append(job)
      // findJobsToRecompileWhenWholeJobChanges is reflexive
      // Don't return job twice.
      for marked in findJobsToRecompileWhenWholeJobChanges(job) where marked != job {
        foundJobs.append(marked)
      }
    }
    return foundJobs;
  }
  
  private func forEachUntracedJobDirectlyDependentOnExternalSwiftDeps(
    externalSwiftDeps: String,
    _ fn: (Job) -> Void
  ) {
    // TODO move nameForDep into key
    // These nodes will depend on the *interface* of the external Decl.
    let key = DependencyKey(interfaceForExternalDepend: externalSwiftDeps)
    nodesAndUses.forEachUse(of: key) {
      use in
      if !use.hasBeenTraced {
        fn(getJob(use.swiftDeps))
      }
    }
  }

  private func findPreviouslyUntracedDependents(
    of definition: ModuleDepGraphNode,
    into found: inout [ModuleDepGraphNode]
  ) {
    guard !definition.hasBeenTraced else { return }
    definition.setHasBeenTraced();

    found.append(definition)

    // If this node is merely used, but not defined anywhere, nothing else
    // can possibly depend upon it.
    if definition.isExpat { return }

    let pathLengthAfterArrival = traceArrival(at: definition);

    // If this use also provides something, follow it
    nodesAndUses.forEachUse(of: definition.key) {
      findPreviouslyUntracedDependents(of: $0, into: &found)
    }
    traceDeparture(pathLengthAfterArrival);
  }

  private func jobsContaining<Nodes: Sequence>(_ nodes: Nodes) -> [Job]
  where Nodes.Element == ModuleDepGraphNode {
    computeSwiftDepsFromNodes(nodes).map(getJob)
  }
  private func computeSwiftDepsFromNodes<Nodes: Sequence>(_ nodes: Nodes) -> [String]
  where Nodes.Element == ModuleDepGraphNode {
    var swiftDepsOfNodes = Set<String>()
    for n in nodes {
      // TODO: Incremental if or assert?
      if !n.isExpat {swiftDepsOfNodes.insert(n.swiftDeps)}
    }
    return Array(swiftDepsOfNodes)
  }
// TODO: Incremental try not optional, also job >1 swiftDeps
  private func getJob(_ swiftDeps: String?) -> Job {
    // TODO: Incremental expats? nil? assert???
    guard let swiftDeps = swiftDeps else {fatalError( "Don't call me for nothing.")}
    guard let job = jobsBySwiftDeps[swiftDeps] else {fatalError("All jobs should be tracked.")}
    // TODO: Incremental centralize job invars
    assert(job.swiftDepsPaths.contains(swiftDeps),
           "jobsBySwiftDeps should be inverse of getSwiftDeps.")
    return job
  }
}

extension ModuleDependencyGraph {
  func traceArrival(at visitedNode: ModuleDepGraphNode) -> Int {
    guard var currentPath = currentPathIfTracing else {
      return 0
    }
    currentPath.append(visitedNode)
    currentPathIfTracing = currentPath
    recordDependencyPathToJob(currentPath, getJob(visitedNode.swiftDeps))
    return currentPath.count
  }

  func recordDependencyPathToJob(
    _ pathToJob: [ModuleDepGraphNode],
    _ dependentJob: Job)
  {
    _ = dependencyPathsToJobs.addValue(pathToJob, forKey: dependentJob)
  }

  func traceDeparture(_ pathLengthAfterArrival: Int) {
    guard var currentPath = currentPathIfTracing else { return }
    assert(pathLengthAfterArrival == currentPath.count,
           "Path must be maintained throughout recursive visits.")
    currentPath.removeLast()
    currentPathIfTracing = currentPath
  }
}


extension Job {
  @_spi(Testing) public var swiftDepsPaths: [String] {
    outputs.compactMap {$0.type != .swiftDeps ? nil : $0.file.name }
  }
}

fileprivate extension DependencyKey {
  init(interfaceForSourceFile swiftDeps: String) {
    self.init(aspect: .interface,
              designator: .sourceFileProvide(name: swiftDeps))
  }

  init(interfaceForExternalDepend externalSwiftDeps: String ) {
    self.init(aspect: .interface,
              designator: .externalDepend(name: externalSwiftDeps))
  }

}
