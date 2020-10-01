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


// MARK: - ModuleDependencyGraph

@_spi(Testing) public final class ModuleDependencyGraph {

  internal var nodesAndUses = NodesAndUses()

  // Supports requests from the driver to getExternalDependencies.
  @_spi(Testing) public internal(set) var externalDependencies = Set<String>()



  let verifyDependencyGraphAfterEveryImport: Bool
  let emitDependencyDotFileAfterEveryImport: Bool

  @_spi(Testing) public let diagnosticEngine: DiagnosticsEngine

  @_spi(Testing) public var jobTracker = JobTracker()


  public init(
    verifyDependencyGraphAfterEveryImport: Bool,
    emitDependencyDotFileAfterEveryImport: Bool,
    diagnosticEngine: DiagnosticsEngine)
  {
    self.verifyDependencyGraphAfterEveryImport = verifyDependencyGraphAfterEveryImport
    self.emitDependencyDotFileAfterEveryImport = emitDependencyDotFileAfterEveryImport
    self.diagnosticEngine = diagnosticEngine
  }
}

// MARK: - initial build only
extension ModuleDependencyGraph {
  static func buildInitialGraph(jobs: [Job],
                                verifyDependencyGraphAfterEveryImport: Bool,
                                emitDependencyDotFileAfterEveryImport: Bool,
                                diagnosticEngine: DiagnosticsEngine) -> Self {
    let r = Self(verifyDependencyGraphAfterEveryImport: verifyDependencyGraphAfterEveryImport,
                 emitDependencyDotFileAfterEveryImport: emitDependencyDotFileAfterEveryImport,
                 diagnosticEngine: diagnosticEngine)
    for job in jobs {
      _ = DepGraphIntegrator.integrate(job: job, into: r,
                                       diagnosticEngine: diagnosticEngine)
    }
    return r
  }
}

// MARK: - finding jobs
extension ModuleDependencyGraph {
  @_spi(Testing) public func findJobsToRecompileWhenWholeJobChanges(_ job: Job) -> [Job] {
    let allNodesInJob = findAllNodes(in: job)
    return findJobsToRecompileWhenNodesChange(allNodesInJob);
  }

  private func findAllNodes(in job: Job) -> [ModuleDepGraphNode] {
    job.swiftDepsPaths.flatMap(nodesIn(swiftDeps:))
  }
  
  @_spi(Testing) public func findJobsToRecompileWhenNodesChange(
    _ nodes: [ModuleDepGraphNode])
  -> [Job]
  {
    let affectedNodes = ModuleDepGraphTracer.findPreviouslyUntracedUsesOf(defs: nodes, in: self)
      .tracedUses
    return jobsContaining(affectedNodes)
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
      use, useSwiftDeps in
      if !use.hasBeenTraced {
        fn(jobTracker.getJob(useSwiftDeps))
      }
    }
  }


  private func jobsContaining<Nodes: Sequence>(_ nodes: Nodes) -> [Job]
  where Nodes.Element == ModuleDepGraphNode {
    computeSwiftDepsFromNodes(nodes).map(jobTracker.getJob)
  }




}


extension Job {
  @_spi(Testing) public var swiftDepsPaths: [String] {
    outputs.compactMap {$0.type != .swiftDeps ? nil : $0.file.name }
  }
}

// MARK: - finding nodes; swiftDeps
extension ModuleDependencyGraph {
  private func computeSwiftDepsFromNodes<Nodes: Sequence>(_ nodes: Nodes) -> [String]
  where Nodes.Element == ModuleDepGraphNode {
    var swiftDepsOfNodes = Set<String>()
    for n in nodes {
      if let swiftDeps = n.swiftDeps {
        swiftDepsOfNodes.insert(swiftDeps)
      }
    }
    return Array(swiftDepsOfNodes)
  }
}

// MARK: - purely for testing
extension ModuleDependencyGraph {
  /// Testing only
  @_spi(Testing) public func haveAnyNodesBeenTraversedIn(_ job: Job) -> Bool {
    for swiftDeps in job.swiftDepsPaths {
      // optimization
      if let fileNode = nodesAndUses.findFileInterfaceNode(forSwiftDeps: swiftDeps),
         fileNode.hasBeenTraced
      {
        return true
      }
      if  nodesIn(swiftDeps: swiftDeps).contains(where: {$0.hasBeenTraced}) {
        return true
      }
    }
    return false
  }
  
  private func nodesIn(swiftDeps: String) -> [ModuleDepGraphNode]
  {
    nodesAndUses.findNodes(for: swiftDeps)
      .map {Array($0.values)}
    ?? []
  }
}





// MARK: - verificaiton
extension ModuleDependencyGraph {
  @discardableResult
  func verifyGraph() -> Bool {
    nodesAndUses.verify()
  }
}


// MARK: - debugging
extension ModuleDependencyGraph {
  func emitDotFile(_ g: SourceFileDependencyGraph, _ swiftDeps: String) {
    // TODO: Incremental emitDotFIle
    fatalError("unimplmemented")
  }
}

// MARK: - key helpers

fileprivate extension DependencyKey {
  init(interfaceForExternalDepend externalSwiftDeps: String ) {
    self.init(aspect: .interface,
              designator: .externalDepend(name: externalSwiftDeps))
  }

}
