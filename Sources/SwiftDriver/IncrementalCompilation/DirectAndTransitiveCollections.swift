//===------------------ DirectAndTransitiveCollections.swift --------------===//
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

// Use the type system to ensure that dependencies are transitively closed
// without doing too much work at the leaves of the call tree

public struct DirectlyInvalidatedNodes {
  typealias Node = ModuleDependencyGraph.Node
  var contents = Set<Node>()

  init(_ s: Set<Node> = Set()) {
    self.contents = s
  }

  init<Nodes: Sequence>(_ nodes: Nodes)
  where Nodes.Element == Node
  {
    self.init(Set(nodes))
  }

  mutating func insert(_ e: Node) {
    contents.insert(e)
  }
  mutating func formUnion(_ nodes: DirectlyInvalidatedNodes) {
    contents.formUnion(nodes.contents)
  }
}

//extension Sequence {
//  func reduce(into initialResult: DirectlyInvalidatedNodes,
//              _ updateAccumulatingResult: (inout: DirectlyInvalidatedNodes, Element) -> Void) {
//    var r = initialResult
//    reduce(into: r.contents, updateAccumulatingResult)
//    return r
//    }
//  }
//}
