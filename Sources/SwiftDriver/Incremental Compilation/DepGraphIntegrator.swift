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

// MARK: - state & creation

/// Integrates a \c SourceFileDependencyGraph into a \c ModuleDependencyGraph
/// The former comes from a frontend job, and the latter is used by the driver.
@_spi(Testing) public struct DepGraphIntegrator {
  @_spi(Testing) public  typealias Changes = Set<ModuleDepGraphNode>

  let source: SourceFileDependencyGraph
  let swiftDeps: String
  let destination: ModuleDependencyGraph

  /// When done, changedNodes contains a set of nodes that changed as a result of this integration.

  var changedNodes = Changes()
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
  private enum LoadedDependencyGraph {
    case success(SourceFileDependencyGraph, String)
    case failure(String)
  }

  /// returns nil means there was an error
  @_spi(Testing) public static func integrate(
    job: Job,
    into destination: ModuleDependencyGraph,
    diagnosticEngine: DiagnosticsEngine
  ) -> Changes? {
    destination.jobTracker.registerJob(job)
    let loadedGraphs = getSourceFileDependencyGraphs(job: job, diagnosticEngine: diagnosticEngine)

    var changedNodes = Changes()
    var hadError = false
    loadedGraphs.forEach {
      if case let .success(graph, swiftDeps) = $0 {
        integrate(from: graph, swiftDeps: swiftDeps, into: destination)
          .forEach {changedNodes.insert($0)}
      }
      else {
        hadError = true
      }
    }
    return hadError ? nil : Set(changedNodes)
  }

  /// Returns a nil graph if there's a error
  private static func getSourceFileDependencyGraphs(job: Job,
                                                    diagnosticEngine: DiagnosticsEngine
  ) -> [LoadedDependencyGraph] {
    let swiftDepsOutputs = job.outputs.filter {$0.type == .swiftDeps}
    return swiftDepsOutputs.map {
      do {
        return .success(
          try SourceFileDependencyGraph.read(from: $0),
          $0.file.name
        )
      }
      catch {
        diagnosticEngine.emit(
          .error_cannot_read_swiftdeps(file: $0, reason: error.localizedDescription)
        )
        return .failure($0.file.name)
      }
    }
  }
}

// MARK: - integrate a graph

extension DepGraphIntegrator {
  /// Integrate a SourceFileDepGraph into the receiver.
  /// Integration happens when the driver needs to read SourceFileDepGraph.
  /// Returns changed nodes
  @_spi(Testing) public static func integrate(
    from g: SourceFileDependencyGraph,
    swiftDeps: String,
    into destination: ModuleDependencyGraph
  ) ->  Changes {
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

    source.forEachNode { integrate(oneNode: $0) }
    for (_, node) in disappearedNodes {
      changedNodes.insert(node)
      destination.nodeFinder.remove(node)
    }
    destination.ensureGraphWillRetrace(changedNodes)
  }
}

// MARK: - integrate a node
extension DepGraphIntegrator {
  private mutating func integrate(
    oneNode integrand: SourceFileDependencyGraph.Node)
  {
    guard integrand.isProvides else {
      // depends are captured by recordWhatIsDependedUpon below
      return
    }

    let preexistingMatchHereOrExpat =
      destination.nodeFinder.findNodes(for: integrand.key)
      .flatMap { (matches: [String?: ModuleDepGraphNode]) -> ModuleDepGraphNode? in
        if let matchHere = matches[swiftDeps] {
          // Node was and still is. Do not remove it.
          disappearedNodes.removeValue(forKey: matchHere.dependencyKey)
          return matchHere
        }
        if let expat = matches[nil] {
          assert(matches.count == 1,
                 "If an expat exists, then must not be any matches in other files")
          return expat
        }
        return nil
      }

    let (foundChange: foundChange, integratedNode: integratedNode) =
      integrate(integrand, reconcilingWith: preexistingMatchHereOrExpat)

    let hasNewExternalDependency = recordWhatIsDependedUpon(
      integrand, integratedNode)

    if foundChange || hasNewExternalDependency {
      changedNodes.insert(integratedNode)
    }
  }

  private func integrate(
    _ integrand: SourceFileDependencyGraph.Node,
    reconcilingWith preexistingMatch: ModuleDepGraphNode?
  ) -> (foundChange: Bool, integratedNode: ModuleDepGraphNode) {
    precondition(
      preexistingMatch.flatMap {
        $0.swiftDeps.map {$0 == swiftDeps} ?? true}
        ?? true,
      "preexistingMatch must be nil or here or expat"
    )
    switch preexistingMatch {
    case nil:
      // no match, or match for a different decl
      // create a new node
      return (foundChange: true, integratedNode: integrateNewDef(integrand))

    case let node?
          where node.swiftDeps == swiftDeps
          && node.fingerprint == integrand.fingerprint:
      // no change
      return (foundChange: false, integratedNode: node)

    case let node?:
      let integratedNode = destination.nodeFinder
        .replace(node,
                 newSwiftDeps: swiftDeps,
                 newFingerprint: integrand.fingerprint)
      return ( foundChange: true, integratedNode: integratedNode )
    }
  }

  private func integrateNewDef(_ integrand: SourceFileDependencyGraph.Node
  ) -> ModuleDepGraphNode {
    precondition(integrand.isProvides, "Dependencies are arcs in the module graph")
    let newNode = ModuleDepGraphNode(
      key: integrand.key,
      fingerprint: integrand.fingerprint,
      swiftDeps: swiftDeps)
    let oldNode = destination.nodeFinder.insert(newNode)
    assert(oldNode == nil, "Should be new!")
    return newNode
  }

  /// Return true for new external dependency
  func recordWhatIsDependedUpon(
    _ sourceFileUseNode: SourceFileDependencyGraph.Node,
    _ moduleUseNode: ModuleDepGraphNode) -> Bool {
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
  func verifyAfterImporting() -> Bool {
    guard let nodesInFile = destination.nodeFinder.findNodes(for: swiftDeps),
          !nodesInFile.isEmpty
    else {
      fatalError("Just imported \(swiftDeps), should have nodes")
    }
    return destination.verifyGraph()
  }
}
