//===------- ModuleDependencyGraph.swift ----------------------------------===//
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
import TSCUtility
import SwiftOptions


// MARK: - ModuleDependencyGraph

/// Holds all the dependency relationships in this module, and declarations in other modules that
/// are dependended-upon.
/*@_spi(Testing)*/ public final class ModuleDependencyGraph {

  @_spi(Testing) public var nodeFinder = NodeFinder()
  
  /// Maps input files (e.g. .swift) to and from the DependencySource object
  @_spi(Testing) public private(set) var inputDependencySourceMap = BidirectionalMap<TypedVirtualPath, DependencySource>()

  // The set of paths to external dependencies known to be in the graph
  public internal(set) var fingerprintedExternalDependencies = Set<FingerprintedExternalDependency>()

  /// A lot of initial state that it's handy to have around.
  @_spi(Testing) public let info: IncrementalCompilationState.InitialStateComputer

  /// For debugging, something to write out files for visualizing graphs
  let dotFileWriter: DependencyGraphDotFileWriter?

  public init(_ info: IncrementalCompilationState.InitialStateComputer
  ) {
    self.info = info
    self.dotFileWriter = info.emitDependencyDotFileAfterEveryImport
    ? DependencyGraphDotFileWriter(info)
    : nil
  }

  private func addMapEntry(_ input: TypedVirtualPath, _ dependencySource: DependencySource) {
    assert(input.type == .swift && dependencySource.typedFile.type == .swiftDeps)
    inputDependencySourceMap[input] = dependencySource
  }

  @_spi(Testing) public func getSource(for input: TypedVirtualPath,
                                       function: String = #function,
                                       file: String = #file,
                                       line: Int = #line) -> DependencySource {
    guard let source = inputDependencySourceMap[input] else {
      fatalError("\(input.file) not found in map: \(inputDependencySourceMap), \(file):\(line) in \(function)")
    }
    return source
  }
  @_spi(Testing) public func getInput(for source: DependencySource) -> TypedVirtualPath {
    guard let input = inputDependencySourceMap[source] else {
      fatalError("\(source.file) not found in map: \(inputDependencySourceMap)")
    }
    return input
  }
}

// MARK: - Building from swiftdeps
extension ModuleDependencyGraph {
  /// Integrates `input` as needed and returns any inputs that were invalidated by external dependencies
  /// When creating a graph from swiftdeps files, this operation is performed for each input.
  func collectInputsRequiringCompilationFromExternalsFoundByCompiling(
    input: TypedVirtualPath
  ) -> Set<TypedVirtualPath>? {
    // do not try to read swiftdeps of a new input
    if info.sourceFiles.isANewInput(input.file) {
      return Set<TypedVirtualPath>()
    }
    return collectInputsRequiringCompilationAfterProcessing(
      dependencySource: getSource(for: input),
      includeAddedExternals: false)
  }
}

// MARK: - Getting a graph read from priors ready to use
extension ModuleDependencyGraph {
  func collectNodesInvalidatedByChangedOrAddedExternals() -> Set<Node> {
    fingerprintedExternalDependencies.reduce(into: Set()) { invalidatedNodes, fed in
      invalidatedNodes.formUnion (
        self.collectNodesInvalidatedByProcessing(fingerprintedExternalDependency: fed,
                                                 includeAddedExternals: true))
    }
  }
}

// MARK: - Scheduling the first wave
extension ModuleDependencyGraph {
  /// Find all the sources that depend on `sourceFile`. For some source files, these will be
  /// speculatively scheduled in the first wave.
  func collectInputsTransitivelyInvalidatedBy(input: TypedVirtualPath
  ) -> [TypedVirtualPath] {
    let changedSource = getSource(for: input)
    let allDependencySourcesToRecompile =
      collectSwiftDepsTransitivelyUsing(dependencySource: changedSource)

    return allDependencySourcesToRecompile.compactMap {
      guard $0 != changedSource else {return nil}
      let dependentSource = inputDependencySourceMap[$0]
      info.reporter?.report(
        "Found dependent of \(input.file.basename):", dependentSource)
      return dependentSource
    }
  }

  /// Find all the swiftDeps files that depend on `dependencySource`.
  /// Really private, except for testing.
  /*@_spi(Testing)*/ public func collectSwiftDepsTransitivelyUsing(
    dependencySource: DependencySource
  ) -> Set<DependencySource> {
    let nodes = nodeFinder.findNodes(for: dependencySource) ?? [:]
    /// Tests expect this to be reflexive
    return collectSwiftDepsUsingTransitivelyInvalidated(nodes: nodes.values)
  }

