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

import SwiftOptions

import protocol TSCBasic.FileSystem
import struct TSCBasic.ByteString
import class Dispatch.DispatchQueue
import struct Foundation.TimeInterval

// MARK: - ModuleDependencyGraph

/// Holds all the dependency relationships in this module, and declarations in other modules that
/// are depended-upon.
/*@_spi(Testing)*/ public final class ModuleDependencyGraph: InternedStringTableHolder {
  /// The build record information associated with this module dependency graph.
  ///
  /// This data reflects the result of the _prior_ compilation. Consult
  /// ``BuildRecordInfo`` for data from the in-flight compilation session.
  @_spi(Testing) public let buildRecord: BuildRecord

  /// Supports finding nodes in two ways.
  @_spi(Testing) public var nodeFinder: NodeFinder

  // The set of paths to external dependencies known to be in the graph
  public internal(set) var fingerprintedExternalDependencies:  Set<FingerprintedExternalDependency>

  /// A lot of initial state that it's handy to have around.
  @_spi(Testing) public let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup

  /// For debugging, something to write out files for visualizing graphs
  var dotFileWriter: DependencyGraphDotFileWriter?

  @_spi(Testing) public fileprivate(set) var phase: Phase

  @_spi(Testing) public func setPhase(to newPhase: Phase) {
    mutationSafetyPrecondition()
    self.phase = newPhase
  }

  /// The phase when the graph was created. Used to help diagnose later failures
  let creationPhase: Phase

  fileprivate var currencyCache: ExternalDependencyCurrencyCache

  /// To speed all the node insertions and lookups, intern all the strings.
  /// Put them here because it matches the concurrency constraints; just as modifications to this graph
  /// are serialized, so must all the mods to this table be.
  @_spi(Testing) public let internedStringTable: InternedStringTable

  private init(
    _ buildRecord: BuildRecord,
    _ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup,
    _ phase: Phase,
    _ internedStringTable: InternedStringTable,
    _ nodeFinder: NodeFinder,
    _ fingerprintedExternalDependencies: Set<FingerprintedExternalDependency>
  ) {
    self.buildRecord = buildRecord
    self.currencyCache = ExternalDependencyCurrencyCache(
      info.fileSystem, buildStartTime: buildRecord.buildStartTime)
    self.info = info
    self.dotFileWriter = info.emitDependencyDotFileAfterEveryImport
      ? DependencyGraphDotFileWriter(info)
      : nil
    self.phase = phase
    self.creationPhase = phase
    self.internedStringTable = internedStringTable
    self.nodeFinder = nodeFinder
    self.fingerprintedExternalDependencies = fingerprintedExternalDependencies
  }

  private convenience init(
    _ buildRecord: BuildRecord,
    _ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup,
    _ phase: Phase
  ) {
    assert(phase != .updatingFromAPrior,
           "If updating from prior, should be supplying more ingredients")
    self.init(buildRecord, info, phase, InternedStringTable(info.incrementalCompilationQueue),
              NodeFinder(),
              Set())
  }

  public static func createFromPrior(
    _ buildRecord: BuildRecord,
    _ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup,
    _ internedStringTable: InternedStringTable,
    _ nodeFinder: NodeFinder,
    _ fingerprintedExternalDependencies: Set<FingerprintedExternalDependency>
  ) -> Self {
    self.init(buildRecord,
              info,
              .updatingFromAPrior,
              internedStringTable,
              nodeFinder,
              fingerprintedExternalDependencies)
  }

  public static func createForBuildingFromSwiftDeps(
    _ buildRecord: BuildRecord,
    _ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
  ) -> Self {
    self.init(buildRecord, info, .buildingFromSwiftDeps)
  }
  public static func createForBuildingAfterEachCompilation(
    _ buildRecord: BuildRecord,
    _ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
  ) -> Self {
    self.init(buildRecord, info, .buildingAfterEachCompilation)
  }
  public static func createForSimulatingCleanBuild(
    _ buildRecord: BuildRecord,
    _ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
  ) -> Self {
    self.init(buildRecord, info, .updatingAfterCompilation)
  }
}

extension ModuleDependencyGraph: IncrementalCompilationSynchronizer  {
  @_spi(Testing) public var incrementalCompilationQueue: DispatchQueue {
    info.incrementalCompilationQueue
  }
}

extension ModuleDependencyGraph {
  public enum Phase {
    /// Building a graph from swiftdeps files, will never do this if incremental imports are enabled.
    case buildingFromSwiftDeps

    /// Building a graph by reading a prior graph
    /// and updating for changed external dependencies
    case updatingFromAPrior

    /// Updating a graph from a `swiftdeps` file for an input that was just compiled
    /// Or, updating a graph from a `swiftmodule` file (i.e. external dependency) that was transitively found to be
    /// added as the `swiftdeps` file was processed.
    case updatingAfterCompilation

    /// This is a clean incremental build. All inputs are being compiled and after each compilation,
    /// the graph is being built from the new `swiftdeps` file.
    case buildingAfterEachCompilation

    var isUpdating: Bool {
      switch self {
      case .buildingFromSwiftDeps, .buildingAfterEachCompilation:
        return false
      case .updatingAfterCompilation, .updatingFromAPrior:
        return true
      }
    }

    var isWholeGraphPresent: Bool {
      !isBuilding
    }

    var isBuilding: Bool {
      switch self {
      case .buildingFromSwiftDeps, .buildingAfterEachCompilation: return true
      case .updatingFromAPrior, .updatingAfterCompilation: return false
      }
    }
  }
}

// MARK: - Building from swiftdeps
extension ModuleDependencyGraph {
  /// Integrates `input` as needed and returns any inputs that were invalidated by external dependencies
  /// When creating a graph from swiftdeps files, this operation is performed for each input.
  func collectInputsRequiringCompilationFromExternalsFoundByCompiling(
    input: SwiftSourceFile
  ) -> TransitivelyInvalidatedSwiftSourceFileSet? {
    // do not try to read swiftdeps of a new input
    guard self.buildRecord.inputInfos[input.typedFile.file] != nil else {
      return TransitivelyInvalidatedSwiftSourceFileSet()
    }
    return self.collectInputsRequiringCompilationAfterProcessing(input: input)
  }
}

