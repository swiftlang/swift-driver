//===------------------------ Node.swift ----------------------------------===//
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

// MARK: - ModuleDependencyGraph.Node
extension ModuleDependencyGraph {

  /// A node in the per-module (i.e. the driver) dependency graph
  /// Each node represents a `Decl` from the frontend.
  /// If a file references a `Decl` we haven't seen yet, the node's `dependencySource` will be nil,
  /// otherwise it will hold the name of the dependencySource file from which the node was read.
  /// A dependency is represented by an arc, in the `usesByDefs` map.
  /// (Cargo-culted and modified from the legacy driver.)
  ///
  /// Use a class, not a struct because otherwise it would be duplicated for each thing it uses
  ///
  /// Neither the `fingerprint`, nor the `isTraced` value is part of the node's identity.
  /// Neither of these must be considered for equality testing or hashing because their
  /// value is subject to change during integration and tracing.

  public final class Node {
    public typealias DefinitionLocation = ModuleDependencyGraph.DefinitionLocation

    /*@_spi(Testing)*/ public typealias Graph = ModuleDependencyGraph

    /// Hold these where an invariant can be checked.
    /// Must be able to change the fingerprint
    private(set) var keyAndFingerprint: KeyAndFingerprintHolder

    /*@_spi(Testing)*/ public var key: DependencyKey { keyAndFingerprint.key }
    /*@_spi(Testing)*/ public var fingerprint: InternedString? { keyAndFingerprint.fingerprint }

    /// When integrating a change, the driver finds untraced nodes so it can kick off jobs that have not been
    /// kicked off yet. (Within any one driver invocation, compiling a source file is idempotent.)
    /// When reading a serialized, prior graph, *don't* recover this state, since it will be a new driver
    /// invocation that has not kicked off any compiles yet.
    @_spi(Testing) public private(set) var isTraced: Bool = false
      
    /// Each Node corresponds to a declaration, somewhere. If the definition has been already found,
    /// the `definitionLocation` will point to it.
    /// If uses are encountered before the definition (in reading swiftdeps files), the `definitionLocation`
    /// will be set to `.unknown`.
    /// A node's definition location can move from file to file when the driver reads the result of a
    /// compilation.

    @_spi(Testing) public let definitionLocation: DefinitionLocation

    private let cachedHash: Int

    /// This dependencySource is the file where the swiftDeps, etc. was read, not necessarily anything in the
    /// SourceFileDependencyGraph or the DependencyKeys
    init(key: DependencyKey, fingerprint: InternedString?,
         definitionLocation: DefinitionLocation) {
      self.keyAndFingerprint = try! KeyAndFingerprintHolder(key, fingerprint)
      self.definitionLocation = definitionLocation
      self.cachedHash = Self.computeHash(key, definitionLocation)
    }
  }
}

// MARK: - Setting fingerprint
extension ModuleDependencyGraph.Node {
  func setFingerprint(_ newFP: InternedString?) {
    keyAndFingerprint = try! KeyAndFingerprintHolder(key, newFP)
  }
}

// MARK: - trace status
extension ModuleDependencyGraph.Node {
  var isUntraced: Bool { !isTraced }
  func setTraced() { isTraced = true }
  @_spi(Testing) public func setUntraced() { isTraced = false }
}

// MARK: - comparing, hashing
extension ModuleDependencyGraph.Node: Equatable, Hashable {
  public static func ==(lhs: ModuleDependencyGraph.Node, rhs: ModuleDependencyGraph.Node) -> Bool {
    lhs.keyAndFingerprint.key == rhs.keyAndFingerprint.key &&
    lhs.definitionLocation == rhs.definitionLocation
  }
  static private func computeHash(_ key: DependencyKey, _ definitionLocation: ModuleDependencyGraph.DefinitionLocation) -> Int {
    var h = Hasher()
    h.combine(key)
    h.combine(definitionLocation)
    return h.finalize()
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(cachedHash)
  }
}

/// May not be used today, but will be needed if we ever need to deterministically order nodes.
/// For example, when following def-use links in ``ModuleDependencyGraph/Tracer``
public func isInIncreasingOrder(
  _ lhs: ModuleDependencyGraph.Node, _ rhs: ModuleDependencyGraph.Node,
  in holder: InternedStringTableHolder
)-> Bool {
  if lhs.key != rhs.key {
    return isInIncreasingOrder(lhs.key, rhs.key, in: holder)
  }
  guard lhs.definitionLocation == rhs.definitionLocation
  else {
    return lhs.definitionLocation < rhs.definitionLocation
  }
  guard let rf = rhs.fingerprint else {return false}
  guard let lf = lhs.fingerprint else {return true}
  return isInIncreasingOrder(lf, rf, in: holder)
}

extension ModuleDependencyGraph.Node {
  public func description(in holder: InternedStringTableHolder) -> String {
    "\(key.description(in: holder)) \( definitionLocation.locationString )"
  }
}

extension ModuleDependencyGraph.Node {
  public func verify() {
    verifyNodesithoutDefinitionLocationHasNoFingerprints()
    key.verify()
  }

  public func verifyNodesithoutDefinitionLocationHasNoFingerprints() {
    if case .unknown = definitionLocation, fingerprint != nil {
      fatalError(#function)
    }
  }
}

// MARK: - DefinitionLocation

extension ModuleDependencyGraph {
  /// Represents a (possibly unknown) location for a declaration.
  /// Although a graph node represents a declaration, the location of the definition is not
  /// always known. For example, it may be in a `swiftdeps` file yet to be read.
  public enum DefinitionLocation: Equatable, Hashable, Comparable {
    case unknown, known(DependencySource)

    public static func <(lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
        case (.unknown, .unknown): return false
        case (.known, .unknown): return false
        case (.unknown, .known): return true
        case let (.known(lh), .known(rh)): return lh < rh
      }
    }

    /// A string explaining where the definition is.
    public var locationString: String {
      switch self {
        case .unknown: return "nowhere"
        case let .known(dependencySource): return "in \(dependencySource.description)"
      }
    }

    /// The file holding the definition.
    public var internedFileNameIfAny: InternedString? {
      switch self {
        case .unknown: return nil
        case let .known(dependencySource): return dependencySource.internedFileName
      }
    }
  }
}