  /// Does the graph contain any dependency nodes for a given source-code file?
  func containsNodes(forSourceFile file: TypedVirtualPath) -> Bool {
    precondition(file.type == .swift)
    guard let source = inputDependencySourceMap[file] else {
      return false
    }
    return containsNodes(forDependencySource: source)
  }

  func containsNodes(forDependencySource source: DependencySource) -> Bool {
    return nodeFinder.findNodes(for: source).map {!$0.isEmpty}
      ?? false
  }

  /// Return true on success
  func populateInputDependencySourceMap() -> Bool {
    let ofm = info.outputFileMap
    let de = info.diagnosticEngine
    return info.inputFiles.reduce(true) { okSoFar, input in
      ofm.getDependencySource(for: input, diagnosticEngine: de)
        .map {source in addMapEntry(input, source); return okSoFar } ?? false
    }
  }
}
// MARK: - Scheduling the 2nd wave
extension ModuleDependencyGraph {
  /// After `source` has been compiled, figure out what other source files need compiling.
  /// Used to schedule the 2nd wave.
  /// Return nil in case of an error.
  /// May return a source that has already been compiled.
  func collectInputsRequiringCompilation(byCompiling input: TypedVirtualPath
  ) -> Set<TypedVirtualPath>? {
    precondition(input.type == .swift)
    let dependencySource = getSource(for: input)
    return collectInputsRequiringCompilationAfterProcessing(
      dependencySource: dependencySource,
      includeAddedExternals: true)
  }
}

// MARK: - Scheduling either wave
extension ModuleDependencyGraph {
  
  /// Given a set of invalidated nodes, find all swiftDeps dependency sources containing defs that transitively use
  /// any of the invalidated nodes.
  /*@_spi(Testing)*/
  public func collectSwiftDepsUsingTransitivelyInvalidated<Nodes: Sequence>(
    nodes: Nodes
  ) -> Set<DependencySource>
  where Nodes.Element == Node
  {
    // Is this correct for the 1st wave after having read a prior?
    // Yes, because
    //  1. if the externalDependency was current, there are no changes required
    //  2. otherwise, it will have been reread, which should create changed nodes, etc.
    let affectedNodes = Tracer.collectPreviouslyUntracedNodesUsing(
      defNodes: nodes,
      in: self,
      diagnosticEngine: info.diagnosticEngine)
      .tracedUses
    return affectedNodes.reduce(into: Set()) {
      invalidatedSources, affectedNode in
      if let source = affectedNode.dependencySource,
          source.typedFile.type == .swiftDeps {
        invalidatedSources.insert(source)
      }
    }
  }

  /// Given an external dependency & its fingerprint, find any nodes directly using that dependency.
  /// As an optimization, only return the nodes that have not been already traced, because the traced nodes
  /// will have already been used to schedule jobs to run.
  /*@_spi(Testing)*/ public func collectUntracedNodesDirectlyUsing(
    _ fingerprintedExternalDependency: FingerprintedExternalDependency
  ) -> Set<Node> {
    // These nodes will depend on the *interface* of the external Decl.
    let key = DependencyKey(
      aspect: .interface,
      designator: .externalDepend(fingerprintedExternalDependency.externalDependency))
    // DependencySource is OK as a nil placeholder because it's only used to find
    // the corresponding implementation node and there won't be any for an
    // external dependency node.
    let node = Node(key: key,
                    fingerprint: fingerprintedExternalDependency.fingerprint,
                    dependencySource: nil)
    return nodeFinder
      .uses(of: node)
      .filter({ use in use.isUntraced })
  }

  /// Find all the inputs known to need recompilation as a consequence of reading a swiftdeps or swiftmodule
  /// `dependencySource` - The file to read containing dependency information
  /// `includeAddedExternals` - If `true` external dependencies read from the dependencySource cause inputs to be invalidated,
  /// even if the external file has not changed since the last build.
  /// (`false` when building a graph from swiftdeps, `true` when building a graph from rereading the result of a compilation,
  /// because in that case the added external is assumed to be caused by an `import` added to the source file.)
  /// `invalidatedOnlyByExternals` - Only return inputs invalidated because of external dependencies, vs invalidated by any dependency
  /// Returns `nil` on error
  private func collectInputsRequiringCompilationAfterProcessing(
    dependencySource: DependencySource,
    includeAddedExternals: Bool
  ) -> Set<TypedVirtualPath>? {
    guard let sourceGraph = dependencySource.read(in: info.fileSystem,
                                                  reporter: info.reporter)
    else {
      // to preserve legacy behavior cancel whole thing
      info.diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "malformed dependencies file '\(dependencySource.typedFile)'"))
      return nil
    }
    let results = Integrator.integrate(from: sourceGraph,
                                       into: self,
                                       includeAddedExternals: includeAddedExternals)

    /// When reading from a swiftdeps file ( includeAddedExternals is false), any changed input files are
    /// computed separately. (TODO: fix this? by finding changed inputs in a callee?),
    /// so the only invalidates that matter are the ones caused by
    /// changed external dependencies.
    /// When reading a swiftdeps file after compiling, any invalidated node matters.
    let invalidatedNodes = includeAddedExternals
      ? results.allInvalidatedNodes
      : results.nodesInvalidatedByUsingSomeExternal

    return collectInputsUsingTransitivelyInvalidated(nodes: invalidatedNodes)
  }

  /// Given nodes that are invalidated, find all the affected inputs that must be recompiled.
  func collectInputsUsingTransitivelyInvalidated(
    nodes invalidatedNodes: Set<Node>
  ) -> Set<TypedVirtualPath> {
    collectSwiftDepsUsingTransitivelyInvalidated(nodes: invalidatedNodes)
      .reduce(into: Set()) { invalidatedInputs, invalidatedSwiftDeps in
        invalidatedInputs.insert(getInput(for: invalidatedSwiftDeps))
      }
  }
}

