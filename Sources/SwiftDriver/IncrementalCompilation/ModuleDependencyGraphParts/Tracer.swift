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

import class TSCBasic.DiagnosticsEngine

extension ModuleDependencyGraph {

/// Trace dependencies through the graph
  struct Tracer {
    typealias Graph = ModuleDependencyGraph

    let startingPoints: DirectlyInvalidatedNodeSet
    let graph: ModuleDependencyGraph

    private(set) var tracedUses = TransitivelyInvalidatedNodeArray()

    /// Record the paths taking so that  -driver-show-incremental can explain why things are recompiled
    /// If tracing dependencies, holds a vector used to hold the current path
    /// def - use/def - use/def - ...
    private var currentPathIfTracing: [Node]?

    private let diagnosticEngine: DiagnosticsEngine
  }
}

// MARK:- Tracing
extension ModuleDependencyGraph.Tracer {

  /// Find all uses of `defs` that have not already been traced.
  ///
  /// - Parameters:
  ///   - defNodes: Nodes for changed declarations
  ///   - graph: The graph hosting the nodes
  ///   - diagnosticEngine: The complaint department
  /// - Returns: all uses of the changed nodes that have not already been traced. These represent
  /// heretofore-unschedule compilations that are now required.
  static func collectPreviouslyUntracedNodesUsing(
    defNodes: DirectlyInvalidatedNodeSet,
    in graph: ModuleDependencyGraph,
    diagnosticEngine: DiagnosticsEngine
  ) -> Self {
    var tracer = Self(collectingUsesOf: defNodes,
                      in: graph,
                      diagnosticEngine: diagnosticEngine)
    tracer.collectPreviouslyUntracedDependents()
    return tracer
  }

  private init(collectingUsesOf defs: DirectlyInvalidatedNodeSet,
               in graph: ModuleDependencyGraph,
               diagnosticEngine: DiagnosticsEngine) {
    self.graph = graph
    self.startingPoints = defs
    self.currentPathIfTracing = graph.info.reporter != nil ? [] : nil
    self.diagnosticEngine = diagnosticEngine
  }

  private mutating func collectPreviouslyUntracedDependents() {
    for n in startingPoints {
      collectNextPreviouslyUntracedDependent(of: n)
    }
  }

  private mutating func collectNextPreviouslyUntracedDependent(
    of definition: ModuleDependencyGraph.Node
  ) {
    guard definition.isUntraced else { return }
    definition.setTraced()

    tracedUses.append(definition)

    // If this node is merely used, but not defined anywhere, nothing else
    // can possibly depend upon it
    if case .unknown = definition.definitionLocation { return }

    let pathLengthAfterArrival = traceArrival(at: definition);

    // If this use also provides something, follow it
    for use in graph.nodeFinder.uses(of: definition) {
      collectNextPreviouslyUntracedDependent(of: use)
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

    printPath(currentPath)

    return currentPath.count
  }


  private mutating func traceDeparture(_ pathLengthAfterArrival: Int) {
    guard var currentPath = currentPathIfTracing else { return }
    assert(pathLengthAfterArrival == currentPath.count,
           "Path must be maintained throughout recursive visits.")
    currentPath.removeLast()
    currentPathIfTracing = currentPath
  }

  private func printPath(_ path: [Graph.Node]) {
    guard path.first?.definitionLocation != path.last?.definitionLocation
    else {
      return
    }
    graph.info.reporter?.report(
      [
        "Traced:",
        path.compactMap { node in
          guard case let .known(source) = node.definitionLocation else {
            return nil
          }
          return source.typedFile.type == .swift
          ? "\(node.key.description(in: graph)) in \(source.file.basename)"
          : "\(node.key.description(in: graph))"
        }
        .joined(separator: " -> ")
      ].joined(separator: " ")
    )
  }
}
