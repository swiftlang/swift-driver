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

@_spi(Testing) import SwiftDriver
import TSCBasic
import Foundation

// MARK: - utilities for unit testing
extension ModuleDependencyGraph {
  func haveAnyNodesBeenTraversed(inMock i: Int) -> Bool {
    let dependencySource = DependencySource(mock: i)
    // optimization
    if let fileNode = nodeFinder.findFileInterfaceNode(forMock: dependencySource),
       fileNode.isTraced {
      return true
    }
    if let nodes = nodeFinder.findNodes(for: dependencySource)?.values,
       nodes.contains(where: {$0.isTraced}) {
      return true
    }
    return false
  }

  func setUntraced() {
    nodeFinder.forEachNode {
      $0.setUntraced()
    }
  }

  func ensureIsSerializable() {
    var nodeIDs = Set<Node>()
    nodeFinder.forEachNode { node in
      nodeIDs.insert(node)
    }
    for key in nodeFinder.usesByDef.keys {
      for use in nodeFinder.usesByDef[key, default: []] {
        XCTAssertTrue(nodeIDs.contains(use), "Node ID was not registered! \(use), \(String(describing: use.fingerprint))")
      }
    }
  }
}

// MARK: - mocking

extension TypedVirtualPath {
  init(mockInput i: Int) {
    self.init(file: try! VirtualPath(path: "\(i).swift"), type: .swift)
  }
}

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

extension BuildRecordInfo {
  static func mock(
    _ diagnosticEngine: DiagnosticsEngine,
    _ outputFileMap: OutputFileMap
    ) -> Self {
    self.init(
      buildRecordPath: try! VirtualPath(path: "no-build-record"),
      fileSystem: localFileSystem,
      currentArgsHash: "",
      actualSwiftVersion: "for-testing",
      timeBeforeFirstJob: Date(),
      diagnosticEngine: diagnosticEngine,
      compilationInputModificationDates: [:])
  }
}

extension IncrementalCompilationState.InitialStateComputer {
  static func mock(
    options: IncrementalCompilationState.Options = [.verifyDependencyGraphAfterEveryImport],
    diagnosticEngine: DiagnosticsEngine = DiagnosticsEngine(),
    fileSystem: FileSystem = localFileSystem) -> Self {
    let diagnosticsEngine = DiagnosticsEngine()
    let outputFileMap = OutputFileMap()
    return Self(options,
              JobsInPhases.none,
              outputFileMap,
              BuildRecordInfo.mock(diagnosticsEngine, outputFileMap),
              nil,
              nil,
              [],
              fileSystem,
              showJobLifecycle: false,
              diagnosticsEngine)
  }
}

func `is`<S: StringProtocol>(dotFileName a: S, lessThan b: S) -> Bool {
  let sequenceNumbers = [a, b].map { Int($0.split(separator: ".").dropLast().last!)! }
  return sequenceNumbers[0] < sequenceNumbers[1]
}

extension Collection where Element: StringProtocol {
  func sortedByDotFileSequenceNumbers() -> [Element] {
    sorted(by: `is`(dotFileName:lessThan:))
  }
}