// MARK: - processing external dependencies
extension ModuleDependencyGraph {

  /// Process a possibly-fingerprinted external dependency by reading and integrating, if applicable.
  /// Return the nodes thus invalidated.
  /// includeAddedExternals - return the changes arising merely because the external was new to the graph,
  /// as opposed to changes from changed externals.
  /// But always integrate, in order to detect future changes.
  func collectNodesInvalidatedByProcessing(
    fingerprintedExternalDependency fed: FingerprintedExternalDependency,
    includeAddedExternals: Bool)
  -> Set<Node> {

    let isNewToTheGraph = fingerprintedExternalDependencies.insert(fed).inserted

    var lazyModTimer = LazyModTimer(
      externalDependency: fed.externalDependency,
      info: info)

    // If the graph already includes prior externals, then any new externals are changes
    // Short-circuit conjunction may avoid the modTime query
    let shouldTryToProcess = info.isCrossModuleIncrementalBuildEnabled &&
      (isNewToTheGraph || lazyModTimer.hasExternalFileChanged)

    let invalidatedNodesFromIncrementalExternal = shouldTryToProcess
      ? collectNodesInvalidatedByAttemptingToProcess(
        fed, info, includeAddedExternals: includeAddedExternals)
      : nil

    let callerWantsTheseChanges = (includeAddedExternals && isNewToTheGraph) ||
      lazyModTimer.hasExternalFileChanged

    return !callerWantsTheseChanges
      ? Set<Node>()
      : invalidatedNodesFromIncrementalExternal ?? collectUntracedNodesDirectlyUsing(fed)
  }
  
  private struct LazyModTimer {
    let externalDependency: ExternalDependency
    let info: IncrementalCompilationState.InitialStateComputer

    lazy var hasExternalFileChanged = (externalDependency.modTime(info.fileSystem) ?? .distantFuture)
      >= info.buildTime
  }

  private func collectNodesInvalidatedByAttemptingToProcess(
    _ fed: FingerprintedExternalDependency,
    _ info: IncrementalCompilationState.InitialStateComputer,
    includeAddedExternals: Bool
  ) -> Set<Node>? {
    fed.incrementalDependencySource?
      .read(in: info.fileSystem, reporter: info.reporter)
      .map { unserializedDepGraph in
        info.reporter?.report("Integrating changes from", fed.externalDependency.file)
        return Integrator.integrate(
          from: unserializedDepGraph,
          into: self,
          includeAddedExternals: includeAddedExternals)
          .allInvalidatedNodes
      }
  }

}

extension OutputFileMap {
  fileprivate func getDependencySource(
    for sourceFile: TypedVirtualPath,
    diagnosticEngine: DiagnosticsEngine
  ) -> DependencySource? {
    assert(sourceFile.type == FileType.swift)
    guard let swiftDepsPath = existingOutput(inputFile: sourceFile.file,
                                             outputType: .swiftDeps)
    else {
      // The legacy driver fails silently here.
      diagnosticEngine.emit(
        .remarkDisabled("\(sourceFile.file.basename) has no swiftDeps file")
      )
      return nil
    }
    assert(swiftDepsPath.extension == FileType.swiftDeps.rawValue)
    let typedSwiftDepsFile = TypedVirtualPath(file: swiftDepsPath, type: .swiftDeps)
    return DependencySource(typedSwiftDepsFile)
  }
}

// MARK: - tracking traced nodes
extension ModuleDependencyGraph {

 func ensureGraphWillRetrace<Nodes: Sequence>(_ nodes: Nodes)
  where Nodes.Element == Node
  {
    for node in nodes {
      node.setUntraced()
    }
  }
}

