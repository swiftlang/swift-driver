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
  
  /// Maps input files (e.g. .swift) to and from the DependencySource object.
  @_spi(Testing) public private(set) var inputDependencySourceMap = InputDependencySourceMap()

  // The set of paths to external dependencies known to be in the graph
  public internal(set) var fingerprintedExternalDependencies = Set<FingerprintedExternalDependency>()

  /// A lot of initial state that it's handy to have around.
  @_spi(Testing) public let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup

  /// For debugging, something to write out files for visualizing graphs
  let dotFileWriter: DependencyGraphDotFileWriter?

  @_spi(Testing) public var phase: Phase

  /// The phase when the graph was created. Used to help diagnose later failures
  let creationPhase: Phase

  /// Minimize the number of file system modification-time queries.
  private var externalDependencyModTimeCache = [ExternalDependency: Bool]()

  public init(_ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup,
              _ phase: Phase
  ) {
    self.info = info
    self.dotFileWriter = info.emitDependencyDotFileAfterEveryImport
    ? DependencyGraphDotFileWriter(info)
    : nil
    self.phase = phase
    self.creationPhase = phase
  }

  @_spi(Testing) public func source(requiredFor input: TypedVirtualPath,
                                    function: String = #function,
                                    file: String = #file,
                                    line: Int = #line) -> DependencySource {
    guard let source = inputDependencySourceMap.sourceIfKnown(for: input)
    else {
      fatalError("\(input.file.basename) not found in inputDependencySourceMap, \(file):\(line) in \(function)")
    }
    return source
  }

  @_spi(Testing) public func input(neededFor source: DependencySource) -> TypedVirtualPath? {
    guard let input = inputDependencySourceMap.input(ifKnownFor: source)
    else {
      info.diagnosticEngine.emit(warning: "Failed to find source file for '\(source.file.basename)', recovering with a full rebuild. Next build will be incremental.")
      return nil
    }
    return input
  }
}

extension ModuleDependencyGraph {
  public enum Phase {
    case
    buildingWithoutAPrior,
    updatingFromAPrior,
    updatingAfterCompilation,
    buildingAfterEachCompilation

    var isUpdating: Bool {
      switch self {
      case .buildingWithoutAPrior, .buildingAfterEachCompilation:
        return false
      case .updatingAfterCompilation, .updatingFromAPrior:
        return true
      }
    }

    var shouldNewExternalDependenciesTriggerInvalidation: Bool {
      switch self {
      case .buildingWithoutAPrior:
       // Reading graph from a swiftdeps file,
        // so every incremental external dependency found will be new to the
        // graph. Don't invalidate just 'cause it's new.
        return false

      case .buildingAfterEachCompilation:
        // Will be compiling every file, so no need to invalidate based on
        // found external dependencies.
        return false

        // Reading a swiftdeps file after a compilation.
        // A new external dependency represents an addition.
        // So must invalidate based on it.
      case .updatingAfterCompilation:
        return true

      case .updatingFromAPrior:
        // If the graph was read from priors,
        // then any new external dependency must also be an addition.
        return true
      }
    }

    var isCompilingAllInputsNoMatterWhat: Bool {
      switch self {
      case .buildingAfterEachCompilation:
        return true
      case .buildingWithoutAPrior, .updatingFromAPrior, .updatingAfterCompilation:
        return false
      }
    }
  }
}

// MARK: - Building from swiftdeps
extension ModuleDependencyGraph {
  /// Integrates `input` as needed and returns any inputs that were invalidated by external dependencies
  /// When creating a graph from swiftdeps files, this operation is performed for each input.
  func collectInputsRequiringCompilationFromExternalsFoundByCompiling(
    input: TypedVirtualPath
  ) -> TransitivelyInvalidatedInputSet? {
    // do not try to read swiftdeps of a new input
    if info.sourceFiles.isANewInput(input.file) {
      return TransitivelyInvalidatedInputSet()
    }
    return collectInputsRequiringCompilationAfterProcessing(
      dependencySource: source(requiredFor: input))
  }
}

