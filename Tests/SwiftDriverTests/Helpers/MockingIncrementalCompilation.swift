//===------------- MockingIncrementalCompilation.swift --------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import SwiftDriver

// MARK: - utilities for unit testing
extension ModuleDependencyGraph {
  func haveAnyNodesBeenTraversed(inMock i: Int) -> Bool {
    let dependencySource = DependencySource(mock: i)
    // optimization
    if let fileNode = nodeFinder.findFileInterfaceNode(forMock: dependencySource),
       isTraced(fileNode) {
      return true
    }
    if let nodes = nodeFinder.findNodes(for: dependencySource)?.values,
       nodes.contains(where: isTraced) {
      return true
    }
    return false
  }
}

// MARK: - mocking
extension DependencySource {
  init(mock i: Int) {
    self.init(try! VirtualPath(path: String(i) + "." + FileType.swiftDeps.rawValue))!
  }

  var mockID: Int {
    Int(file.basenameWithoutExt)!
  }

  var sourceFileProvideNameForMockDependencySource: String {
    file.name
  }

  var interfaceHashForMockDependencySource: String {
    file.name
  }
}

extension ModuleDependencyGraph.NodeFinder {
  func findFileInterfaceNode(
    forMock dependencySource: DependencySource
  ) -> Graph.Node?  {
    let fileKey = DependencyKey(fileKeyForMockDependencySource: dependencySource)
    return findNode((dependencySource, fileKey))
  }
}

fileprivate extension DependencyKey {
  init(fileKeyForMockDependencySource dependencySource: DependencySource) {
    self.init(aspect: .interface,
              designator:
                .sourceFileProvide(name: dependencySource.sourceFileProvidesNameForMocking)
    )
  }
}

fileprivate extension DependencySource {
  var sourceFileProvidesNameForMocking: String {
    // Only when mocking are these two guaranteed to be the same
    file.name
  }
}