// MARK: - verification
extension ModuleDependencyGraph {
  @discardableResult
  func verifyGraph() -> Bool {
    nodeFinder.verify()
  }
}
// MARK: - Serialization

extension ModuleDependencyGraph {
  /// The leading signature of this file format.
  fileprivate static let signature = "DDEP"
  /// The expected version number of the serialized dependency graph.
  ///
  /// - WARNING: You *must* increment the minor version number when making any
  ///            changes to the underlying serialization format.
  fileprivate static let version = Version(1, 0, 0)

  /// The IDs of the records used by the module dependency graph.
  fileprivate enum RecordID: UInt64 {
    case metadata           = 1
    case moduleDepGraphNode = 2
    case dependsOnNode      = 3
    case useIDNode          = 4
    case externalDepNode    = 5
    case identifierNode     = 6
    case mapNode            = 7

    /// The human-readable name of this record.
    ///
    /// This data is emitted into the block info field for each record so tools
    /// like llvm-bcanalyzer can be used to more effectively debug serialized
    /// dependency graphs.
    var humanReadableName: String {
      switch self {
      case .metadata:
        return "METADATA"
      case .moduleDepGraphNode:
        return "MODULE_DEP_GRAPH_NODE"
      case .dependsOnNode:
        return "DEPENDS_ON_NODE"
      case .useIDNode:
        return "USE_ID_NODE"
      case .externalDepNode:
        return "EXTERNAL_DEP_NODE"
      case .identifierNode:
        return "IDENTIFIER_NODE"
      case .mapNode:
        return "MAP_NODE"
      }
    }
  }

  fileprivate enum ReadError: Error {
    case badMagic
    case noRecordBlock
    case malformedMetadataRecord
    case unexpectedMetadataRecord
    case malformedFingerprintRecord
    case malformedIdentifierRecord
    case malformedModuleDepGraphNodeRecord
    case malformedDependsOnRecord
    case malformedMapRecord
    case malformedExternalDepNodeRecord
    case unknownRecord
    case unexpectedSubblock
    case bogusNameOrContext
    case unknownKind
    case unknownDependencySourceExtension
  }

