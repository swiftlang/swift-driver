//===---SourceFileDependencyGraph.swift - Read swiftdeps or swiftmodule files ---===//
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

import protocol TSCBasic.FileSystem
import struct TSCBasic.ByteString

/*@_spi(Testing)*/ public struct SourceFileDependencyGraph {
  public static let sourceFileProvidesInterfaceSequenceNumber: Int = 0
  public static let sourceFileProvidesImplementationSequenceNumber: Int = 1

  public var majorVersion: UInt64
  public var minorVersion: UInt64
  public var compilerVersionString: String
  private var allNodes: [Node]
  let internedStringTable: InternedStringTable

  public var sourceFileNodePair: (interface: Node, implementation: Node) {
    (interface: allNodes[SourceFileDependencyGraph.sourceFileProvidesInterfaceSequenceNumber],
     implementation: allNodes[SourceFileDependencyGraph.sourceFileProvidesImplementationSequenceNumber])
  }

  public func forEachNode(_ visit: (Node) -> Void) {
    allNodes.forEach(visit)
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

extension SourceFileDependencyGraph {
  public struct Node: Equatable, Hashable {
    public let keyAndFingerprint: KeyAndFingerprintHolder
    public var key: DependencyKey { keyAndFingerprint.key }
    public var fingerprint: InternedString? { keyAndFingerprint.fingerprint }

    public let sequenceNumber: Int
    public let defsIDependUpon: [Int]
    public let definitionVsUse: DefinitionVsUse

    /*@_spi(Testing)*/ public init(
      key: DependencyKey,
      fingerprint: InternedString?,
      sequenceNumber: Int,
      defsIDependUpon: [Int],
      definitionVsUse: DefinitionVsUse
    ) throws {
      self.keyAndFingerprint = try KeyAndFingerprintHolder(key, fingerprint)
      self.sequenceNumber = sequenceNumber
      self.defsIDependUpon = defsIDependUpon
      self.definitionVsUse = definitionVsUse
    }

    public func verify() {
      key.verify()

      if case .sourceFileProvide = key.designator {
        switch key.aspect {
        case .interface:
          assert(sequenceNumber == SourceFileDependencyGraph.sourceFileProvidesInterfaceSequenceNumber)
        case .implementation:
          assert(sequenceNumber == SourceFileDependencyGraph.sourceFileProvidesImplementationSequenceNumber)
        }
      }
    }

    public func description(in holder: InternedStringTableHolder) -> String {
      let providesString = definitionVsUse == .definition ? "provides" : "depends"
      return [
        key.description(in: holder),
        fingerprint.map {"fingerprint: \($0.description(in: holder))"},
        providesString,
        defsIDependUpon.isEmpty ? nil : "depends on \(defsIDependUpon.count)"
      ]
        .compactMap{$0}
        .joined(separator: ", ")
    }
  }
}

extension SourceFileDependencyGraph {
  private enum RecordKind: UInt64 {
    case metadata = 1
    case sourceFileDepGraphNode
    case fingerprintNode
    case dependsOnDefinitionNode
    case identifierNode
  }

  fileprivate enum ReadError: Error {
    case badMagic
    case swiftModuleHasNoDependencies
    case noRecordBlock
    case malformedMetadataRecord
    case unexpectedMetadataRecord
    case malformedFingerprintRecord
    case malformedDependsOnDefinitionRecord
    case malformedIdentifierRecord
    case malformedSourceFileDepGraphNodeRecord
    case unknownRecord
    case unexpectedSubblock
    case bogusNameOrContext
    case unknownKind
  }

  /// Returns nil if there was no dependency info
  ///
  /// Warning: if the serialization format changes, it will be necessary to regenerate the `swiftdeps`
  /// files in `TestInputs/SampleSwiftDeps`.
  /// See ``CleanBuildPerformanceTests/testCleanBuildSwiftDepsPerformance``.
  static func read(
    from typedFile: TypedVirtualPath,
    on fileSystem: FileSystem,
    internedStringTable: InternedStringTable
  ) throws -> Self? {
    try self.init(contentsOf: typedFile, on: fileSystem, internedStringTable: internedStringTable)
  }

  /*@_spi(Testing)*/ public init(nodesForTesting: [Node],
                                 internedStringTable: InternedStringTable) {
    majorVersion = 0
    minorVersion = 0
    compilerVersionString = ""
    allNodes = nodesForTesting
    self.internedStringTable = internedStringTable
  }

  /*@_spi(Testing)*/ public init?(
    contentsOf typedFile: TypedVirtualPath,
    on fileSystem: FileSystem,
    internedStringTable: InternedStringTable
  ) throws {
    assert(typedFile.type == .swiftDeps || typedFile.type == .swiftModule)
    let data = try fileSystem.readFileContents(typedFile.file)
    try self.init(internedStringTable: internedStringTable,
                  data: data,
                  fromSwiftModule: typedFile.type == .swiftModule)
  }

  /// Returns nil for a swiftmodule with no dependencies
  /*@_spi(Testing)*/ public init?(
    internedStringTable: InternedStringTable,
    data: ByteString,
    fromSwiftModule extractFromSwiftModule: Bool = false
  ) throws {
    struct Visitor: BitstreamVisitor, InternedStringTableHolder {
      let extractFromSwiftModule: Bool
      let internedStringTable: InternedStringTable

      init(extractFromSwiftModule: Bool,
           internedStringTable: InternedStringTable) {
        self.extractFromSwiftModule = extractFromSwiftModule
        self.internedStringTable = internedStringTable
        self.identifiers = ["".intern(in: internedStringTable)]
      }

      var nodes: [Node] = []
      var majorVersion: UInt64?
      var minorVersion: UInt64?
      var compilerVersionString: String?

      // Node ingredients
      private var key: DependencyKey?
      private var fingerprint: String?
      private var nodeSequenceNumber = 0
      private var defsNodeDependUpon: [Int] = []
      private var definitionVsUse: DefinitionVsUse = .use

      private var nextSequenceNumber = 0
      private var identifiers: [InternedString] // The empty string is hardcoded as identifiers[0]

      func validate(signature: Bitcode.Signature) throws {
        if extractFromSwiftModule {
          guard signature == .init(value: 0x0EA89CE2) else { throw ReadError.swiftModuleHasNoDependencies }
        } else {
          guard signature == .init(string: "DEPS") else { throw ReadError.badMagic }
        }
      }

      mutating func shouldEnterBlock(id: UInt64) throws -> Bool {
        if extractFromSwiftModule {
          // Enter the top-level module block, and the incremental info
          // subblock, ignoring the rest of the file.
          return id == /*Module block*/ 8 || id == /*Incremental record block*/ 196
        } else {
          guard id == /*Incremental record block*/ 8 else {
            throw ReadError.unexpectedSubblock
          }
          return true
        }
      }

      mutating func didExitBlock() throws {
        try finalizeNode()
      }
      private mutating func finalizeNode() throws {
        guard let key = key else {return}

          let defsIDependUpon: [Int] = Array(unsafeUninitializedCapacity: defsNodeDependUpon.count) { destinationBuffer, initializedCount in
            _ = destinationBuffer.initialize(from: defsNodeDependUpon)
            initializedCount = defsNodeDependUpon.count
        }
        let node = try Node(key: key,
                            fingerprint: fingerprint?.intern(in: internedStringTable),
                            sequenceNumber: nodeSequenceNumber,
                            defsIDependUpon: defsIDependUpon,
                            definitionVsUse: definitionVsUse)
        self.key = nil
        self.defsNodeDependUpon.removeAll(keepingCapacity: true)
        self.nodes.append(node)
      }
      mutating func visit(record: BitcodeElement.Record) throws {
        guard let kind = RecordKind(rawValue: record.id) else { throw ReadError.unknownRecord }
        switch kind {
        case .metadata:
          // If we've already read metadata, this is an unexpected duplicate.
          guard majorVersion == nil, minorVersion == nil, compilerVersionString == nil else {
            throw ReadError.unexpectedMetadataRecord
          }
          guard record.fields.count == 2,
                case .blob(let compilerVersionBlob) = record.payload
          else { throw ReadError.malformedMetadataRecord }

          self.majorVersion = record.fields[0]
          self.minorVersion = record.fields[1]
          self.compilerVersionString = String(decoding: compilerVersionBlob, as: UTF8.self)
        case .sourceFileDepGraphNode:
          try finalizeNode()
          let kindCode = record.fields[0]
          guard record.fields.count == 5,
                let declAspect = DependencyKey.DeclAspect(record.fields[1]),
                record.fields[2] < identifiers.count,
                record.fields[3] < identifiers.count else {
            throw ReadError.malformedSourceFileDepGraphNodeRecord
          }
          let context = identifiers[Int(record.fields[2])]
          let identifier = identifiers[Int(record.fields[3])]
            self.definitionVsUse = .deserializing(record.fields[4])
          let designator = try DependencyKey.Designator(
            kindCode: kindCode, context: context, name: identifier,
            internedStringTable: internedStringTable)
          self.key = DependencyKey(aspect: declAspect, designator: designator)
          self.fingerprint = nil
          self.nodeSequenceNumber = nextSequenceNumber
          self.defsNodeDependUpon.removeAll(keepingCapacity: true)

          nextSequenceNumber += 1
        case .fingerprintNode:
          guard key != nil,
                record.fields.count == 0,
                case .blob(let fingerprintBlob) = record.payload
          else {
            throw ReadError.malformedFingerprintRecord
          }
          self.fingerprint = String(decoding: fingerprintBlob, as: UTF8.self)
        case .dependsOnDefinitionNode:
          guard key != nil,
                record.fields.count == 1 else { throw ReadError.malformedDependsOnDefinitionRecord }
          self.defsNodeDependUpon.append(Int(record.fields[0]))
        case .identifierNode:
          guard record.fields.count == 0,
                case .blob(let identifierBlob) = record.payload
          else {
            throw ReadError.malformedIdentifierRecord
          }
          identifiers.append(String(decoding: identifierBlob, as: UTF8.self).intern(in: internedStringTable))
        }
      }
    }

    var visitor = Visitor(
      extractFromSwiftModule: extractFromSwiftModule,
      internedStringTable: internedStringTable)
    do {
      try Bitcode.read(bytes: data, using: &visitor)
    } catch ReadError.swiftModuleHasNoDependencies {
      return nil
    }
    guard let major = visitor.majorVersion,
          let minor = visitor.minorVersion,
          let versionString = visitor.compilerVersionString else {
      throw ReadError.malformedMetadataRecord
    }
    self.majorVersion = major
    self.minorVersion = minor
    self.compilerVersionString = versionString
    self.allNodes = visitor.nodes
    self.internedStringTable = internedStringTable
  }
}

// MARK: - Creating DependencyKeys
fileprivate extension DependencyKey.DeclAspect {
  init?(_ c: UInt64) {
    switch c {
    case 0: self = .interface
    case 1: self = .implementation
    default: return nil
    }
  }
}

fileprivate extension DependencyKey.Designator {
  init(kindCode: UInt64,
       context: String,
       name: String,
       internedStringTable: InternedStringTable
  ) throws {
    try self.init(kindCode: kindCode,
                  context: context.intern(in: internedStringTable),
                  name: name.intern(in: internedStringTable),
                  internedStringTable: internedStringTable)
  }

  init(kindCode: UInt64,
       context: InternedString,
       name: InternedString,
       internedStringTable: InternedStringTable) throws {
    func mustBeEmpty(_ s: InternedString) throws {
      guard s.isEmpty else { throw SourceFileDependencyGraph.ReadError.bogusNameOrContext }
    }
    switch kindCode {
    case 0:
      try mustBeEmpty(context)
      self = .topLevel(name: name)
    case 1:
      try mustBeEmpty(name)
      self = .nominal(context: context)
    case 2:
      try mustBeEmpty(name)
      self = .potentialMember(context: context)
    case 3:
      self = .member(context: context, name: name)
    case 4:
      try mustBeEmpty(context)
      self = .dynamicLookup(name: name)
    case 5:
      try mustBeEmpty(context)
      self = .externalDepend(ExternalDependency(fileName: name, internedStringTable))
    case 6:
      try mustBeEmpty(context)
      self = .sourceFileProvide(name: name)
    default: throw SourceFileDependencyGraph.ReadError.unknownKind
    }
  }
}

// MARK: - Provides or Depends

/// The frontend reports Swift dependency information about `Decl`s (declarations).
/// The reports are either for definitions or uses. The old terminology (pre-fine-grained) was `provides` vs `depends`.
public enum DefinitionVsUse {
  case definition, use

  static func deserializing(_ field: UInt64) -> Self {
    field != 0 ? .definition : .use
  }
}