// MARK: - Getting a graph read from priors ready to use
extension ModuleDependencyGraph {
  func collectNodesInvalidatedByChangedOrAddedExternals() -> DirectlyInvalidatedNodeSet {
    fingerprintedExternalDependencies.reduce(into: DirectlyInvalidatedNodeSet()) {
      invalidatedNodes, fed in
      invalidatedNodes.formUnion(self.integrateExternal(.known(fed)))
    }
  }
}

// MARK: - Scheduling the first wave
extension ModuleDependencyGraph {
  /// Find all the sources that depend on `sourceFile`. For some source files, these will be
  /// speculatively scheduled in the first wave.
  func collectInputsInvalidatedBy(input: TypedVirtualPath
  ) -> TransitivelyInvalidatedInputArray {
    let changedSource = source(requiredFor: input)
    let allDependencySourcesToRecompile =
      collectSwiftDepsUsing(dependencySource: changedSource)

    return allDependencySourcesToRecompile.compactMap {
      depedencySource in
      guard depedencySource != changedSource else {return nil}
      let dependentInput = inputDependencySourceMap.input(ifKnownFor: depedencySource)
      info.reporter?.report(
        "Found dependent of \(input.file.basename):", dependentInput)
      return dependentInput
    }
  }

  /// Find all the swiftDeps files that depend on `dependencySource`.
  /// Really private, except for testing.
  /*@_spi(Testing)*/ public func collectSwiftDepsUsing(
    dependencySource: DependencySource
  ) -> TransitivelyInvalidatedSourceSet {
    let nodes = nodeFinder.findNodes(for: dependencySource) ?? [:]
    /// Tests expect this to be reflexive
    return collectSwiftDepsUsingInvalidated(nodes: DirectlyInvalidatedNodeSet(nodes.values))
  }

  /// Does the graph contain any dependency nodes for a given source-code file?
  func containsNodes(forSourceFile file: TypedVirtualPath) -> Bool {
    precondition(file.type == .swift)
    guard let source = inputDependencySourceMap.sourceIfKnown(for: file) else {
      return false
    }
    return containsNodes(forDependencySource: source)
  }

  func containsNodes(forDependencySource source: DependencySource) -> Bool {
    return nodeFinder.findNodes(for: source).map {!$0.isEmpty}
      ?? false
  }
  
  /// Returns: false on error
  func populateInputDependencySourceMap(
    for purpose: InputDependencySourceMap.AdditionPurpose
  ) -> Bool {
    let ofm = info.outputFileMap
    let diags = info.diagnosticEngine
    var allFound = true
    for input in info.inputFiles {
      if let source = ofm.dependencySource(for: input, diagnosticEngine: diags) {
        inputDependencySourceMap.addEntry(input, source, for: purpose)
      } else {
        // Don't break in order to report all failures.
        allFound = false
      }
    }
    return allFound
  }
}
extension OutputFileMap {
  fileprivate func dependencySource(
    for sourceFile: TypedVirtualPath,
    diagnosticEngine: DiagnosticsEngine
  ) -> DependencySource? {
    assert(sourceFile.type == FileType.swift)
    guard let swiftDepsPath = existingOutput(inputFile: sourceFile.fileHandle,
                                             outputType: .swiftDeps)
    else {
      // The legacy driver fails silently here.
      diagnosticEngine.emit(
        .remarkDisabled("\(sourceFile.file.basename) has no swiftDeps file")
      )
      return nil
    }
    assert(VirtualPath.lookup(swiftDepsPath).extension == FileType.swiftDeps.rawValue)
    let typedSwiftDepsFile = TypedVirtualPath(file: swiftDepsPath, type: .swiftDeps)
    return DependencySource(typedSwiftDepsFile)
  }
}