// MARK: - Getting a graph read from priors ready to use
extension ModuleDependencyGraph {
  func collectNodesInvalidatedByChangedOrAddedExternals() -> DirectlyInvalidatedNodeSet {
    fingerprintedExternalDependencies.reduce(into: DirectlyInvalidatedNodeSet()) {
      invalidatedNodes, fed in
      invalidatedNodes.formUnion(self.findNodesInvalidated(
        by: ExternalIntegrand(fed, shouldBeIn: self)))
    }
  }
}

// MARK: - Scheduling the first wave
extension ModuleDependencyGraph {
  /// Find all the sources that depend on `changedInput`.
  ///
  /// For some source files, these will be speculatively scheduled in the first wave.
  /// - Parameter changedInput: The input file that changed since the last build
  /// - Returns: The input files that must be recompiled, excluding `changedInput`
  func collectInputsInvalidatedBy(changedInput: SwiftSourceFile
  ) -> TransitivelyInvalidatedSwiftSourceFileArray {
    accessSafetyPrecondition()
    let changedSource = DependencySource(changedInput, internedStringTable)
    let allUses = collectInputsUsing(dependencySource: changedSource)

    return allUses.filter {
      user in
      guard user != changedInput else {return false}
      info.reporter?.report(
        "Found dependent of \(changedInput.typedFile.file.basename):", user)
      return true
    }
  }

  /// Find all the input files that depend on `dependencySource`.
  /// Really private, except for testing.
  /*@_spi(Testing)*/ public func collectInputsUsing(
    dependencySource: DependencySource
  ) -> TransitivelyInvalidatedSwiftSourceFileSet {
    accessSafetyPrecondition()
    let nodes = nodeFinder.findNodes(for: .known(dependencySource)) ?? [:]
    /// Tests expect this to be reflexive
    return collectInputsUsingInvalidated(nodes: DirectlyInvalidatedNodeSet(nodes.values))
  }

  /// Does the graph contain any dependency nodes for a given source-code file?
  func containsNodes(forSourceFile file: SwiftSourceFile) -> Bool {
    accessSafetyPrecondition()
    return containsNodes(forDependencySource: DependencySource(file, internedStringTable))
  }

  private func containsNodes(forDependencySource source: DependencySource) -> Bool {
    accessSafetyPrecondition()
    return nodeFinder.findNodes(for: .known(source)).map {!$0.isEmpty}
      ?? false
  }
}


// MARK: - Scheduling the 2nd wave
extension ModuleDependencyGraph {
  /// After `source` has been compiled, figure out what other source files need compiling.
  /// Used to schedule the 2nd wave.
  ///
  /// - Parameter input: The file that has just been compiled
  /// - Returns: The input files that must be compiled now that `input` has been compiled.
  /// These may include inputs that do not need compilation because this build already compiled them.
  /// In case of an error, such as a missing entry in the `OutputFileMap`, nil is returned.
  @_spi(Testing) public func collectInputsRequiringCompilation(
    byCompiling input: SwiftSourceFile
  ) -> TransitivelyInvalidatedSwiftSourceFileSet? {
    return collectInputsRequiringCompilationAfterProcessing(input: input)
  }
}

// MARK: - Scheduling either wave
extension ModuleDependencyGraph {

