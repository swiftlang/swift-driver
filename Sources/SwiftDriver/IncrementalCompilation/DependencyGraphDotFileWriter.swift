//===---------- DependencyGraphDotFileWriter.swift - Swift GraphViz -------===//
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

import protocol TSCBasic.WritableByteStream

// MARK: - Asking to write dot files / interface
public struct DependencyGraphDotFileWriter {
  /// Holds file-system and options
  private let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup

  private var versionNumber = 0

  init(_ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup) {
    self.info = info
  }

  mutating func write(_ sfdg: SourceFileDependencyGraph, for file: TypedVirtualPath,
                      internedStringTable: InternedStringTable) {
    let basename = file.file.basename
    write(sfdg, basename: basename, internedStringTable: internedStringTable)
  }

  mutating func write(_ mdg: ModuleDependencyGraph) {
    write(mdg, basename: Self.moduleDependencyGraphBasename,
          internedStringTable: mdg.internedStringTable)
  }

  @_spi(Testing) public static let moduleDependencyGraphBasename = "moduleDependencyGraph"
}

// MARK: Asking to write dot files / implementation
fileprivate extension DependencyGraphDotFileWriter {
  mutating func write<Graph: ExportableGraph>(
    _ graph: Graph,
    basename: String,
    internedStringTable: InternedStringTable
  ) {
    let path = dotFilePath(for: basename)
    try! info.fileSystem.writeFileContents(path) { stream in
      var s = DOTDependencyGraphSerializer<Graph>(
        graph,
        graphID: basename,
        stream,
        includeExternals: info.dependencyDotFilesIncludeExternals,
        includeAPINotes: info.dependencyDotFilesIncludeAPINotes,
        internedStringTable: internedStringTable)
      s.emit()
    }
  }

  mutating func dotFilePath(for basename: String) -> VirtualPath {
    let nextVersionNumber = versionNumber
    // Update the version number so that successive saved dot files for the graph
    // (for instance the ModuleDependencyGraph) can be examined in order to see
    // how an import changed the graph.
    versionNumber += 1
    return info.buildRecordInfo.dotFileDirectory
      .appending(component: "\(basename).\(nextVersionNumber).dot")
  }
}

// MARK: - Making dependency graphs exportable
fileprivate protocol ExportableGraph {
  associatedtype Node: ExportableNode
  func forEachExportableNode(_ visit: (Node) -> Void)
  func forEachExportableArc(_ visit: (Node, Node) -> Void)
}

extension SourceFileDependencyGraph: ExportableGraph {
  fileprivate func forEachExportableNode<Node: ExportableNode>(_ visit: (Node) -> Void) {
    forEachNode { visit($0 as! Node) }
  }
  fileprivate func forEachExportableArc<Node: ExportableNode>(_ visit: (Node, Node) -> Void) {
    forEachNode { use in
      forEachDefDependedUpon(by: use) { def in
        visit(def as! Node, use as! Node)
      }
    }
  }
}

extension ModuleDependencyGraph: ExportableGraph {
  fileprivate var graphID: String {
    return "ModuleDependencyGraph"
  }
  fileprivate func forEachExportableNode<Node: ExportableNode>(
    _ visit: (Node) -> Void) {
    nodeFinder.forEachNode { visit($0 as! Node) }
  }
  fileprivate func forEachExportableArc<Node: ExportableNode>(
    _ visit: (Node, Node) -> Void
  ) {
    nodeFinder.forEachNode {def in
      for use in nodeFinder.uses(of: def) {
        visit(def as! Node, use as! Node)
      }
    }
  }
}

// MARK: - Making dependency graph nodes exportable
fileprivate protocol ExportableNode: Hashable {
  var key: DependencyKey {get}
  var definitionVsUse: DefinitionVsUse {get}
  func label(in: InternedStringTable) -> String
}

extension SourceFileDependencyGraph.Node: ExportableNode {
}

extension ModuleDependencyGraph.Node: ExportableNode {
  fileprivate var definitionVsUse: DefinitionVsUse {
    definitionLocation == .unknown ? .use : .definition
  }
}

extension ExportableNode {
  fileprivate func emit(id: Int, to out: inout WritableByteStream, _ t: InternedStringTable) {
    out.send("\(DotFileNode(id: id, node: self, in: t).description)\n")
  }

  fileprivate func label(in t: InternedStringTable) -> String {
    "\(key.description(in: t)) \(definitionVsUse == .definition ? "here" : "somewhere else")"
  }

  fileprivate var isExternal: Bool {
    key.designator.externalDependency != nil
  }
  fileprivate var isAPINotes: Bool {
    key.designator.externalDependency?.fileNameString.hasSuffix(".apinotes")
      ?? false
  }