// MARK: - Scheduling the 2nd wave
extension ModuleDependencyGraph {
  /// After `source` has been compiled, figure out what other source files need compiling.
  /// Used to schedule the 2nd wave.
  /// Return nil in case of an error.
  /// May return a source that has already been compiled.
  func collectInputsRequiringCompilation(byCompiling input: TypedVirtualPath
  ) -> TransitivelyInvalidatedInputSet? {
    precondition(input.type == .swift)
    let dependencySource = source(requiredFor: input)
    return collectInputsRequiringCompilationAfterProcessing(
      dependencySource: dependencySource)
  }
}

// MARK: - Scheduling either wave
extension ModuleDependencyGraph {
  
  /// Given a set of invalidated nodes, find all swiftDeps dependency sources containing defs that transitively use
  /// any of the invalidated nodes.
  /*@_spi(Testing)*/
  public func collectSwiftDepsUsingInvalidated(
    nodes: DirectlyInvalidatedNodeSet
  ) -> TransitivelyInvalidatedSourceSet
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
    return affectedNodes.reduce(into: TransitivelyInvalidatedSourceSet()) {
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
  /*@_spi(Testing)*/ public func collectUntracedNodes(
    from fingerprintedExternalDependency: FingerprintedExternalDependency,
    _ why: ExternalDependency.InvalidationReason
  ) -> DirectlyInvalidatedNodeSet {
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
    let untracedUses = DirectlyInvalidatedNodeSet(
      nodeFinder
        .uses(of: node)
        .filter({ use in use.isUntraced }))
    info.reporter?.reportInvalidated(untracedUses, by: fingerprintedExternalDependency.externalDependency, why)
    return untracedUses
  }

  /// Find all the inputs known to need recompilation as a consequence of reading a swiftdeps or swiftmodule
  /// `dependencySource` - The file to read containing dependency information
  /// Returns `nil` on error
  private func collectInputsRequiringCompilationAfterProcessing(
    dependencySource: DependencySource
  ) -> TransitivelyInvalidatedInputSet? {
    assert(dependencySource.typedFile.type == .swiftDeps)
    guard let sourceGraph = dependencySource.read(in: info.fileSystem,
                                                  reporter: info.reporter)
    else {
      // to preserve legacy behavior cancel whole thing
      info.diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "malformed dependencies file '\(dependencySource.typedFile)'"))
      return nil
    }
    let invalidatedNodes = Integrator.integrate(from: sourceGraph, into: self)
    return collectInputsUsingInvalidated(nodes: invalidatedNodes)
  }

  /// Computes the set of inputs that must be recompiled as a result of the
  /// invalidation of the given list of nodes.
  ///
  /// If the set of invalidated nodes could not be computed because of a failure
  /// to match a swiftdeps file to its corresponding input file, this function
  /// return `nil`. This can happen when e.g. the build system changes the
  /// entries in the output file map out from under us.
  ///
  /// - Parameter directlyInvalidatedNodes: The set of invalidated nodes.
  /// - Returns: The set of inputs that were transitively invalidated, if
  ///            possible. Or `nil` if such a set could not be computed.
  func collectInputsUsingInvalidated(
    nodes directlyInvalidatedNodes: DirectlyInvalidatedNodeSet
  ) -> TransitivelyInvalidatedInputSet? {
    var invalidatedInputs = TransitivelyInvalidatedInputSet()
    for invalidatedSwiftDeps in collectSwiftDepsUsingInvalidated(nodes: directlyInvalidatedNodes) {
      guard let invalidatedInput = input(neededFor: invalidatedSwiftDeps) else {
        return nil
      }
      invalidatedInputs.insert(invalidatedInput)
    }
    return invalidatedInputs
  }
}

// MARK: - Integrating External Dependencies

