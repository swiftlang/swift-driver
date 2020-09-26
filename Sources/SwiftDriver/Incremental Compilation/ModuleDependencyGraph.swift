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


@_spi(Testing) public final class ModuleDependencyGraph {

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
  @_spi(Testing) public private(set)var usesByDef: [DependencyKey: Set<ModuleDepGraphNode>] = [:]

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
  private var dependencyPathsToJobs = [Job: Set<[ModuleDepGraphNode]>]()

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
  public typealias Changes = Set<ModuleDepGraphNode>?

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
    var disappearedNodes: [DependencyKey: ModuleDepGraphNode] = nodeMap[swiftDeps] ?? [:]

    // When done, changeDependencyKeys contains a list of keys that changed
    // as a result of this integration.
    // Or if the integration failed, None.
    var changedNodes = Set<ModuleDepGraphNode>()

    g.forEachNode {
      integrand in
      let key = integrand.key
      let preexistingMatch = PreexistingNode(matches: nodeMap[integrand.key], integrand: integrand, swiftDeps: swiftDeps)
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
      removeValue(node)
    }

    changedNodes.forEach {$0.clearHasBeenTraced()}

    if verifyDependencyGraphAfterEveryImport {
      verifyAfterIntegration(g, swiftDeps, changedNodes)
    }
    if emitDependencyDotFileAfterEveryImport {
      emitDotFile(g, swiftDeps)
    }

    return changedNodes
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
        return (true, integrateByCreatingANewNode(integrand, swiftDeps))

      case .here(let n):
        return (
          foundChange: n.integrateFingerprintFrom(integrand),
          node: n)

      case .nowhere(let n):
        // Some other file depended on this, but didn't know where it was.
        move(node: n, toDifferentFile: swiftDeps)
        _ = n.integrateFingerprintFrom(integrand)
        return (foundChange: true, n) // New decl, assume changed

