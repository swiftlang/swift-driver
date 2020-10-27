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
    private var currentPathIfTracing: [Node]?

    private let diagnosticEngine: DiagnosticsEngine
  }
}

// MARK:- Tracing
extension ModuleDependencyGraph.Tracer {

  /// Find all uses of `defs` that have not already been traced.
  /// (If already traced, jobs have already been scheduled.)
  @_spi(Testing) public static func findPreviouslyUntracedUsesOf<Nodes: Sequence> (
    defs: Nodes,
    in graph: ModuleDependencyGraph,
    diagnosticEngine: DiagnosticsEngine
  ) -> Self
  where Nodes.Element == ModuleDependencyGraph.Node
  {
    var tracer = Self(findingUsesOf: defs,
                      in: graph,
                      diagnosticEngine: diagnosticEngine)
    tracer.findPreviouslyUntracedDependents()
    return tracer
  }

  private init<Nodes: Sequence>(findingUsesOf defs: Nodes,
               in graph: ModuleDependencyGraph,
               diagnosticEngine: DiagnosticsEngine)
  where Nodes.Element == ModuleDependencyGraph.Node
  {
    self.graph = graph
    self.startingPoints = Array(defs)
    self.currentPathIfTracing = graph.traceDependencies ? [] : nil
    self.diagnosticEngine = diagnosticEngine
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
    guard path.first?.swiftDeps != path.last?.swiftDeps else {return}
    diagnosticEngine.emit(
      .remark(
        path
          .compactMap { node in
            node.swiftDeps
              .flatMap {graph.sourceSwiftDepsMap[$0] }
              .map (node.dependencyKey.descriptionForPath(from:))
          }
          .joined(separator: "->")
      )
    )
  }
}

fileprivate extension DependencyKey {
  func descriptionForPath(from sourceFile: TypedVirtualPath) -> String {
    "\(aspect) of \(designator.descriptionForPath(from: sourceFile))"
  }
}

fileprivate extension DependencyKey.Designator {
  func descriptionForPath(from sourceFile: TypedVirtualPath) -> String {
    switch self {
    case let .topLevel(name: name):
      return "top-level name \(name)"
    case let .nominal(context: context):
      return "type \(context)"
    case let .potentialMember(context: context):
      return "potential members of \(context)"
    case let .member(context: context, name: name):
      return "member \(name) of \(context)"
    case let .dynamicLookup(name: name):
      return "AnyObject member \(name)"
    case let .externalDepend(externalDependency):
      return "module \(externalDependency)"
    case let .sourceFileProvide(name: name):
      return (try? VirtualPath(path: name).basename) ?? name
    }
  }
}