extension ModuleDependencyGraph {
  /// The kinds of external dependencies available to integrate.
  enum ExternalIntegrand {
    /// A `known` integrand is known to be present in the graph and requires
    /// only a mod-time check to determine if it is up to date.
    case known(FingerprintedExternalDependency)
    /// An `unknown` integrand is not, up to this point, known to the dependency
    /// graph. This models the addition of an import that is discovered during
    /// the incremental build.
    case unknown(FingerprintedExternalDependency)

    var externalDependency: FingerprintedExternalDependency {
      switch self {
      case .known(let fed): return fed
      case .unknown(let fed): return fed
      }
    }

    var isKnown: Bool {
      switch self {
      case .known(_): return true
      case .unknown(_): return false
      }
    }
  }

  /// Collects the nodes invalidated by a change to the given external
  /// dependency after integrating it into the dependency graph.
  ///
  /// This function does not to the transitive closure; that is left to the
  /// callers.
  ///
  /// - Parameters:
  ///   - integrand: The external dependency to integrate.
  ///   - isKnown: If `true`, the caller is aware of this node and
  ///              integration should assume it is a known external.
  ///              If `false`, and the external has not been
  ///              integrated before, it is treated as a freshly-
  ///              added external dependency.
  /// - Returns: The set of module dependency graph nodes invalidated by integration.
  func integrateExternal(
    _ integrand: ExternalIntegrand
  ) -> DirectlyInvalidatedNodeSet {
    guard let whyInvalidate = self.invalidationReason(for: integrand) else {
      return DirectlyInvalidatedNodeSet()
    }

    if self.info.isCrossModuleIncrementalBuildEnabled {
      if let ii = integrateIncrementalImport(of: integrand.externalDependency, whyInvalidate) {
        return ii
      }
    }

    // If we're compiling everything anyways, there's no need to trace.
    // FIXME: Seems like
    // 1) We could set this flag a lot earlier in some cases
    // 2) It should apply to incremental imports as well.
    guard !self.phase.isCompilingAllInputsNoMatterWhat else {
      return DirectlyInvalidatedNodeSet()
    }
    return collectUntracedNodes(from: integrand.externalDependency, whyInvalidate)
  }

  /// Figure out the reason to invalidate or process a dependency.
  ///
  /// Even if invalidation won't be reported to the caller, a new or added
  /// incremental external dependencies may require integration in order to
  /// transitively close them, (e.g. if an imported module imports a module).
  private func invalidationReason(
    for fed: ExternalIntegrand
  ) -> ExternalDependency.InvalidationReason? {
    let isNewToTheGraph = !fed.isKnown && fingerprintedExternalDependencies.insert(fed.externalDependency).inserted
    if self.phase.shouldNewExternalDependenciesTriggerInvalidation && isNewToTheGraph {
      return .added
    }

    if self.hasFileChanged(fed.externalDependency.externalDependency) {
      return .changed
    }
    return nil
  }

  private func hasFileChanged(_ externalDependency: ExternalDependency) -> Bool {
    if let hasChanged = externalDependencyModTimeCache[externalDependency] {
      return hasChanged
    }
    guard let depFile = externalDependency.path else {
      return true
    }
    let fileModTime = (try? info.fileSystem.lastModificationTime(for: depFile)) ?? .distantFuture
    let hasChanged = fileModTime >= info.buildStartTime
    externalDependencyModTimeCache[externalDependency] = hasChanged
    return hasChanged
  }

  /// Try to read and integrate an external dependency.
  /// Return nil if it's not incremental, or if an error occurs.
  private func integrateIncrementalImport(
    of fed: FingerprintedExternalDependency,
    _ why: ExternalDependency.InvalidationReason
  ) -> DirectlyInvalidatedNodeSet? {
    guard
      let source = fed.incrementalDependencySource,
      let unserializedDepGraph = source.read(in: info.fileSystem, reporter: info.reporter)
    else {
      return nil
    }
    let invalidatedNodes = Integrator.integrate(from: unserializedDepGraph, into: self)
    info.reporter?.reportInvalidated(invalidatedNodes, by: fed.externalDependency, why)
    return invalidatedNodes
  }
}

