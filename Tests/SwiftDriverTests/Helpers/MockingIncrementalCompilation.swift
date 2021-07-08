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
import TSCUtility
import Foundation
import XCTest

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

extension Version {
  var withAlteredMinor: Self {
    Self(major, minor + 1, patch)
  }
}

// MARK: - mocking

extension TypedVirtualPath {
  init(mockInput i: Int) {
    self.init(file: try! VirtualPath.intern(path: "\(i).swift"), type: .swift)
  }
}

extension DependencySource {
  init(mock i: Int) {
    self.init(try! VirtualPath.intern(path: String(i) + "." + FileType.swift.rawValue))!
  }

  var sourceFileProvideNameForMockDependencySource: String {
    file.name
  }

  var interfaceHashForMockDependencySource: String {
    file.name
  }
}

extension TypedVirtualPath {
  var mockID: Int {
    Int(file.basenameWithoutExt)!
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

extension IncrementalCompilationState.IncrementalDependencyAndInputSetup {
  static func mock(
    options: IncrementalCompilationState.Options = [.verifyDependencyGraphAfterEveryImport],
    outputFileMap: OutputFileMap,
    fileSystem: FileSystem = localFileSystem,
    diagnosticEngine: DiagnosticsEngine = DiagnosticsEngine()
  ) -> Self {
    let diagnosticsEngine = DiagnosticsEngine()
    // Must set input files in order to avoid graph deserialization from culling
    let inputFiles = outputFileMap.entries.keys
      .filter {VirtualPath.lookup($0).extension == FileType.swift.rawValue }
      .map {TypedVirtualPath(file: $0, type: .swift)}
     return Self(options, outputFileMap,
                BuildRecordInfo.mock(diagnosticsEngine, outputFileMap),
                nil, nil, inputFiles, fileSystem,
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

// MARK: - Mocking up a ModuleDependencyGraph
protocol ModuleDependencyGraphMocker {
  static var mockGraphCreator: MockModuleDependencyGraphCreator {get}
}

struct MockModuleDependencyGraphCreator {
  let maxIndex: Int
  let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup

  /// maxIndex must be larger than any index used
  init(maxIndex: Int) {
    let outputFileMap = OutputFileMap.mock(maxIndex: maxIndex)
    self.info = IncrementalCompilationState.IncrementalDependencyAndInputSetup
      .mock(outputFileMap: outputFileMap)
    self.maxIndex = maxIndex
  }

  func mockUpAGraph() -> ModuleDependencyGraph {
    ModuleDependencyGraph(info, .buildingFromSwiftDeps)
  }
}


extension OutputFileMap {
  static func mock(maxIndex: Int) -> Self {
    OutputFileMap( entries: (0...maxIndex) .reduce(into: [:]) {
      entries, index in
      let inputHandle = TypedVirtualPath(mockInput: index).file.intern()
      let swiftDepsHandle = DependencySource(mock: index).file.intern()
      entries[inputHandle] = [.swiftDeps: swiftDepsHandle]
    }
    )
  }
}