  /// Attempts to read a serialized dependency graph from the given path.
  ///
  /// - Parameters:
  ///   - path: The absolute path to the file to be read.
  ///   - fileSystem: The file system on which to search.
  ///   - diagnosticEngine: The diagnostics engine.
  ///   - reporter: An optional reporter used to log information about
  /// - Throws: An error describing any failures to read the graph from the given file.
  /// - Returns: A fully deserialized ModuleDependencyGraph, or nil if nothing is there
  @_spi(Testing) public static func read(
    from path: VirtualPath,
    info: IncrementalCompilationState.InitialStateComputer
  ) throws -> ModuleDependencyGraph? {
    guard try info.fileSystem.exists(path) else {
      return nil
    }
    let data = try info.fileSystem.readFileContents(path)

    struct Visitor: BitstreamVisitor {
      private let fileSystem: FileSystem
      private let graph: ModuleDependencyGraph
      var majorVersion: UInt64?
      var minorVersion: UInt64?
      var compilerVersionString: String?

      // The empty string is hardcoded as identifiers[0]
      private var identifiers: [String] = [""]
      private var currentDefKey: DependencyKey? = nil
      private var nodeUses: [DependencyKey: [Int]] = [:]
      private var inputDependencySourceMap: [(TypedVirtualPath, DependencySource)] = []
      public private(set) var allNodes: [Node] = []

      init(_ info: IncrementalCompilationState.InitialStateComputer) {
        self.fileSystem = info.fileSystem
        self.graph = ModuleDependencyGraph(info)
      }

      func finalizeGraph() -> ModuleDependencyGraph {
        for (dependencyKey, useIDs) in self.nodeUses {
          for useID in useIDs {
            let isNewUse = self.graph.nodeFinder
              .record(def: dependencyKey, use: self.allNodes[useID])
            assert(isNewUse, "Duplicate use def-use arc in graph?")
          }
        }
        for (input, source) in inputDependencySourceMap {
          graph.addMapEntry(input, source)
        }

        return self.graph
      }

      func validate(signature: Bitcode.Signature) throws {
        guard signature == .init(string: ModuleDependencyGraph.signature) else {
          throw ReadError.badMagic
        }
      }

      mutating func shouldEnterBlock(id: UInt64) throws -> Bool {
        return true
      }

      mutating func didExitBlock() throws {}

      private mutating func finalize(node newNode: Node) {
        self.allNodes.append(newNode)
        let oldNode = self.graph.nodeFinder.insert(newNode)
        assert(oldNode == nil,
               "Integrated the same node twice: \(oldNode!), \(newNode)")
      }

      mutating func visit(record: BitcodeElement.Record) throws {
        guard let kind = RecordID(rawValue: record.id) else {
          throw ReadError.unknownRecord
        }

        switch kind {
        case .metadata:
          // If we've already read metadata, this is an unexpected duplicate.
          guard self.majorVersion == nil, self.minorVersion == nil, self.compilerVersionString == nil else {
            throw ReadError.unexpectedMetadataRecord
          }
          guard record.fields.count == 2,
                case .blob(let compilerVersionBlob) = record.payload,
                let compilerVersionString = String(data: compilerVersionBlob, encoding: .utf8)
          else { throw ReadError.malformedMetadataRecord }

          self.majorVersion = record.fields[0]
          self.minorVersion = record.fields[1]
          self.compilerVersionString = compilerVersionString
        case .moduleDepGraphNode:
          let kindCode = record.fields[0]
          guard record.fields.count == 7,
                let declAspect = DependencyKey.DeclAspect(record.fields[1]),
                record.fields[2] < identifiers.count,
                record.fields[3] < identifiers.count,
                case .blob(let fingerprintBlob) = record.payload,
                let fingerprintStr = String(data: fingerprintBlob, encoding: .utf8)
          else {
            throw ReadError.malformedModuleDepGraphNodeRecord
          }
          let context = identifiers[Int(record.fields[2])]
          let identifier = identifiers[Int(record.fields[3])]
          let designator = try DependencyKey.Designator(
            kindCode: kindCode, context: context, name: identifier, fileSystem: fileSystem)
          let key = DependencyKey(aspect: declAspect, designator: designator)
          let hasSwiftDeps = Int(record.fields[4]) != 0
          let swiftDepsStr = hasSwiftDeps ? identifiers[Int(record.fields[5])] : nil
          let hasFingerprint = Int(record.fields[6]) != 0
          let fingerprint = hasFingerprint ? fingerprintStr : nil
          guard let dependencySource = try swiftDepsStr
                  .map({ try VirtualPath(path: $0) })
                  .map(DependencySource.init)
          else {
            throw ReadError.unknownDependencySourceExtension
          }
          self.finalize(node: Node(key: key,
                                   fingerprint: fingerprint,
                                   dependencySource: dependencySource))
        case .dependsOnNode:
          let kindCode = record.fields[0]
          guard record.fields.count == 4,
                let declAspect = DependencyKey.DeclAspect(record.fields[1]),
                record.fields[2] < identifiers.count,
                record.fields[3] < identifiers.count
          else {
            throw ReadError.malformedDependsOnRecord
          }
          let context = identifiers[Int(record.fields[2])]
          let identifier = identifiers[Int(record.fields[3])]
          let designator = try DependencyKey.Designator(
            kindCode: kindCode, context: context, name: identifier, fileSystem: fileSystem)
          self.currentDefKey = DependencyKey(aspect: declAspect, designator: designator)
        case .useIDNode:
          guard let key = self.currentDefKey, record.fields.count == 1 else {
            throw ReadError.malformedDependsOnRecord
          }
          self.nodeUses[key, default: []].append(Int(record.fields[0]))
        case .mapNode:
          guard record.fields.count == 2,
                record.fields[0] < identifiers.count,
                record.fields[1] < identifiers.count
          else {
            throw ReadError.malformedModuleDepGraphNodeRecord
          }
          let inputPathString = identifiers[Int(record.fields[0])]
          let dependencySourcePathString = identifiers[Int(record.fields[1])]
          let inputPath = try VirtualPath(path: inputPathString)
          let dependencySourcePath = try VirtualPath(path: dependencySourcePathString)
          guard inputPath.extension == FileType.swift.rawValue,
                dependencySourcePath.extension == FileType.swiftDeps.rawValue,
                let dependencySource = DependencySource(dependencySourcePath)
          else {
            throw ReadError.malformedMapRecord
          }
          let input = TypedVirtualPath(file: inputPath, type: .swift)
          inputDependencySourceMap.append((input, dependencySource))
        case .externalDepNode:
          guard record.fields.count == 2,
                record.fields[0] < identifiers.count,
                case .blob(let fingerprintBlob) = record.payload,
                let fingerprintStr = String(data: fingerprintBlob, encoding: .utf8)
          else {
            throw ReadError.malformedExternalDepNodeRecord
          }
          let path = identifiers[Int(record.fields[0])]
          let hasFingerprint = Int(record.fields[1]) != 0
          let fingerprint = hasFingerprint ? fingerprintStr : nil
          try self.graph.fingerprintedExternalDependencies.insert(
            FingerprintedExternalDependency(ExternalDependency(path), fingerprint))
        case .identifierNode:
          guard record.fields.count == 0,
                case .blob(let identifierBlob) = record.payload,
                let identifier = String(data: identifierBlob, encoding: .utf8)
          else {
            throw ReadError.malformedIdentifierRecord
          }
          identifiers.append(identifier)
        }
      }
    }

    var visitor = Visitor(info)
    try Bitcode.read(bytes: data, using: &visitor)
    guard let major = visitor.majorVersion,
          let minor = visitor.minorVersion,
          visitor.compilerVersionString != nil,
          Version(Int(major), Int(minor), 0) == Self.version
    else {
      throw ReadError.malformedMetadataRecord
    }
    let graph = visitor.finalizeGraph()
    info.reporter?.report("Read dependency graph", path)
    return graph
  }
}

