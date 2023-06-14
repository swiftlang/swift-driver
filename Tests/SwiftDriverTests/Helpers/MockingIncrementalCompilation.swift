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
import XCTest

// MARK: - utilities for unit testing
extension ModuleDependencyGraph {
  func haveAnyNodesBeenTraversed(inMock i: Int) -> Bool {
    blockingConcurrentAccessOrMutation {
      let dependencySource = DependencySource(
        SwiftSourceFile(mock: i),
        internedStringTable)
      // optimization
      if let fileNode = nodeFinder.findFileInterfaceNode(forMock: dependencySource),
         fileNode.isTraced {
        return true
      }
      if let nodes = nodeFinder.findNodes(for: .known(dependencySource))?.values,
         nodes.contains(where: {$0.isTraced}) {
        return true
      }
      return false
    }
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

extension DependencySource {
  var sourceFileProvideNameForMockDependencySource: String {
    typedFile.file.name
  }

  var interfaceHashForMockDependencySource: String {
    file.name
  }

  fileprivate  var sourceFileProvidesNameForMocking: InternedString {
    // Only when mocking are these two guaranteed to be the same
    internedFileName
  }
}

extension SwiftSourceFile {
  init(mock i: Int) {
    self.init(try! VirtualPath.intern(path: String(i) + "." + FileType.swift.rawValue))
  }
}

extension SwiftSourceFile {
  var mockID: Int {
    Int(typedFile.file.basenameWithoutExt)!
  }
}

extension ModuleDependencyGraph.NodeFinder {
  func findFileInterfaceNode(
    forMock dependencySource: DependencySource
  ) -> Graph.Node?  {
    let fileKey = DependencyKey(fileKeyForMockDependencySource: dependencySource)
    return findNode((.known(dependencySource), fileKey))
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

extension BuildRecordInfo {
  static func mock(
    diagnosticEngine: DiagnosticsEngine,
    outputFileMap: OutputFileMap,
    compilerVersion: String
  ) -> Self {
    self.init(
      buildRecordPath: try! VirtualPath(path: "no-build-record"),
      fileSystem: localFileSystem,
      currentArgsHash: "",
      actualSwiftVersion: compilerVersion,
      timeBeforeFirstJob: .now(),
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
    // Must set input files in order to avoid graph deserialization from culling
    let inputFiles = outputFileMap.entries.keys
      .filter {VirtualPath.lookup($0).extension == FileType.swift.rawValue }
      .map {TypedVirtualPath(file: $0, type: .swift)}
    let buildRecord = BuildRecordInfo.mock(
      diagnosticEngine: diagnosticEngine,
      outputFileMap: outputFileMap,
      compilerVersion: "for-testing")
    return Self(options, outputFileMap,
                buildRecord,
                nil, inputFiles, fileSystem,
                diagnosticEngine)
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
    .createForBuildingFromSwiftDeps(info.buildRecordInfo.buildRecord([], []), info)
  }
}


extension OutputFileMap {
  static func mock(maxIndex: Int) -> Self {
    OutputFileMap(entries: (0...maxIndex) .reduce(into: [:]) {
      entries, index in
      let inputHandle = SwiftSourceFile(mock: index).fileHandle
      let swiftDepsHandle = SwiftSourceFile(mock: index).fileHandle
      entries[inputHandle] = [.swiftDeps: swiftDepsHandle]
    })
  }
}