// MARK: - tracking traced nodes
extension ModuleDependencyGraph {

 func ensureGraphWillRetrace(_ nodes: DirectlyInvalidatedNodeSet) {
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
    info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
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
      private var nodeUses: [(DependencyKey, Int)] = []
      private var inputDependencySourceMap: [(TypedVirtualPath, DependencySource)] = []
      public private(set) var allNodes: [Node] = []

      init(_ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup) {
        self.fileSystem = info.fileSystem
        self.graph = ModuleDependencyGraph(info, .updatingFromAPrior)
      }

      func finalizeGraph() -> ModuleDependencyGraph {
        for (dependencyKey, useID) in self.nodeUses {
          let isNewUse = self.graph.nodeFinder
            .record(def: dependencyKey, use: self.allNodes[useID])
          assert(isNewUse, "Duplicate use def-use arc in graph?")
        }
        for (input, dependencySource) in inputDependencySourceMap {
          graph.inputDependencySourceMap.addEntry(input,
                                                  dependencySource,
                                                  for: .readingPriors)
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
                  .map({ try VirtualPath.intern(path: $0) })
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
          self.nodeUses.append( (key, Int(record.fields[0])) )
        case .mapNode:
          guard record.fields.count == 2,
                record.fields[0] < identifiers.count,
                record.fields[1] < identifiers.count
          else {
            throw ReadError.malformedModuleDepGraphNodeRecord
          }
          let inputPathString = identifiers[Int(record.fields[0])]
          let dependencySourcePathString = identifiers[Int(record.fields[1])]
          let inputHandle = try VirtualPath.intern(path: inputPathString)
          let inputPath = VirtualPath.lookup(inputHandle)
          let dependencySourceHandle = try VirtualPath.intern(path: dependencySourcePathString)
          let dependencySourcePath = VirtualPath.lookup(dependencySourceHandle)
          guard inputPath.extension == FileType.swift.rawValue,
                dependencySourcePath.extension == FileType.swiftDeps.rawValue,
                let dependencySource = DependencySource(dependencySourceHandle)
          else {
            throw ReadError.malformedMapRecord
          }
          let input = TypedVirtualPath(file: inputHandle, type: .swift)
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
          self.graph.fingerprintedExternalDependencies.insert(
            FingerprintedExternalDependency(ExternalDependency(fileName: path), fingerprint))
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
  /// - Returns: true if had error
  @_spi(Testing) public func write(
    to path: VirtualPath,
    on fileSystem: FileSystem,
    compilerVersion: String
  ) throws {
    let data = ModuleDependencyGraph.Serializer.serialize(self, compilerVersion)

    do {
      try fileSystem.writeFileContents(path,
                                       bytes: data,
                                       atomically: true)
    } catch {
      throw IncrementalCompilationState.WriteDependencyGraphError.couldNotWrite(
        path: path, error: error)
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

      graph.inputDependencySourceMap.enumerateToSerializePriors { input, dependencySource in
        self.addIdentifier(input.file.name)
        self.addIdentifier(dependencySource.file.name)
      }

      for edF in graph.fingerprintedExternalDependencies {
        self.addIdentifier(edF.externalDependency.fileName)
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
        graph.inputDependencySourceMap.enumerateToSerializePriors {
          input, dependencySource in
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
                        for: fingerprintedExternalDependency.externalDependency.fileName))
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
      self = .externalDepend(ExternalDependency(fileName: name))
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

extension InputDependencySourceMap {
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
  @_spi(Testing) public func mockMapEntry(
    _ mockInput: TypedVirtualPath,
    _ mockDependencySource: DependencySource
  ) {
    inputDependencySourceMap.addEntry(mockInput, mockDependencySource, for: .mocking)
  }
}