extension ModuleDependencyGraph {
  /// Attempts to serialize this dependency graph and write its contents
  /// to the given file path.
  ///
  /// Should serialization fail, the driver must emit an error *and* moreover
  /// the build record should reflect that the incremental build failed. This
  /// prevents bogus priors from being picked up the next time the build is run.
  /// It's better for us to just redo the incremental build than wind up with
  /// corrupted dependency state.
  ///
  /// - Parameters:
  ///   - path: The location to write the data for this file.
  ///   - fileSystem: The file system for this location.
  ///   - compilerVersion: A string containing version information for the
  ///                      driver used to create this file.
  @_spi(Testing) public func write(
    to path: VirtualPath,
    on fileSystem: FileSystem,
    compilerVersion: String
  ) {
    let data = ModuleDependencyGraph.Serializer.serialize(self, compilerVersion)

    do {
      try fileSystem.writeFileContents(path,
                                       bytes: data,
                                       atomically: true)
    } catch {
      info.diagnosticEngine.emit(.error_could_not_write_dep_graph(to: path))
    }
  }

  fileprivate final class Serializer {
    let compilerVersion: String
    let stream = BitstreamWriter()
    private var abbreviations = [RecordID: Bitstream.AbbreviationID]()
    private var identifiersToWrite = [String]()
    private var identifierIDs = [String: Int]()
    private var lastIdentifierID: Int = 1
    fileprivate private(set) var nodeIDs = [Node: Int]()
    private var lastNodeID: Int = 0

    private init(compilerVersion: String) {
      self.compilerVersion = compilerVersion
    }

    private func emitSignature() {
      for c in ModuleDependencyGraph.signature {
        self.stream.writeASCII(c)
      }
    }

    private func emitBlockID(_ ID: Bitstream.BlockID, _ name: String) {
      self.stream.writeRecord(Bitstream.BlockInfoCode.setBID) {
        $0.append(ID)
      }

      // Emit the block name if present.
      guard !name.isEmpty else {
        return
      }

      self.stream.writeRecord(Bitstream.BlockInfoCode.blockName) { buffer in
        buffer.append(name)
      }
    }

    private func emitRecordID(_ id: RecordID) {
      self.stream.writeRecord(Bitstream.BlockInfoCode.setRecordName) {
        $0.append(id)
        $0.append(id.humanReadableName)
      }
    }

    private func writeBlockInfoBlock() {
      self.stream.writeBlockInfoBlock {
        self.emitBlockID(.firstApplicationID, "RECORD_BLOCK")
        self.emitRecordID(.metadata)
        self.emitRecordID(.moduleDepGraphNode)
        self.emitRecordID(.useIDNode)
        self.emitRecordID(.externalDepNode)
        self.emitRecordID(.identifierNode)
        self.emitRecordID(.mapNode)
      }
    }

    private func writeMetadata() {
      self.stream.writeRecord(self.abbreviations[.metadata]!, {
        $0.append(RecordID.metadata)
        // Major version
        $0.append(1 as UInt32)
        // Minor version
        $0.append(0 as UInt32)
      },
      blob: self.compilerVersion)
    }

    private func addIdentifier(_ str: String) {
      guard !str.isEmpty && self.identifierIDs[str] == nil else {
        return
      }

      defer { self.lastIdentifierID += 1 }
      self.identifierIDs[str] = self.lastIdentifierID
      self.identifiersToWrite.append(str)
    }

    private func lookupIdentifierCode(for string: String) -> UInt32 {
      guard !string.isEmpty else {
        return 0
      }

      return UInt32(self.identifierIDs[string]!)
    }

    private func cacheNodeID(for node: Node) {
      defer { self.lastNodeID += 1 }
      nodeIDs[node] = self.lastNodeID
    }

    private func populateCaches(from graph: ModuleDependencyGraph) {
      graph.nodeFinder.forEachNode { node in
        self.cacheNodeID(for: node)

        if let dependencySourceFileName = node.dependencySource?.file.name {
          self.addIdentifier(dependencySourceFileName)
        }
        if let context = node.key.designator.context {
          self.addIdentifier(context)
        }
        if let name = node.key.designator.name {
          self.addIdentifier(name)
        }
      }

      for key in graph.nodeFinder.usesByDef.keys {
        if let context = key.designator.context {
          self.addIdentifier(context)
        }
        if let name = key.designator.name {
          self.addIdentifier(name)
        }
      }

      for (input, dependencySource) in graph.inputDependencySourceMap {
        self.addIdentifier(input.file.name)
        self.addIdentifier(dependencySource.file.name)
      }

      for edF in graph.fingerprintedExternalDependencies {
        self.addIdentifier(edF.externalDependency.file.name)
      }

      for str in self.identifiersToWrite {
        self.stream.writeRecord(self.abbreviations[.identifierNode]!, {
          $0.append(RecordID.identifierNode)
        }, blob: str)
      }
    }

    private func registerAbbreviations() {
      self.abbreviate(.metadata, [
        .literal(RecordID.metadata.rawValue),
        // Major version
        .fixed(bitWidth: 16),
        // Minor version
        .fixed(bitWidth: 16),
        // Frontend version
        .blob,
      ])
      self.abbreviate(.moduleDepGraphNode, [
        .literal(RecordID.moduleDepGraphNode.rawValue),
        // dependency kind discriminator
        .fixed(bitWidth: 3),
        // dependency decl aspect discriminator
        .fixed(bitWidth: 1),
        // dependency context
        .vbr(chunkBitWidth: 13),
        // dependency name
        .vbr(chunkBitWidth: 13),
        // swiftdeps?
        .fixed(bitWidth: 1),
        // swiftdeps path
        .vbr(chunkBitWidth: 13),
        // fingerprint?
        .fixed(bitWidth: 1),
        // fingerprint bytes
        .blob,
      ])
      self.abbreviate(.dependsOnNode, [
        .literal(RecordID.dependsOnNode.rawValue),
        // dependency kind discriminator
        .fixed(bitWidth: 3),
        // dependency decl aspect discriminator
        .fixed(bitWidth: 1),
        // dependency context
        .vbr(chunkBitWidth: 13),
        // dependency name
        .vbr(chunkBitWidth: 13),
      ])

      self.abbreviate(.useIDNode, [
        .literal(RecordID.useIDNode.rawValue),
        // node ID
        .vbr(chunkBitWidth: 13),
      ])
      self.abbreviate(.externalDepNode, [
        .literal(RecordID.externalDepNode.rawValue),
        // path ID
        .vbr(chunkBitWidth: 13),
        // fingerprint?
        .fixed(bitWidth: 1),
        // fingerprint bytes
        .blob
      ])
      self.abbreviate(.identifierNode, [
        .literal(RecordID.identifierNode.rawValue),
        // identifier data
        .blob
      ])
      self.abbreviate(.mapNode, [
        .literal(RecordID.mapNode.rawValue),
        // input name
        .vbr(chunkBitWidth: 13),
        // dependencySource name
        .vbr(chunkBitWidth: 13),
      ])
    }

    private func abbreviate(
      _ record: RecordID,
      _ operands: [Bitstream.Abbreviation.Operand]
    ) {
      self.abbreviations[record]
        = self.stream.defineAbbreviation(Bitstream.Abbreviation(operands))
    }

    public static func serialize(
      _ graph: ModuleDependencyGraph,
      _ compilerVersion: String
    ) -> ByteString {
      let serializer = Serializer(compilerVersion: compilerVersion)
      serializer.emitSignature()
      serializer.writeBlockInfoBlock()

      serializer.stream.withSubBlock(.firstApplicationID, abbreviationBitWidth: 8) {
        serializer.registerAbbreviations()

        serializer.writeMetadata()

        serializer.populateCaches(from: graph)

        graph.nodeFinder.forEachNode { node in
          serializer.stream.writeRecord(serializer.abbreviations[.moduleDepGraphNode]!, {
            $0.append(RecordID.moduleDepGraphNode)
            $0.append(node.key.designator.code)
            $0.append(node.key.aspect.code)
            $0.append(serializer.lookupIdentifierCode(
                        for: node.key.designator.context ?? ""))
            $0.append(serializer.lookupIdentifierCode(
                        for: node.key.designator.name ?? ""))
            $0.append((node.dependencySource != nil) ? UInt32(1) : UInt32(0))
            $0.append(serializer.lookupIdentifierCode(
                        for: node.dependencySource?.file.name ?? ""))
            $0.append((node.fingerprint != nil) ? UInt32(1) : UInt32(0))
          }, blob: node.fingerprint ?? "")
        }

        for key in graph.nodeFinder.usesByDef.keys {
          serializer.stream.writeRecord(serializer.abbreviations[.dependsOnNode]!) {
            $0.append(RecordID.dependsOnNode)
            $0.append(key.designator.code)
            $0.append(key.aspect.code)
            $0.append(serializer.lookupIdentifierCode(
                        for: key.designator.context ?? ""))
            $0.append(serializer.lookupIdentifierCode(
                        for: key.designator.name ?? ""))
          }
          for use in graph.nodeFinder.usesByDef[key, default: []] {
            guard let useID = serializer.nodeIDs[use] else {
              fatalError("Node ID was not registered! \(use)")
            }

            serializer.stream.writeRecord(serializer.abbreviations[.useIDNode]!) {
              $0.append(RecordID.useIDNode)
              $0.append(UInt32(useID))
            }
          }
        }
        for (input, dependencySource) in graph.inputDependencySourceMap {
          serializer.stream.writeRecord(serializer.abbreviations[.mapNode]!) {
            $0.append(RecordID.mapNode)
            $0.append(serializer.lookupIdentifierCode(for: input.file.name))
            $0.append(serializer.lookupIdentifierCode(for: dependencySource.file.name))
          }
        }

        for fingerprintedExternalDependency in graph.fingerprintedExternalDependencies {
          serializer.stream.writeRecord(serializer.abbreviations[.externalDepNode]!, {
            $0.append(RecordID.externalDepNode)
            $0.append(serializer.lookupIdentifierCode(
                        for: fingerprintedExternalDependency.externalDependency.file.name))
            $0.append((fingerprintedExternalDependency.fingerprint != nil) ? UInt32(1) : UInt32(0))
          }, 
          blob: (fingerprintedExternalDependency.fingerprint ?? ""))
        }
      }
      return ByteString(serializer.stream.data)
    }
  }
}

