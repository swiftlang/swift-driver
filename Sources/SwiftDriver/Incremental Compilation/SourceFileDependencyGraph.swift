//===------- SourceFileDependencyGraph.swift - Read swiftdeps files -------===//
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
@_implementationOnly import Yams

public struct SourceFileDependencyGraph: Codable {
  public static let sourceFileProvidesInterfaceSequenceNumber: Int = 0
  public static let sourceFileProvidesImplementationSequenceNumber: Int = 1

  private var allNodes: [Node]

  public var sourceFileNodePair: (interface: Node, implementation: Node) {
    (interface: allNodes[SourceFileDependencyGraph.sourceFileProvidesInterfaceSequenceNumber],
     implementation: allNodes[SourceFileDependencyGraph.sourceFileProvidesImplementationSequenceNumber])
  }

  public func forEachNode(_ doIt: (Node)->Void) {
    allNodes.forEach(doIt)
  }

  public func forEachDefDependedUpon(by node: Node, _ doIt: (Node)->Void) {
    for sequenceNumber in node.defsIDependUpon {
      doIt(allNodes[sequenceNumber])
    }
  }

  public func forEachArc(_ doIt: (Node, Node)->Void) {
    forEachNode { useNode in
      forEachDefDependedUpon(by: useNode) { defNode in
        doIt(defNode, useNode)
      }
    }
  }

  @discardableResult public func verify() -> Bool {
    assert(Array(allNodes.indices) == allNodes.map { $0.sequenceNumber })
    forEachNode {
      $0.verify()
    }
    return true
  }

  public init(contents: String) throws {
    let decoder = YAMLDecoder()
    self = try decoder.decode(Self.self, from: contents)
    assert(verify())
  }
}

public enum DeclAspect: String, Codable {
  case interface, implementation
}

public struct DependencyKey: Codable {
  public enum Kind: String, Codable {
    case topLevel
    case nominal
    case potentialMember
    case member
    case dynamicLookup
    case externalDepend
    case sourceFileProvide
  }

  public var kind: Kind
  public var aspect: DeclAspect
  public var context: String
  public var name: String

  public func verify() {
    assert(kind != .externalDepend || aspect == .interface, "All external dependencies must be interfaces.")
    switch kind {
    case .topLevel, .dynamicLookup, .externalDepend, .sourceFileProvide:
      assert(context.isEmpty && !name.isEmpty, "Must only have a name")
    case .nominal, .potentialMember:
      assert(!context.isEmpty && name.isEmpty, "Must only have a context")
    case .member:
      assert(!context.isEmpty && !name.isEmpty, "Must have both")
    }
  }
}


extension SourceFileDependencyGraph {
  public struct Node: Codable {
    public var key: DependencyKey
    public var fingerprint: String?
    public var sequenceNumber: Int
    public var defsIDependUpon: [Int]
    public var isProvides: Bool

    public func verify() {
      key.verify()

      if key.kind == .sourceFileProvide {
        switch key.aspect {
        case .interface:
          assert(sequenceNumber == SourceFileDependencyGraph.sourceFileProvidesInterfaceSequenceNumber)
        case .implementation:
          assert(sequenceNumber == SourceFileDependencyGraph.sourceFileProvidesImplementationSequenceNumber)
        }
      }
    }
  }
}
