//===---------- DepGraphIntegrator.swift ----------------------------------===//
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

// MARK: - building or updating
@_spi(Testing) public struct DepGraphIntegrator {
  // nil means there was an error
  @_spi(Testing) public  typealias Changes = Set<ModuleDepGraphNode>?

  let source: SourceFileDependencyGraph
  let swiftDeps: String
  let destination: ModuleDependencyGraph

  // When done, changeDependencyKeys contains a list of keys that changed
  // as a result of this integration.
  // Or if the integration failed, None.
  var changedNodes = Set<ModuleDepGraphNode>()
  var disappearedNodes = [DependencyKey: ModuleDepGraphNode]()

  init(source: SourceFileDependencyGraph,
       swiftDeps: String,
       destination: ModuleDependencyGraph)
  {
    self.source = source
    self.swiftDeps = swiftDeps
    self.destination = destination
  }
}

// MARK: - integrate a Job
extension DepGraphIntegrator {
  static func integrate(job: Job, into destination: ModuleDependencyGraph,
                        diagnosticEngine: DiagnosticsEngine) -> Changes {
    destination.jobTracker.registerJob(job)
    let graphsAndDeps = getSourceFileDependencyGraphs(job: job, diagnosticEngine: diagnosticEngine)

    let goodGraphsAndDeps = graphsAndDeps
      .compactMap {gd in gd.graph.map {(graph: $0, swiftDeps: gd.swiftDeps)}}

    let changedNodes = goodGraphsAndDeps
      .flatMap {
        integrate(from: $0.graph, swiftDeps: $0.swiftDeps, into: destination)
      }

    let hadError = graphsAndDeps.count != goodGraphsAndDeps.count

    return hadError ? nil : Set(changedNodes)
  }

 /// nil graph for error
  private static func getSourceFileDependencyGraphs(job: Job, diagnosticEngine: DiagnosticsEngine)
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
}

// MARK: - integrate a graph

extension DepGraphIntegrator {
  /// Integrate a SourceFileDepGraph into the receiver.
  /// Integration happens when the driver needs to read SourceFileDepGraph.
  /// Returns changed nodes
  @_spi(Testing) static public func integrate(
    from g: SourceFileDependencyGraph,
    swiftDeps: String,
    into destination: ModuleDependencyGraph)
  ->  Set<ModuleDepGraphNode>
  {
    var integrator = Self(source: g,
                            swiftDeps: swiftDeps,
                            destination: destination)
    integrator.integrate()

    if destination.verifyDependencyGraphAfterEveryImport {
      integrator.verifyAfterImporting()
    }
    if destination.emitDependencyDotFileAfterEveryImport {
      destination.emitDotFile(g, swiftDeps)
    }
    return integrator.changedNodes
  }


  private mutating func integrate() {
    disappearedNodes = destination.nodeFinder.findNodes(for: swiftDeps) ?? [:]

    source.forEachNode {integrate(oneNode: $0) }
    for (_, node) in disappearedNodes {
      changedNodes.insert(node)
      destination.nodeFinder.remove(node)
    }
    ModuleDepGraphTracer.ensureChangedNodesAreRetraced(changedNodes)
  }
}

// MARK: - integrate a node
extension DepGraphIntegrator {
  private mutating func integrate(oneNode integrand: SourceFileDependencyGraph.Node)
  {
    let key = integrand.key
    let preexistingMatch = PreexistingMatch(
      matches: destination.nodeFinder.findNodes(for: key),
      integrand: integrand,
      swiftDeps: swiftDeps)

    if case let .here(node) = preexistingMatch {
      // Node was and still is. Do not remove it.
      disappearedNodes.removeValue(forKey: node.dependencyKey)
    }

    guard integrand.isProvides else {
      // depends are captured by recordWhatIsDependendedUpon below
      return
    }

    let (hasChange, integratedNode) =
      integrate(integrand, reconcilingWith: preexistingMatch)

    let hasNewExternalDependency = recordWhatIsDependendedUpon(
      integrand, integratedNode)

    if hasChange || hasNewExternalDependency {
      changedNodes.insert(integratedNode)
    }
  }

  private func integrate(
      _ integrand: SourceFileDependencyGraph.Node,
      reconcilingWith preexistingMatch: PreexistingMatch
    )
  -> (foundChange: Bool, node: ModuleDepGraphNode)
  {
    switch preexistingMatch {
      case .none:
        /// Came from nowhere. (Goes to nowhere case is handled by dissapearedNodes.)
        return (true, integrateANewDef(integrand))

      case .here(let n):
        return (
          foundChange: n.integrateFingerprintFrom(integrand),
          node: n)

      case .nowhere(let n):
        // Some other file depended on this, but didn't know where it was.
        destination.nodeFinder.move(n, toDifferentFile: swiftDeps)
        _ = n.integrateFingerprintFrom(integrand)
        return (foundChange: true, n) // New decl, assume changed

      case .elsewhere:
        // new node, same base name
        return (foundChange: true, integrateANewDef(integrand))
    }
  }

  private func integrateANewDef(_ integrand: SourceFileDependencyGraph.Node)
  -> ModuleDepGraphNode
  {
    precondition(integrand.isProvides, "Dependencies are arcs in the module graph")
    let newNode = ModuleDepGraphNode(
      key: integrand.key,
      fingerprint: integrand.fingerprint,
      swiftDeps: swiftDeps)
    let oldNode = destination.nodeFinder.insert(newNode, isUsed: false)
    assert(oldNode == nil, "Should be new!")
    return newNode
  }

  /// Return true for new external dependency
  func recordWhatIsDependendedUpon(
    _ sourceFileUseNode: SourceFileDependencyGraph.Node,
    _ moduleUseNode: ModuleDepGraphNode)
  -> Bool {
    var useHasNewExternalDependency = false
    source.forEachDefDependedUpon(by: sourceFileUseNode) {
      def in
      let isNewUse = destination.nodeFinder.record(def: def.key, use: moduleUseNode)
      if case let .externalDepend(name: externalSwiftDeps) = def.key.designator, isNewUse {
        destination.externalDependencies.insert(externalSwiftDeps)
        useHasNewExternalDependency = true
      }
    }
    return useHasNewExternalDependency
  }
}

// MARK: - verification
extension DepGraphIntegrator {
  @discardableResult
  func verifyAfterImporting()
  -> Bool {
    guard let nodesInFile = destination.nodeFinder.findNodes(for: swiftDeps),
          !nodesInFile.isEmpty
    else {
      fatalError("Just imported \(swiftDeps), should have nodes")
    }
    return destination.verifyGraph()
  }
}

// MARK: - preexisting match

private extension DepGraphIntegrator {
  enum PreexistingMatch {
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

    init( matches: [String?: ModuleDepGraphNode]?,
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
      if let preexistingMatchInPlace = matches[swiftDeps], integrand.isProvides {
        self = .here(preexistingMatchInPlace)
        return
      }
      self = matches.first.map {.elsewhere($0.value)} ?? .none
    }
  }

}