fileprivate extension DependencyKey.DeclAspect {
  init?(_ c: UInt64) {
    switch c {
    case 0:
      self = .interface
    case 1:
      self = .implementation
    default:
      return nil
    }
  }

  var code: UInt32 {
    switch self {
    case .interface:
      return 0
    case .implementation:
      return 1
    }
  }
}

fileprivate extension DependencyKey.Designator {
  init(kindCode: UInt64, context: String, name: String, fileSystem: FileSystem) throws {
    func mustBeEmpty(_ s: String) throws {
      guard s.isEmpty else {
        throw ModuleDependencyGraph.ReadError.bogusNameOrContext
      }
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
      self = .externalDepend(try ExternalDependency(name))
    case 6:
      try mustBeEmpty(context)
      self = .sourceFileProvide(name: name)
    default: throw ModuleDependencyGraph.ReadError.unknownKind
    }
  }

  var code: UInt32 {
    switch self {
    case .topLevel(name: _):
      return 0
    case .nominal(context: _):
      return 1
    case .potentialMember(context: _):
      return 2
    case .member(context: _, name: _):
      return 3
    case .dynamicLookup(name: _):
      return 4
    case .externalDepend(_):
      return 5
    case .sourceFileProvide(name: _):
      return 6
    }
  }
}

