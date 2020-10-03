//===----------------------------- Tracer.swift ---------------------------===//
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

extension ModuleDependencyGraph {

/// Trace dependencies through the graph
  @_spi(Testing) public struct Tracer {
    @_spi(Testing) public typealias Graph = ModuleDependencyGraph

    let startingPoints: [Node]
    let graph: ModuleDependencyGraph

    @_spi(Testing) public private(set) var tracedUses: [Node] = []

    /// Record the paths taking so that  -driver-show-incremental can explain why things are recompiled
    /// If tracing dependencies, holds a vector used to hold the current path
    /// def - use/def - use/def - ...
    private var currentPathIfTracing: [Node]? = nil



    /// If tracing dependencies, holds the sequence of defs used to get to the job
    /// that is the key
    @_spi(Testing) public private(set) var dependencyPathsToJobs = Multidictionary<Job, [Node]>()
  }
}

// MARK:- Tracing
extension ModuleDependencyGraph.Tracer {
  @_spi(Testing) public static func findPreviouslyUntracedUsesOf(
    defs: [ModuleDependencyGraph.Node],
    in graph: ModuleDependencyGraph
  ) -> Self {
    var tracer = Self(findingUsesOf: defs, in: graph)
    tracer.findPreviouslyUntracedDependents()
    return tracer
  }
  
  private init(findingUsesOf defs: [ModuleDependencyGraph.Node],
               in graph: ModuleDependencyGraph) {
    self.graph = graph
    self.startingPoints = defs
  }
  
  private mutating func findPreviouslyUntracedDependents() {
    for n in startingPoints {
      findNextPreviouslyUntracedDependent(of: n)
    }
  }
  
  private mutating func findNextPreviouslyUntracedDependent(
    of definition: ModuleDependencyGraph.Node
  ) {
    guard graph.isUntraced(definition) else { return }
    graph.amTracing(definition)
    
    tracedUses.append(definition)
    
    // If this node is merely used, but not defined anywhere, nothing else
    // can possibly depend upon it.
    if definition.isExpat { return }
    
    let pathLengthAfterArrival = traceArrival(at: definition);
    
    // If this use also provides something, follow it
    graph.nodeFinder.forEachUse(of: definition.dependencyKey) { use, _ in
      findNextPreviouslyUntracedDependent(of: use)
    }
    traceDeparture(pathLengthAfterArrival);
  }
  
  private mutating func traceArrival(at visitedNode: ModuleDependencyGraph.Node
  ) -> Int {
    guard var currentPath = currentPathIfTracing else {
      return 0
    }
    currentPath.append(visitedNode)
    currentPathIfTracing = currentPath

    // TODO Incremental: type system should be telling use this is a provides node
    // and then it should always succeed
    if let swiftDeps = visitedNode.swiftDeps {
      recordDependencyPathToJob(currentPath,
                                graph.jobTracker.getJob(swiftDeps))
    }
    return currentPath.count
  }
  
  private mutating func recordDependencyPathToJob(
    _ pathToJob: [Graph.Node],
    _ dependentJob: Job)
  {
    _ = dependencyPathsToJobs.addValue(pathToJob, forKey: dependentJob)
  }
  
  private mutating func traceDeparture(_ pathLengthAfterArrival: Int) {
    guard var currentPath = currentPathIfTracing else { return }
    assert(pathLengthAfterArrival == currentPath.count,
           "Path must be maintained throughout recursive visits.")
    currentPath.removeLast()
    currentPathIfTracing = currentPath
  }
}