  /// Given nodes that are invalidated, find all the affected inputs that must be recompiled.
  ///
  /// - Parameter nodes: A set of graph nodes for changed declarations.
  /// - Returns: All source files containing declarations that transitively depend upon the changed declarations.
  @_spi(Testing) public func collectInputsUsingInvalidated(
    nodes: DirectlyInvalidatedNodeSet
  ) -> TransitivelyInvalidatedSwiftSourceFileSet
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
    return affectedNodes.reduce(into: TransitivelyInvalidatedSwiftSourceFileSet()) {
      invalidatedInputs, affectedNode in
      if case let .known(source) = affectedNode.definitionLocation,
         let swiftSourceFile = SwiftSourceFile(ifSource: source.typedFile) {
        invalidatedInputs.insert(swiftSourceFile)
      }
    }
  }

  /// Given an external dependency & its fingerprint, find any nodes directly using that dependency.
  ///
  /// - Parameters:
  ///   - fingerprintedExternalDependency: the dependency to trace
  ///   - why: why the dependency must be traced
  /// - Returns: any nodes that directly use (depend upon) that external dependency.
  /// As an optimization, only return the nodes that have not been already traced, because the traced nodes
  /// will have already been used to schedule jobs to run.
  public func collectUntracedNodes(
    thatUse externalDefs: FingerprintedExternalDependency,
    _ why: ExternalDependency.InvalidationReason
  ) -> DirectlyInvalidatedNodeSet {
    // These nodes will depend on the *interface* of the external Decl.
    let key = DependencyKey(
      aspect: .interface,
      designator: .externalDepend(externalDefs.externalDependency))
    // DependencySource is OK as a nil placeholder because it's only used to find
    // the corresponding implementation node and there won't be any for an
    // external dependency node.
    let node = Node(key: key,
                    fingerprint: externalDefs.fingerprint,
                    definitionLocation: .unknown)
    accessSafetyPrecondition()
    let untracedUses = DirectlyInvalidatedNodeSet(
      nodeFinder
        .uses(of: node)
        .filter({ use in use.isUntraced }))
    info.reporter?.reportInvalidated(untracedUses, by: externalDefs.externalDependency, why)
    return untracedUses
  }

  /// Find all the inputs known to need recompilation as a consequence of processing a swiftdeps file.
  ///
  /// - Parameter input: The input file whose swiftdeps file contains the dependencies to be read and integrated.
  /// - Returns: `nil` on error, or the inputs discovered to be requiring compilation.
  private func collectInputsRequiringCompilationAfterProcessing(
    input: SwiftSourceFile
  ) -> TransitivelyInvalidatedSwiftSourceFileSet? {
    accessSafetyPrecondition()
    mutationSafetyPrecondition() // string table
    let dependencySource = DependencySource(input, internedStringTable)
    guard let sourceGraph = dependencySource.read(info: info,
                                                  internedStringTable: internedStringTable)
    else {
      // to preserve legacy behavior cancel whole thing
      info.diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "malformed dependencies file '\((try? dependencySource.fileToRead(info: info))?.file.name ?? "none?!")'"))
      return nil
    }
    let invalidatedNodes = Integrator.integrate(
      from: sourceGraph,
      dependencySource: dependencySource,
      into: self)
    return collectInputsInBuildUsingInvalidated(nodes: invalidatedNodes)
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
  func collectInputsInBuildUsingInvalidated(
    nodes directlyInvalidatedNodes: DirectlyInvalidatedNodeSet
  ) -> TransitivelyInvalidatedSwiftSourceFileSet? {
    var invalidatedInputs = TransitivelyInvalidatedSwiftSourceFileSet()
    for invalidatedInput in collectInputsUsingInvalidated(nodes: directlyInvalidatedNodes) {
      guard info.isPartOfBuild(invalidatedInput)
      else {
        info.diagnosticEngine.emit(.warning("Failed to find source file '\(invalidatedInput.typedFile.file.basename)' in command line, recovering with a full rebuild. Next build will be incremental."),
                                   location: nil)
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
    /// An `old` integrand is one that, when found, is known to already be in ``ModuleDependencyGraph/fingerprintedExternalDependencies``
    case old(FingerprintedExternalDependency)
    /// A `new` integrand is one that, when found was not already in ``ModuleDependencyGraph/fingerprintedExternalDependencies``
    case new(FingerprintedExternalDependency)

    init(_ fed: FingerprintedExternalDependency,
         in graph: ModuleDependencyGraph ) {
      graph.mutationSafetyPrecondition()
      self = graph.fingerprintedExternalDependencies.insert(fed).inserted
      ? .new(fed)
      : .old(fed)
    }

    init(_ fed: FingerprintedExternalDependency,
         shouldBeIn graph: ModuleDependencyGraph ) {
      graph.accessSafetyPrecondition()
      assert(graph.fingerprintedExternalDependencies.contains(fed))
      self = .old(fed)
    }


    var externalDependency: FingerprintedExternalDependency {
      switch self {
      case .new(let fed), .old(let fed): return fed
      }
    }
  }

  /// Find the nodes *directly* invalidated by some external dependency
  ///
  /// This function does not do the transitive closure; that is left to the callers.
  func findNodesInvalidated(
    by integrand: ExternalIntegrand
  ) -> DirectlyInvalidatedNodeSet {
    // If the integrand has no fingerprint, it's academic, cannot integrate it incrementally.
    guard integrand.externalDependency.fingerprint != nil else {
       return indiscriminatelyFindNodesInvalidated(by: integrand,
                                                   .missingFingerprint)
    }
    return incrementallyFindNodesInvalidated(by: integrand)
  }

  /// Collects the nodes invalidated by a change to the given external
  /// dependency after integrating it into the dependency graph.
  /// Use best-effort to integrate incrementally, by reading the `swiftmodule` file.
  ///
  /// This function does not do the transitive closure; that is left to the
  /// callers.
  ///
  /// - Parameter integrand: The external dependency to integrate.
  /// - Returns: The set of module dependency graph nodes invalidated by integration.
  func incrementallyFindNodesInvalidated(
    by integrand: ExternalIntegrand
  ) -> DirectlyInvalidatedNodeSet {
    accessSafetyPrecondition()
    // Better not be reading swiftdeps one-by-one for a selective compilation
    precondition(self.phase != .buildingFromSwiftDeps)

    guard let whyIntegrate = whyIncrementallyFindNodesInvalidated(by: integrand) else {
      return DirectlyInvalidatedNodeSet()
    }
    mutationSafetyPrecondition()
    return integrateIncrementalImport(of: integrand.externalDependency, whyIntegrate)
           ?? indiscriminatelyFindNodesInvalidated(by: integrand, .couldNotRead)
  }

  /// In order to report what happened in a sensible order, reify the reason for indiscriminately invalidating.
  private enum WhyIndiscriminatelyInvalidate: CustomStringConvertible {
    case incrementalImportsIsDisabled
    case missingFingerprint
    case couldNotRead

    var description: String {
      switch self {
      case .incrementalImportsIsDisabled: return "Incremental imports are disabled"
      case .missingFingerprint: return "No fingerprint in swiftmodule"
      case .couldNotRead: return "Could not read"
      }
    }
  }

  /// Collects the nodes invalidated by a change to the given external
  /// dependency after integrating it into the dependency graph.
  ///
  /// Do not try to be incremental; do not read the `swiftmodule` file.
  ///
  /// This function does not do the transitive closure; that is left to the
  /// callers.
  /// If called when incremental imports is enabled, it's a fallback.
  ///
  /// - Parameter integrand: The external dependency to integrate.
  /// - Returns: The set of module dependency graph nodes invalidated by integration.
  private func indiscriminatelyFindNodesInvalidated(
    by integrand: ExternalIntegrand, _ why: WhyIndiscriminatelyInvalidate
  ) -> DirectlyInvalidatedNodeSet {
    guard let reason = whyIndiscriminatelyFindNodesInvalidated(by: integrand)
    else {
      // Every single system swiftmodule can show up here, so don't report it.
      return DirectlyInvalidatedNodeSet()
    }
    info.reporter?.report("\(why.description): Invalidating all nodes in \(reason)", integrand)
    return collectUntracedNodes(thatUse: integrand.externalDependency, reason)
  }

  /// Figure out the reason to integrate, (i.e. process) a dependency that will be read and integrated.
  ///
  /// Even if invalidation won't be reported to the caller, a new or added
  /// incremental external dependencies may require integration in order to
  /// transitively close them, (e.g. if an imported module imports a module).
  ///
  /// - Parameter fed: The external dependency, with fingerprint and origin info to be integrated
  /// - Returns: nil if no integration is needed, or else why the integration is happening
  private func whyIncrementallyFindNodesInvalidated(
    by integrand: ExternalIntegrand
  ) -> ExternalDependency.InvalidationReason? {
    accessSafetyPrecondition()
    switch integrand {
    case .new:
      return .added
    case .old where self.currencyCache.isCurrent(integrand.externalDependency.externalDependency):
      // The most current version is already in the graph
      return nil
    case .old:
      return .newer
    }
  }

  /// Compute the reason for (non-incrementally) invalidating nodes
  ///
  /// Parameter integrand: The exernal dependency causing the invalidation
  /// - Returns: nil if no invalidation is needed, otherwise the reason.
  private func whyIndiscriminatelyFindNodesInvalidated(by integrand: ExternalIntegrand
  ) -> ExternalDependency.InvalidationReason? {
    accessSafetyPrecondition()
    switch self.phase {
    case .buildingFromSwiftDeps, .updatingFromAPrior:
      // If the external dependency has changed, better recompile any dependents
      return self.currencyCache.isCurrent(integrand.externalDependency.externalDependency)
      ? nil : .newer
    case .updatingAfterCompilation:
      // Since this file has been compiled anyway, no need
      return nil
    case .buildingAfterEachCompilation:
      // No need to do any invalidation; every file will be compiled anyway
      return nil
    }
  }

  /// Try to read and integrate an external dependency.
  ///
  /// - Returns: nil if an error occurs, or the set of directly affected nodes.
  private func integrateIncrementalImport(
    of fed: FingerprintedExternalDependency,
    _ why: ExternalDependency.InvalidationReason
  ) -> DirectlyInvalidatedNodeSet? {
    mutationSafetyPrecondition()
    guard
      let source = fed.incrementalDependencySource,
      let unserializedDepGraph = source.read(info: info,
                                             internedStringTable: internedStringTable)
    else {
      return nil
    }
    info.reporter?.report("Integrating \(why) incremental import", fed)
    // When doing incremental imports, never read the same swiftmodule twice
    self.currencyCache.beCurrent(fed.externalDependency)
    let invalidatedNodes = Integrator.integrate(
      from: unserializedDepGraph,
      dependencySource: source,
      into: self)
    info.reporter?.reportInvalidated(invalidatedNodes, by: fed.externalDependency, why)
    return invalidatedNodes
  }

  /// Remember if an external dependency need not be integrated in order to avoid redundant work.
  ///
  /// If using incremental imports, a given build should not read the same `swiftmodule` twice:
  /// Because when using incremental imports, the whole graph is present, a single read of a `swiftmodule`
  /// can invalidate any input file that depends on a changed external declaration.
  ///
  /// If not using incremental imports, a given build may have to invalidate nodes more than once for the same `swiftmodule`:
  /// For example, on a clean build, as each initial `swiftdeps` is integrated, if the file uses a changed `swiftmodule`,
  /// it must be scheduled for recompilation. Thus invalidation happens for every dependent input file.
  fileprivate struct ExternalDependencyCurrencyCache {
    private let fileSystem: FileSystem
    private let buildStartTime: TimePoint
    private var currencyCache = [ExternalDependency: Bool]()

    init(_ fileSystem: FileSystem, buildStartTime: TimePoint) {
      self.fileSystem = fileSystem
      self.buildStartTime = buildStartTime
    }

    mutating func beCurrent(_ externalDependency: ExternalDependency) {
      self.currencyCache[externalDependency] = true
    }

    mutating func isCurrent(_ externalDependency: ExternalDependency) -> Bool {
      if let cachedResult = self.currencyCache[externalDependency] {
        return cachedResult
      }
      let uncachedResult = isCurrentWRTFileSystem(externalDependency)
      self.currencyCache[externalDependency] = uncachedResult
      return uncachedResult
    }

    private func isCurrentWRTFileSystem(_ externalDependency: ExternalDependency) -> Bool {
      if let depFile = externalDependency.path,
         let fileModTime = try? self.fileSystem.lastModificationTime(for: depFile),
         fileModTime < self.buildStartTime {
        return true
      }
      return false
    }
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
  @_spi(Testing) public func verifyGraph() -> Bool {
    accessSafetyPrecondition()
    return nodeFinder.verify()
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
  ///
  /// - Minor number 1: Don't serialize the `inputDependencySourceMap`
  /// - Minor number 2: Use `.swift` files instead of `.swiftdeps` in ``DependencySource``
  /// - Minor number 3: Use interned strings, including for fingerprints and use empty dependency source file for no DependencySource
  /// - Minor number 4: Absorb the data in the ``BuildRecord`` into the module dependency graph.
  @_spi(Testing) public static let serializedGraphVersion = Version(1, 4, 0)

  /// The IDs of the records used by the module dependency graph.
  fileprivate enum RecordID: UInt64 {
    case metadata           = 1
    case moduleDepGraphNode = 2
    case dependsOnNode      = 3
    case useIDNode          = 4
    case externalDepNode    = 5
    case identifierNode     = 6
    case buildRecord        = 7
    case inputInfo          = 8

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
      case .buildRecord:
        return "BUILD_RECORD"
      case .inputInfo:
        return "INPUT_INFO"
      }
    }
  }

  @_spi(Testing) public enum ReadError: Error {
    case badMagic
    case noRecordBlock
    case malformedMetadataRecord
    case mismatchedSerializedGraphVersion(expected: Version, read: Version)
    case unexpectedMetadataRecord
    case unexpectedBuildRecord
    case malformedFingerprintRecord
    case malformedIdentifierRecord
    case malformedModuleDepGraphNodeRecord
    case malformedDependsOnRecord
    case malforedUseIDRecord
    case malformedMapRecord
    case malformedExternalDepNodeRecord
    case malformedBuildRecord
    case malformedInputInfo
    case unknownRecord
    case unexpectedSubblock
    case bogusNameOrContext
    case unknownKind
    case unknownDependencySourceExtension

    fileprivate init(forMalformed kind: RecordID) {
      switch kind {
      case .metadata:
        self = .malformedMetadataRecord
      case .moduleDepGraphNode:
        self = .malformedModuleDepGraphNodeRecord
      case .dependsOnNode:
        self = .malformedDependsOnRecord
      case .useIDNode:
        self = .malforedUseIDRecord
      case .externalDepNode:
        self = .malformedExternalDepNodeRecord
      case .identifierNode:
        self = .malformedIdentifierRecord
      case .buildRecord:
        self = .malformedBuildRecord
      case .inputInfo:
        self = .malformedInputInfo
      }
    }
  }

  /// Attempts to read a serialized dependency graph from the given path.
  ///
  /// - Parameters:
  ///   - path: The absolute path to the file to be read.
  ///   - fileSystem: The file system on which to search.
  ///   - info: The setup state
  /// - Throws: An error describing any failures to read the graph from the given file.
  /// - Returns: A fully deserialized ModuleDependencyGraph, or nil if nothing is there
  @_spi(Testing) public static func read(
    from path: VirtualPath,
    info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
  ) throws -> ModuleDependencyGraph? {
    guard let data = try serializedPriorGraph(from: path,
                                              info: info) else {
      return nil
    }
    let graph = try deserialize(data, info: info)
    info.reporter?.report("Read dependency graph", path)
    return graph
  }

  @_spi(Testing) public static func deserialize(
    _ data: ByteString,
    info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
  ) throws -> ModuleDependencyGraph {

    struct Visitor: BitstreamVisitor, IncrementalCompilationSynchronizer {
      private let info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
      private let internedStringTable: InternedStringTable
      var majorVersion: UInt64?
      var minorVersion: UInt64?
      var compilerVersionString: String?
      var argsHash: String?
      var buildStartTime: TimePoint = .distantPast
      var buildEndTime: TimePoint = .distantFuture
      var inputInfos: [VirtualPath: InputInfo] = [:]
      var expectedInputInfos: Int = 0

      private var currentDefKey: DependencyKey? = nil
      private var nodeUses: [(DependencyKey, Int)] = []
      private var fingerprintedExternalDependencies = Set<FingerprintedExternalDependency>()

      /// Deserialized nodes, in order appearing in the priors file. If `nil`, the node is for a removed source file.
      ///
      /// Since the def-use relationship is serialized according the index of the node in the priors file, this
      /// `Array` supports the deserialization of the def-use links by mapping index to node.
      /// The optionality of the contents lets the ``ModuleDependencyGraph/isForRemovedInput`` check to be cached.
      public private(set) var potentiallyUsedNodes: [Node?] = []

      private var nodeFinder = NodeFinder()

      var incrementalCompilationQueue: DispatchQueue {
        info.incrementalCompilationQueue
      }

      init(_ info: IncrementalCompilationState.IncrementalDependencyAndInputSetup) {
        self.info = info
        self.internedStringTable = InternedStringTable(info.incrementalCompilationQueue)
      }

      private var fileSystem: FileSystem {
        info.fileSystem
      }

      func finalizeGraph() -> ModuleDependencyGraph {
        mutationSafetyPrecondition()
        let record = BuildRecord(
          argsHash: self.argsHash!,
          swiftVersion: self.compilerVersionString!,
          buildStartTime: self.buildStartTime,
          buildEndTime: self.buildEndTime,
          inputInfos: self.inputInfos)
        assert(self.inputInfos.count == self.expectedInputInfos)
        let graph = ModuleDependencyGraph.createFromPrior(record,
                                                          info,
                                                          internedStringTable,
                                                          nodeFinder,
                                                          fingerprintedExternalDependencies)
        for (dependencyKey, useID) in self.nodeUses {
          guard let use = self.potentiallyUsedNodes[useID] else {
            // Don't record uses of defs of removed files.
            continue
          }
          let isNewUse = graph.nodeFinder
            .record(def: dependencyKey, use: use)
          assert(isNewUse, "Duplicate use def-use arc in graph?")
        }
        return graph
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
        mutationSafetyPrecondition()
        if isForRemovedInput(newNode) {
          // Preserve the mapping of Int to Node for reconstructing def-use links with a placeholder.
          self.potentiallyUsedNodes.append(nil)
          return
        }
        self.potentiallyUsedNodes.append(newNode)
        let oldNode = self.nodeFinder.insert(newNode)
        assert(oldNode == nil,
               "Integrated the same node twice: \(oldNode!), \(newNode)")
      }

      /// Determine whether (deserialized) node was for a definition in a source file that is no longer part of the build.
      ///
      /// If the priors were read from an invocation containing a subsequently removed input,
      /// the nodes defining decls from that input must be culled.
      ///
      /// - Parameter node: The (deserialized) node to test.
      /// - Returns: true iff the node corresponds to a definition on a removed source file.
      fileprivate func isForRemovedInput(_ node: Node) -> Bool {
        guard case let .known(dependencySource) = node.definitionLocation,
           dependencySource.typedFile.type == .swift // e.g., could be a .swiftdeps file
        else {
          return false
        }
        return !info.isPartOfBuild(SwiftSourceFile(dependencySource.typedFile))
      }

      mutating func visit(record: BitcodeElement.Record) throws {
        guard let kind = RecordID(rawValue: record.id) else {
          throw ReadError.unknownRecord
        }

        var malformedError: ReadError {.init(forMalformed: kind)}

        func stringIndex(field i: Int) throws -> Int {
          let u = record.fields[i]
          guard u < UInt64(internedStringTable.count) else {
            throw malformedError
          }
          return Int(u)
        }
        func internedString(field i: Int) throws -> InternedString {
          try InternedString(deserializedIndex: stringIndex(field: i))
        }
        func nonemptyInternedString(field i: Int) throws -> InternedString? {
          let s = try internedString(field: i)
          return s.isEmpty ? nil : s
        }
        func dependencyKey(kindCodeField: Int,
                           declAspectField: Int,
                           contextField: Int,
                           identifierField: Int
        ) throws -> DependencyKey {
          let kindCode = record.fields[kindCodeField]
          guard let declAspect = DependencyKey.DeclAspect(record.fields[declAspectField])
          else {
            throw malformedError
          }
          let context = try internedString(field: contextField)
          let identifier = try internedString(field: identifierField)
          let designator = try DependencyKey.Designator(
            kindCode: kindCode, context: context, name: identifier,
            internedStringTable: internedStringTable, fileSystem: fileSystem)
          return DependencyKey(aspect: declAspect, designator: designator)
        }

        switch kind {
        case .metadata:
          // If we've already read metadata, this is an unexpected duplicate.
          guard self.majorVersion == nil, self.minorVersion == nil, self.compilerVersionString == nil else {
            throw ReadError.unexpectedMetadataRecord
          }
          guard
            record.fields.count == 3,
            case .blob(let compilerVersionBlob) = record.payload
          else {
            throw malformedError
          }

          self.majorVersion = record.fields[0]
          self.minorVersion = record.fields[1]
          let stringCount = record.fields[2]
          internedStringTable.reserveCapacity(Int(stringCount))
          self.compilerVersionString = String(decoding: compilerVersionBlob, as: UTF8.self)
        case .buildRecord:
          guard self.argsHash == nil, self.buildStartTime == .distantPast, self.buildEndTime == .distantFuture else {
            throw ReadError.unexpectedBuildRecord
          }
          guard
            record.fields.count == 7,
            case .blob(let argHashBlob) = record.payload
          else {
            throw malformedError
          }
          self.buildStartTime = TimePoint(
            lower: UInt32(record.fields[0]),
            upper: UInt32(record.fields[1]),
            nanoseconds: UInt32(record.fields[2]))
          self.buildEndTime = TimePoint(
            lower: UInt32(record.fields[3]),
            upper: UInt32(record.fields[4]),
            nanoseconds: UInt32(record.fields[5]))
          self.expectedInputInfos = Int(record.fields[6])
          self.argsHash = String(decoding: argHashBlob, as: UTF8.self)
        case .inputInfo:
          guard
            record.fields.count == 5,
            let path = try nonemptyInternedString(field: 4)
          else {
            throw malformedError
          }
          let modTime = TimePoint(
            lower: UInt32(record.fields[0]),
            upper: UInt32(record.fields[1]),
            nanoseconds: UInt32(record.fields[2]))
          let status = try InputInfo.Status(code: UInt32(record.fields[3]))
          let pathString = path.lookup(in: internedStringTable)
          let pathHandle = try VirtualPath.intern(path: pathString)
          self.inputInfos[VirtualPath.lookup(pathHandle)] = InputInfo(
            status: status,
            previousModTime: modTime)
        case .moduleDepGraphNode:
          guard record.fields.count == 6 else {
            throw malformedError
          }
          let key = try dependencyKey(kindCodeField: 0,
                                      declAspectField: 1,
                                      contextField: 2,
                                      identifierField: 3)
          let depSourceFileOrNone = try nonemptyInternedString(field: 4)
          let defLoc: DefinitionLocation = try depSourceFileOrNone.map {
            internedFile -> DefinitionLocation in
            let pathString = internedFile.lookup(in: internedStringTable)
            let pathHandle = try VirtualPath.intern(path: pathString)
            guard let source =  DependencySource(ifAppropriateFor: pathHandle,
                             internedString: internedFile)
            else {
              throw ReadError.unknownDependencySourceExtension
            }
            return .known(source)
          }
          ?? .unknown
          let fingerprint = try nonemptyInternedString(field: 5)
          self.finalize(node: Node(key: key,
                                   fingerprint: fingerprint,
                                   definitionLocation: defLoc))
        case .dependsOnNode:
          guard record.fields.count == 4
          else {
            throw malformedError
          }
          self.currentDefKey = try dependencyKey(
            kindCodeField: 0,
            declAspectField: 1,
            contextField: 2,
            identifierField: 3)
        case .useIDNode:
          guard let key = self.currentDefKey,
                  record.fields.count == 1 else {
            throw malformedError
          }
          self.nodeUses.append( (key, Int(record.fields[0])) )
        case .externalDepNode:
          guard record.fields.count == 2
          else {
            throw malformedError
          }
          let path = try internedString(field: 0)
          let fingerprint = try nonemptyInternedString(field: 1)
          fingerprintedExternalDependencies.insert(
            FingerprintedExternalDependency(
              ExternalDependency(fileName: path, internedStringTable),
              fingerprint))
        case .identifierNode:
          guard record.fields.count == 0,
                case .blob(let identifierBlob) = record.payload
          else {
            throw malformedError
          }
          _ = (String(decoding: identifierBlob, as: UTF8.self)).intern(in: internedStringTable)
        }
      }
    }

    var visitor = Visitor(info)
    try Bitcode.read(bytes: data, using: &visitor)
    guard let major = visitor.majorVersion,
          let minor = visitor.minorVersion,
          visitor.compilerVersionString != nil
    else {
      throw ReadError.malformedMetadataRecord
    }
    let readVersion = Version(Int(major), Int(minor), 0)
    guard readVersion == Self.serializedGraphVersion
    else {
      throw ReadError.mismatchedSerializedGraphVersion(
        expected: Self.serializedGraphVersion, read: readVersion)
    }
    return visitor.finalizeGraph()
  }

  /// Ensure the saved path points to saved graph from the prior build, and read it.
  ///
  /// Parameters:
  /// - path: the saved graph file path
  /// - info: the setup information
  /// - Returns: the file contents on success, nil if no such file exists
  private static func serializedPriorGraph(
    from path: VirtualPath,
    info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
  ) throws -> ByteString? {
    guard try info.fileSystem.exists(path) else {
      return nil
    }
    return try info.fileSystem.readFileContents(path)
  }
}

fileprivate extension InternedString {
  init(deserializedIndex: Int) {
    self.index = deserializedIndex
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
  ///   - mockSerializedGraphVersion: Overrides the standard version for testing
  /// - Returns: true if had error
  @_spi(Testing) public func write(
    to path: VirtualPath,
    on fileSystem: FileSystem,
    buildRecord: BuildRecord,
    mockSerializedGraphVersion: Version? = nil
  ) throws {
    let data = ModuleDependencyGraph.Serializer.serialize(
      self, buildRecord,
      mockSerializedGraphVersion ?? Self.serializedGraphVersion)

    do {
      try fileSystem.writeFileContents(path,
                                       bytes: data,
                                       atomically: true)
    } catch {
      throw IncrementalCompilationState.WriteDependencyGraphError.couldNotWrite(
        path: path, error: error)
    }
  }

  @_spi(Testing) public final class Serializer: InternedStringTableHolder {
    public let internedStringTable: InternedStringTable
    let buildRecord: BuildRecord
    let serializedGraphVersion: Version
    let stream = BitstreamWriter()
    private var abbreviations = [RecordID: Bitstream.AbbreviationID]()
    fileprivate private(set) var nodeIDs = [Node: Int]()
    private var lastNodeID: Int = 0

    private init(internedStringTable: InternedStringTable,
                 buildRecord: BuildRecord,
                 serializedGraphVersion: Version) {
      self.internedStringTable = internedStringTable
      self.buildRecord = buildRecord
      self.serializedGraphVersion = serializedGraphVersion
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
        self.emitRecordID(.buildRecord)
        self.emitRecordID(.inputInfo)
      }
    }

    private func writeMetadata() {
      self.stream.writeRecord(self.abbreviations[.metadata]!, {
        $0.append(RecordID.metadata)
        $0.append(serializedGraphVersion.majorForWriting)
        $0.append(serializedGraphVersion.minorForWriting)
        $0.append(min(UInt(internedStringTable.count), UInt(UInt32.max)))
      },
      blob: self.buildRecord.swiftVersion)
    }

    private func writeBuildRecord() {
      self.stream.writeRecord(self.abbreviations[.buildRecord]!, {
        $0.append(RecordID.buildRecord)
        $0.append(self.buildRecord.buildStartTime)
        $0.append(self.buildRecord.buildEndTime)
        $0.append(UInt32(self.buildRecord.inputInfos.count))
      },
      blob: self.buildRecord.argsHash)

      let sortedInputInfo = self.buildRecord.inputInfos.sorted {
        $0.key.name < $1.key.name
      }

      for (input, inputInfo) in sortedInputInfo {
        let inputID = input.name.intern(in: self.internedStringTable)
        let pathID = self.lookupIdentifierCode(for: inputID)

        self.stream.writeRecord(self.abbreviations[.inputInfo]!) {
          $0.append(RecordID.inputInfo)
          $0.append(inputInfo.previousModTime)
          $0.append(inputInfo.status.code)
          $0.append(pathID)
        }
      }
    }

    private func lookupIdentifierCode(for string: InternedString?) -> UInt32 {
      UInt32(string.map {$0.index} ?? 0)
    }

    private func cacheNodeID(for node: Node) {
      defer { self.lastNodeID += 1 }
      nodeIDs[node] = self.lastNodeID
    }

    private func populateCaches(from graph: ModuleDependencyGraph) {
      graph.nodeFinder.forEachNode { node in
        self.cacheNodeID(for: node)
      }

      let sortedInputInfo = self.buildRecord.inputInfos.sorted {
        $0.key.name < $1.key.name
      }

      for (input, _) in sortedInputInfo {
        _ = input.name.intern(in: self.internedStringTable)
      }

      for str in internedStringTable.strings {
        self.stream.writeRecord(self.abbreviations[.identifierNode]!, {
          $0.append(RecordID.identifierNode)
        }, blob: str)
      }
    }

    private func registerAbbreviations() {
      let dependencyKeyOperands: [Bitstream.Abbreviation.Operand] = [
        // dependency kind discriminator
        .fixed(bitWidth: 3),
        // dependency decl aspect discriminator
        .fixed(bitWidth: 1),
        // dependency context
        .vbr(chunkBitWidth: 13),
        // dependency name
        .vbr(chunkBitWidth: 13),
      ]

      self.abbreviate(.metadata, [
        .literal(RecordID.metadata.rawValue),
        // Major version
        .fixed(bitWidth: 16),
        // Minor version
        .fixed(bitWidth: 16),
        // Number of strings to be interned
        .fixed(bitWidth: 32),
        // Frontend version
        .blob,
      ])
      self.abbreviate(.buildRecord, [
        .literal(RecordID.buildRecord.rawValue),
        // Build start time seconds - lower bits
        .fixed(bitWidth: 32),
        // Build start time seconds - upper bits
        .fixed(bitWidth: 32),
        // Build start time nanoseconds
        .fixed(bitWidth: 32),
        // Build end time seconds - lower bits
        .fixed(bitWidth: 32),
        // Build end time seconds - upper bits
        .fixed(bitWidth: 32),
        // Build end time nanoseconds
        .fixed(bitWidth: 32),
        // Expected input count
        .fixed(bitWidth: 32),
        // Argument hash
        .blob,
      ])
      self.abbreviate(.inputInfo, [
        .literal(RecordID.inputInfo.rawValue),
        // Known modification time seconds - lower bits
        .fixed(bitWidth: 32),
        // Known modification time seconds - upper bits
        .fixed(bitWidth: 32),
        // Known modification time nanoseconds
        .fixed(bitWidth: 32),
        // Input status
        .fixed(bitWidth: 3),
        // path ID
        .vbr(chunkBitWidth: 13),
      ])
      self.abbreviate(.moduleDepGraphNode,
        [Bitstream.Abbreviation.Operand.literal(RecordID.moduleDepGraphNode.rawValue)] +
        dependencyKeyOperands + [
        // swiftdeps path / none if empty
        .vbr(chunkBitWidth: 13),
        // fingerprint
        .vbr(chunkBitWidth: 13),
      ])
      self.abbreviate(.dependsOnNode,
        [.literal(RecordID.dependsOnNode.rawValue)] +
        dependencyKeyOperands)
      self.abbreviate(.useIDNode, [
        .literal(RecordID.useIDNode.rawValue),
        // node ID
        .vbr(chunkBitWidth: 13),
      ])
      self.abbreviate(.externalDepNode, [
        .literal(RecordID.externalDepNode.rawValue),
        // path ID
        .vbr(chunkBitWidth: 13),
        // fingerprint ID
        .vbr(chunkBitWidth: 13),
      ])
      self.abbreviate(.identifierNode, [
        .literal(RecordID.identifierNode.rawValue),
        // identifier data
        .blob
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
      _ buildRecord: BuildRecord,
      _ serializedGraphVersion: Version
    ) -> ByteString {
      graph.accessSafetyPrecondition()
      let serializer = Serializer(
        internedStringTable: graph.internedStringTable,
        buildRecord: buildRecord,
        serializedGraphVersion: serializedGraphVersion)
      serializer.emitSignature()
      serializer.writeBlockInfoBlock()

      serializer.stream.withSubBlock(.firstApplicationID, abbreviationBitWidth: 8) {
        serializer.registerAbbreviations()

        serializer.writeMetadata()

        serializer.populateCaches(from: graph)

        serializer.writeBuildRecord()

        func write(key: DependencyKey, to buffer: inout BitstreamWriter.RecordBuffer) {
          buffer.append(key.designator.code)
          buffer.append(key.aspect.code)
          buffer.append(serializer.lookupIdentifierCode(
                      for: key.designator.context))
          buffer.append(serializer.lookupIdentifierCode(
                      for: key.designator.name))
        }

        graph.nodeFinder.forEachNode { node in
          serializer.stream.writeRecord(serializer.abbreviations[.moduleDepGraphNode]!) {
            $0.append(RecordID.moduleDepGraphNode)
            write(key: node.key, to: &$0)
            $0.append(serializer.lookupIdentifierCode(
                        for: node.definitionLocation.internedFileNameIfAny))
            $0.append(serializer.lookupIdentifierCode(for: node.fingerprint))
          }
        }

        for key in graph.nodeFinder.usesByDef.keys {
          serializer.stream.writeRecord(serializer.abbreviations[.dependsOnNode]!) {
            $0.append(RecordID.dependsOnNode)
            write(key: key, to: &$0)
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
        for fingerprintedExternalDependency in graph.fingerprintedExternalDependencies {
          serializer.stream.writeRecord(serializer.abbreviations[.externalDepNode]!) {
            $0.append(RecordID.externalDepNode)
            $0.append(serializer.lookupIdentifierCode(
              for: fingerprintedExternalDependency.externalDependency.fileName))
            $0.append( serializer.lookupIdentifierCode(
              for: fingerprintedExternalDependency.fingerprint))
          }
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
  init(kindCode: UInt64, context: InternedString, name: InternedString,
       internedStringTable: InternedStringTable,
       fileSystem: FileSystem) throws {
    func mustBeEmpty(_ s: InternedString) throws {
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
      self = .externalDepend(ExternalDependency(fileName: name, internedStringTable))
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

extension Set where Element == FingerprintedExternalDependency {
  fileprivate func matches(_ other: Self) -> Bool {
    self == other
  }
}

fileprivate extension Version {
  var majorForWriting: UInt32 {
    let r = UInt32(Int64(major))
    assert(Int(r) == Int(major))
    return r
  }
  var minorForWriting: UInt32 {
    let r = UInt32(Int64(minor))
    assert(Int(r) == Int(minor))
    return r
  }
}

fileprivate extension BitstreamWriter.RecordBuffer {
  mutating func append(_ time: TimePoint) {
    func split(_ value: UInt64) -> (UInt32, UInt32) {
      let lowerHalf = UInt32((value & 0x0000_0000_FFFF_FFFF))
      let upperHalf = UInt32((value & 0xFFFF_FFFF_0000_0000) >> 32)
      return (lowerHalf, upperHalf)
    }
    let (lower, upper) = split(time.seconds.littleEndian)
    self.append(lower)
    self.append(upper)
    let nanos = time.nanoseconds.littleEndian
    self.append(nanos)
  }
}

fileprivate extension TimePoint {
  init(
    lower: UInt32,
    upper: UInt32,
    nanoseconds: UInt32
  ) {
    let seconds = UInt64(lower) | (UInt64(upper) << 32)
    self.init(seconds: seconds, nanoseconds: nanoseconds)
  }
}

fileprivate extension InputInfo.Status {
  init(code: UInt32) throws {
    switch code {
    case 0:
      self = .upToDate
    case 1:
      self = .needsNonCascadingBuild
    case 2:
      self = .needsCascadingBuild
    case 3:
      self = .newlyAdded
    default:
      throw ModuleDependencyGraph.ReadError.unknownKind
    }
  }

  var code: UInt32 {
    switch self {
    case .upToDate:
      return 0
    case .needsNonCascadingBuild:
      return 1
    case .needsCascadingBuild:
      return 2
    case .newlyAdded:
      return 3
    }
  }
}