extension Diagnostic.Message {
  fileprivate static func error_could_not_write_dep_graph(
    to path: VirtualPath
  ) -> Diagnostic.Message {
    .error("could not write driver dependency graph to \(path)")
  }
}

// MARK: - Checking Serialization

extension ModuleDependencyGraph {
  func matches(_ other: ModuleDependencyGraph) -> Bool {
    guard nodeFinder.matches(other.nodeFinder),
          inputDependencySourceMap.matches(other.inputDependencySourceMap),
          fingerprintedExternalDependencies.matches(other.fingerprintedExternalDependencies)
    else {
      return false
    }
    return true
  }
}

extension Set where Element == ModuleDependencyGraph.Node {
  fileprivate func matches(_ other: Self) -> Bool {
    self == other
  }
}

extension BidirectionalMap where T1 == TypedVirtualPath, T2 == DependencySource {
  fileprivate func matches(_ other: Self) -> Bool {
    self == other
  }
}

extension Set where Element == FingerprintedExternalDependency {
  fileprivate func matches(_ other: Self) -> Bool {
    self == other
  }
}

/// This should be in a test file, but addMapEntry should be private.
extension ModuleDependencyGraph {
  func mockMapEntry(
    _ mockInput: TypedVirtualPath,
    _ mockDependencySource: DependencySource
  ) {
    addMapEntry(mockInput, mockDependencySource)
  }
}