      case .elsewhere:
        // new node, same base name
        return (foundChange: true,
                integrateByCreatingANewNode(integrand, swiftDeps)
        )
    }
  }

  func recordWhatUseDependsUpon(
    _ g: SourceFileDependencyGraph,
    _ sourceFileUseNode: SourceFileDependencyGraph.Node,
    _ moduleUseNode: ModuleDepGraphNode)
  -> Bool {
    var useHasNewExternalDependency = false
    g.forEachDefDependedUpon(by: sourceFileUseNode) {
      def in
      var inner = usesByDef[def.key] ?? Set<ModuleDepGraphNode>()
      let isNewUse = inner.insert(moduleUseNode).inserted
      usesByDef.updateValue(inner, forKey: def.key)
      if isNewUse && def.key.kind == .externalDepend {
        let externalSwiftDeps = def.key.name
        externalDependencies.insert(externalSwiftDeps)
        useHasNewExternalDependency = true
      }
    }
    return useHasNewExternalDependency
  }

  private func integrateByCreatingANewNode(
    _ integrand: SourceFileDependencyGraph.Node,
    _ swiftDeps: String)
  -> ModuleDepGraphNode
  {
    assert(integrand.isProvides, "Dependencies are arcs in the module graph")
    let newNode = ModuleDepGraphNode(
      key: integrand.key,
      fingerprint: integrand.fingerprint,
      swiftDeps: swiftDeps)
    addToMap(newNode)
    return newNode
  }

  /// When integrating a SourceFileDepGraph, there might be a node representing
  /// a Decl that had previously been read as an expat, that is a node
  /// representing a Decl in no known file (to that point). (Recall the the
  /// Frontend processes name lookups as dependencies, but does not record in
  /// which file the name was found.) In such a case, it is necessary to move
  /// the node to the proper collection.
   private func move(node: ModuleDepGraphNode, toDifferentFile newFile: String) {
    removeNodeFromMap(node)
    node.swiftDeps = newFile
    addToMap(node)
  }


  private func removeValue(_ node: ModuleDepGraphNode) {
    removeNodeFromMap(node)
    removeUsesOfNode(node)
    assert(verifyNodeIsNotInGraph(node))
  }

  private func removeUsesOfNode(_ node: ModuleDepGraphNode) {
    let kvs = usesByDef.map {
      kv -> (DependencyKey, Set<ModuleDepGraphNode>) in
      let key = kv.key
      var nodes = kv.value
      nodes.remove(node)
      return (key, nodes)
    }
    usesByDef = Dictionary(uniqueKeysWithValues: kvs)
  }

  private func removeNodeFromMap(_ nodeToErase: ModuleDepGraphNode)
  {
    let nodeActuallyErased = nodeMap.removeValue(forKey: nodeToErase.nodeMapKey)
    assert(
        nodeToErase == nodeActuallyErased,
        "Node found from key must be same as node holding key.")
  }

  private func addToMap(_ n: ModuleDepGraphNode) {
    _ = nodeMap.updateValue(n, forKey: (n.nodeMapKey))
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




//==============================================================================
// MARK: Nodes
//==============================================================================




/// TODO: Incremental  privatize
@_spi(Testing) public final class ModuleDepGraphNode {
  /// Def->use arcs go by DependencyKey. There may be >1 node for a given key.
  let key: DependencyKey

  /// The frontend records in the fingerprint, all of the information about an
  /// entity, such that any uses need be rebuilt only if the fingerprint
  /// changes.
  /// When the driver reloads a dependency graph (after a frontend job has run),
  /// it can use the fingerprint to determine if the entity has changed and thus
  /// if uses need to be recompiled.
  ///
  /// However, at present, the frontend does not record this information for
  /// every Decl; it only records it for the source-file-as-a-whole in the
  /// interface hash. The inteface hash is a product of all the tokens that are
  /// not inside of function bodies. Thus, if there is no fingerprint, when the
  /// frontend creates an interface node,
  /// it adds a dependency to it from the implementation source file node (which
  /// has the intefaceHash as its fingerprint).
  var fingerprint: String?


    /// The swiftDeps file that holds this entity iff this is a provides node.
    /// If more than one source file has the same DependencyKey, then there
    /// will be one node for each in the driver, distinguished by this field.
  var swiftDeps: String?

  /// When finding transitive dependents, this node has been traversed.
  var hasBeenTracedAsADependent = false

  init(key: DependencyKey, fingerprint: String?, swiftDeps: String?) {
    self.key = key
    self.fingerprint = fingerprint
    self.swiftDeps = swiftDeps
  }

  var hasBeenTraced: Bool { hasBeenTracedAsADependent }
  func setHasBeenTraced() { hasBeenTracedAsADependent = true }
  func clearHasBeenTraced() { hasBeenTracedAsADependent = false }

    /// Integrate \p integrand's fingerprint into \p dn.
    /// \returns true if there was a change requiring recompilation.
  func integrateFingerprintFrom(_ integrand: SourceFileDependencyGraph.Node) -> Bool {
    if fingerprint == integrand.fingerprint {
        return false
      }
    fingerprint = integrand.fingerprint
    return true
    }


    /// Nodes can move from file to file when the driver reads the result of a
    /// compilation.
  func setSwiftDeps(s: String?) { swiftDeps = s }

  var isProvides: Bool {swiftDeps != nil}

    /// Return true if this node describes a definition for which the job is known
  var isDefinedInAKnownFile: Bool { isProvides }

  static let expatSwiftDeps = ""

  var nodeMapKey: (String, DependencyKey) {
    (swiftDeps ?? Self.expatSwiftDeps, key)
  }

  var doesNodeProvideAnInterface: Bool {
    key.aspect == .interface && isProvides
    }

  func assertImplementationMustBeInAFile() -> Bool {
    assert(isDefinedInAKnownFile || key.aspect != .implementation,
             "Implementations must be in some file.")
      return true;
    }
}

extension ModuleDepGraphNode: Equatable, Hashable {
  /// Excludes hasBeenTraced...
  static public func == (lhs: ModuleDepGraphNode, rhs: ModuleDepGraphNode) -> Bool {
    lhs.key == rhs.key && lhs.fingerprint == rhs.fingerprint
      && lhs.swiftDeps == rhs.swiftDeps
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(key)
    hasher.combine(fingerprint)
    hasher.combine(swiftDeps)
  }
}


extension ModuleDepGraphNode: CustomStringConvertible {
  public var description: String {
    "\(key)\( swiftDeps.map {" \($0)"} ?? "" )"
  }
}

private extension ModuleDependencyGraph {
  @discardableResult
  func verifyNodeIsNotInGraph(_ node: ModuleDepGraphNode) -> Bool {
    assert(nodeMap[node.nodeMapKey] == nil)
    return true
  }
  @discardableResult
  func verifyAfterIntegration(_ sfg: SourceFileDependencyGraph,
                              _ swiftDeps: String,
                              _ changedNodes: Set<ModuleDepGraphNode>)
  -> Bool {
    assert(!nodeMap[swiftDeps]!.isEmpty)
    return verifyGraph()
  }
  @discardableResult
  func verifyGraph() -> Bool {
    _ = nodeMap.verify {
      swiftDeps, key, node, _ in
      assert(nodeMap[(swiftDeps, key)] == node)
    }

    for (_, nodes) in usesByDef {
      for node in nodes {
        assert(nodeMap[node.nodeMapKey] == node)
      }
    }
    return true
  }
}

extension ModuleDependencyGraph {
  func emitDotFile(_ g: SourceFileDependencyGraph, _ swiftDeps: String) {
    // TODO: Incremental
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
    let fileKey = DependencyKey(kind: .sourceFileProvide,
                                aspect: .interface,
                                context: "",
                                name: swiftDeps)
    if let fileNode = nodeMap[(swiftDeps, fileKey)], fileNode.hasBeenTraced {
      return true
    }

    var result = false;
    forEachNodeInJob(swiftDeps) {
      result = result || $0.hasBeenTraced
    }
    return result;
  }

  private func forEachNodeInJob(_ swiftDeps: String, _ fn: (ModuleDepGraphNode) -> Void) {
    (nodeMap[swiftDeps] ?? [:]).values.forEach(fn)
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
    let key = DependencyKey(kind: .externalDepend,
                            aspect: .interface,
                            context: "",
                            name: externalSwiftDeps)
    for useNode in usesByDef[key] ?? Set() where !useNode.hasBeenTraced {
      assert(useNode.swiftDeps != nil, "only a def can use something")
      useNode.swiftDeps .map {fn(getJob($0))}
    }
  }

  private func findPreviouslyUntracedDependents(
    of definition: ModuleDepGraphNode,
    into found: inout [ModuleDepGraphNode]
  ) {
    guard !definition.hasBeenTraced else { return }
    definition.setHasBeenTraced();

    found.append(definition)

    // If this use also provides something, follow it
    // else no need to look for uses; provides nothing
    guard definition.isProvides else { return }

    let pathLengthAfterArrival = traceArrival(at: definition);

    // If this use also provides something, follow it
    for use in usesByDef[definition.key] ?? [] {
      findPreviouslyUntracedDependents(of: use, into: &found)
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
      if let swiftDeps = n.swiftDeps {swiftDepsOfNodes.insert(swiftDeps)}
    }
    return Array(swiftDepsOfNodes)
  }
// TODO: Incremental try not optional, also job >1 swiftDeps
  private func getJob(_ swiftDeps: String?) -> Job {
    guard let swiftDeps = swiftDeps else {fatalError( "Don't call me for expats.")}
    guard let job = jobsBySwiftDeps[swiftDeps] else {fatalError("All jobs should be tracked.")}
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
    let visitedSwiftDepsIfAny = visitedNode.swiftDeps
    recordDependencyPathToJob(currentPath, getJob(visitedSwiftDepsIfAny))
    return currentPath.count
  }

  func recordDependencyPathToJob(
    _ pathToJob: [ModuleDepGraphNode],
    _ dependentJob: Job)
  {
  dependencyPathsToJobs.addValue(pathToJob, forKey: dependentJob)
  }

  func traceDeparture(_ pathLengthAfterArrival: Int) {
    guard var currentPath = currentPathIfTracing else { return }
    assert(pathLengthAfterArrival == currentPath.count,
           "Path must be maintained throughout recursive visits.")
    currentPath.removeLast()
    currentPathIfTracing = currentPath
  }
}

fileprivate extension Dictionary {
  /// uniquing Bag behavior
  mutating func addValue<V: Hashable>(_ v: V, forKey key: Key)
  where Value == Set<V> {
    var inner = self[key] ?? Set<V>()
    inner.insert(v)
    updateValue(inner, forKey: key)
  }
}

extension Job {
  @_spi(Testing) public var swiftDepsPaths: [String] {
    outputs.compactMap {$0.type != .swiftDeps ? nil : $0.file.name }
  }
}