  fileprivate var shape: Shape {
    key.designator.shape
  }
  fileprivate var fillColor: Color {
    switch (definitionVsUse, key.aspect) {
      case (.definition,  _             ): return .azure
      case (.use,        .interface     ): return .yellow
      case (.use,        .implementation): return .white
    }
  }
  fileprivate var style: Style? {
    definitionVsUse == .definition ? .solid : .dotted
  }
}


fileprivate extension DependencyKey.Designator {
  var shape: Shape {
    switch self {
    case .topLevel:
      return .box
    case .dynamicLookup:
      return .diamond
    case .externalDepend:
      return .house
    case .sourceFileProvide:
      return .hexagon
    case .nominal:
      return .parallelogram
    case .potentialMember:
      return .ellipse
    case .member:
      return .triangle
    }
  }

  static var oneOfEachKind: [DependencyKey.Designator] {
    [
      .topLevel(name: .empty),
      .dynamicLookup(name: .empty),
      .externalDepend(.dummy),
      .sourceFileProvide(name: .empty),
      .nominal(context: .empty),
      .potentialMember(context: .empty),
      .member(context: .empty, name: .empty)
  ]}
}

// MARK: - writing one dot file

fileprivate struct DOTDependencyGraphSerializer<Graph: ExportableGraph>: InternedStringTableHolder {
  private let includeExternals: Bool
  private let includeAPINotes: Bool
  private let graphID: String
  private let graph: Graph
  fileprivate let internedStringTable: InternedStringTable
  private var nodeIDs = [Graph.Node: Int]()
  private var out: WritableByteStream

  fileprivate init(
    _ graph: Graph,
    graphID: String,
    _ stream: WritableByteStream,
    includeExternals: Bool,
    includeAPINotes: Bool,
    internedStringTable: InternedStringTable
  ) {
    self.graph = graph
    self.internedStringTable = internedStringTable
    self.graphID = graphID
    self.out = stream
    self.includeExternals = includeExternals
    self.includeAPINotes = includeAPINotes
  }

  fileprivate mutating func emit() {
    emitPrelude()
    emitLegend()
    emitNodes()
    emitArcs()
    emitPostlude()
  }

  private func emitPrelude() {
    out.send("digraph \(graphID.quoted) {\n")
  }
  private mutating func emitLegend() {
    for dummy in DependencyKey.Designator.oneOfEachKind {
      out.send("\(DotFileNode(forLegend: dummy).description)\n")
    }
  }
  private mutating func emitNodes() {
    graph.forEachExportableNode { (n: Graph.Node) in
      if include(n) {
        n.emit(id: register(n), to: &out, internedStringTable)
      }
    }
  }

  private mutating func register(_ n: Graph.Node) -> Int {
    let newValue = nodeIDs.count
    let oldValue = nodeIDs.updateValue(newValue, forKey: n)
    assert(oldValue == nil, "not nil")
    return newValue
  }

  private func emitArcs() {
    graph.forEachExportableArc { (def: Graph.Node, use: Graph.Node) in
      if include(def: def, use: use) {
        out.send("\(DotFileArc(defID: nodeIDs[def]!, useID: nodeIDs[use]!).description)\n")
      }
    }
  }
  private func emitPostlude() {
    out.send("\n}\n")
  }

  func include(_ n: Graph.Node) -> Bool {
    let externalPredicate = includeExternals || !n.isExternal
    let apiPredicate = includeAPINotes || !n.isAPINotes
    return externalPredicate && apiPredicate;
  }

  func include(def: Graph.Node, use: Graph.Node) -> Bool {
    include(def) && include(use)
  }
}

fileprivate extension String {
  var quoted: String {
    "\"" + replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

fileprivate struct DotFileNode: CustomStringConvertible {
  let id: String
  let label: String
  let shape: Shape
  let fillColor: Color
  let style: Style?

  init<Node: ExportableNode>(id: Int, node: Node, in t: InternedStringTable) {
    self.id = String(id)
    self.label = node.label(in: t)
    self.shape = node.shape
    self.fillColor = node.fillColor
    self.style = node.style
  }

  init(forLegend designator: DependencyKey.Designator) {
    self.id = designator.shape.rawValue
    self.label = designator.kindName
    self.shape = designator.shape
    self.fillColor = .azure
    self.style = nil
  }

  var description: String {
    let bodyString: String = [
      ("label", label),
      ("shape", shape.rawValue),
      ("fillcolor", fillColor.rawValue),
      style.map {("style", $0.rawValue)}
    ]
      .compactMap {
        $0.map {name, value  in "\(name) = \"\(value)\""}
      }
      .joined(separator: ", ")

    return "\(id.quoted) [ \(bodyString) ]"
  }
}

fileprivate struct DotFileArc: CustomStringConvertible {
  let defID, useID: Int

  var description: String {
    "\(defID) -> \(useID);"
  }
}

fileprivate enum Shape: String {
  case box, parallelogram, ellipse, triangle, diamond, house, hexagon
}

fileprivate enum Color: String {
  case azure, white, yellow
}

fileprivate enum Style: String {
  case solid, dotted
}
