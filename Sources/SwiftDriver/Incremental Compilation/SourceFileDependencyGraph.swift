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
import Foundation

public struct SourceFileDependencyGraph {
  public static let sourceFileProvidesInterfaceSequenceNumber: Int = 0
  public static let sourceFileProvidesImplementationSequenceNumber: Int = 1

  public var majorVersion: UInt64
  public var minorVersion: UInt64
  public var compilerVersionString: String
  private var allNodes: [Node]

  public var sourceFileNodePair: (interface: Node, implementation: Node) {
    (interface: allNodes[SourceFileDependencyGraph.sourceFileProvidesInterfaceSequenceNumber],
     implementation: allNodes[SourceFileDependencyGraph.sourceFileProvidesImplementationSequenceNumber])
  }

  public func forEachNode(_ doIt: (Node) -> Void) {
    allNodes.forEach(doIt)
  }

  public func forEachDefDependedUpon(by node: Node, _ doIt: (Node) -> Void) {
    for sequenceNumber in node.defsIDependUpon {
      doIt(allNodes[sequenceNumber])
    }
  }

  public func forEachArc(_ doIt: (Node, Node) -> Void) {
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
}

public enum DeclAspect: UInt64 {
  case interface, implementation
}

public struct DependencyKey {
  public enum Kind: UInt64 {
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
  public struct Node {
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

extension SourceFileDependencyGraph {
  private static let recordBlockId = 8

  private enum RecordKind: UInt64 {
    case metadata = 1
    case sourceFileDepGraphNode
    case fingerprintNode
    case dependsOnDefinitionNode
    case identifierNode
  }

  private enum ReadError: Error {
    case badMagic
    case noRecordBlock
    case malformedMetadataRecord
    case unexpectedMetadataRecord
    case malformedFingerprintRecord
    case malformedDependsOnDefinitionRecord
    case malformedIdentifierRecord
    case malformedSourceFileDepGraphNodeRecord
    case unknownRecord
    case unexpectedSubblock
  }

  public init(data: Data) throws {
    // FIXME: visit blocks and records incrementally instead of reading the
    // entire file up front.
    let bitcode = try Bitcode(data: data)
    guard bitcode.signature == .init(string: "DEPS") else { throw ReadError.badMagic }

    guard bitcode.elements.count == 1,
          case .block(let recordBlock) = bitcode.elements.first,
          recordBlock.id == Self.recordBlockId else { throw ReadError.noRecordBlock }

    guard case .record(let metadataRecord) = recordBlock.elements.first,
          RecordKind(rawValue: metadataRecord.id) == .metadata,
          metadataRecord.fields.count == 2,
          case .blob(let compilerVersionBlob) = metadataRecord.payload,
          let compilerVersionString = String(data: compilerVersionBlob, encoding: .utf8)
    else { throw ReadError.malformedMetadataRecord }

    self.majorVersion = metadataRecord.fields[0]
    self.minorVersion = metadataRecord.fields[1]
    self.compilerVersionString = compilerVersionString

    var nodes: [Node] = []
    var node: Node? = nil
    var identifiers: [String] = [""] // The empty string is hardcoded as identifiers[0]
    var sequenceNumber = 0
    for element in recordBlock.elements.dropFirst() {
      guard case .record(let record) = element else { throw ReadError.unexpectedSubblock }
      guard let kind = RecordKind(rawValue: record.id) else { throw ReadError.unknownRecord }
      switch kind {
      case .metadata:
        throw ReadError.unexpectedMetadataRecord
      case .sourceFileDepGraphNode:
        if let node = node {
          nodes.append(node)
        }
        guard record.fields.count == 5,
              let nodeKind = DependencyKey.Kind(rawValue: record.fields[0]),
              let declAspect = DeclAspect(rawValue: record.fields[1]),
              record.fields[2] < identifiers.count,
              record.fields[3] < identifiers.count else {
          throw ReadError.malformedSourceFileDepGraphNodeRecord
        }
        let context = identifiers[Int(record.fields[2])]
        let identifier = identifiers[Int(record.fields[3])]
        let isProvides = record.fields[4] != 0
        node = Node(key: .init(kind: nodeKind,
                               aspect: declAspect,
                               context: context,
                               name: identifier),
                    fingerprint: nil,
                    sequenceNumber: sequenceNumber,
                    defsIDependUpon: [],
                    isProvides: isProvides)
        sequenceNumber += 1
      case .fingerprintNode:
        guard node != nil,
              record.fields.count == 0,
              case .blob(let fingerprintBlob) = record.payload,
              let fingerprint = String(data: fingerprintBlob, encoding: .utf8) else {
          throw ReadError.malformedFingerprintRecord
        }
        node?.fingerprint = fingerprint
      case .dependsOnDefinitionNode:
        guard node != nil,
              record.fields.count == 1 else { throw ReadError.malformedDependsOnDefinitionRecord }
        node?.defsIDependUpon.append(Int(record.fields[0]))
      case .identifierNode:
        guard record.fields.count == 0,
              case .blob(let identifierBlob) = record.payload,
              let identifier = String(data: identifierBlob, encoding: .utf8) else {
          throw ReadError.malformedIdentifierRecord
        }
        identifiers.append(identifier)
      }
    }

    if let node = node {
      nodes.append(node)
    }

    self.allNodes = nodes
  }
}
