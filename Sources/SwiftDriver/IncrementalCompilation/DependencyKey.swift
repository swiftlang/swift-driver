//===------------------- DependencyKey.swift ------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch

/// A filename from another module
/*@_spi(Testing)*/ final public class ExternalDependency: Hashable, Comparable, CustomStringConvertible {


  /// Delay computing the path as an optimization.
  let fileName: InternedString
  let fileNameString: String // redundant, but allows caching pathHandle

  lazy var pathHandle = getPathHandle()

  /*@_spi(Testing)*/ public init(
    fileName: InternedString, _ t: InternedStringTable) {
      self.fileName = fileName
      self.fileNameString = fileName.lookup(in: t)
  }

  static var dummy: Self {
    MockIncrementalCompilationSynchronizer.withInternedStringTable { t in
      return Self(fileName: ".".intern(in: t), t)
    }
  }

  public static func ==(lhs: ExternalDependency, rhs: ExternalDependency) -> Bool {
    lhs.fileName == rhs.fileName
  }
  public static func <(lhs: ExternalDependency, rhs: ExternalDependency) -> Bool {
    lhs.fileNameString < rhs.fileNameString
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(fileName)
  }

  /// Should only be called by debugging functions or functions that are cached
  private func getPathHandle() -> VirtualPath.Handle? {
    try? VirtualPath.intern(path: fileNameString)
  }

  /// Cache this here
  var isSwiftModule: Bool {
    fileNameString.hasSuffix(".\(FileType.swiftModule.rawValue)")
  }

  var swiftModuleFile: TypedVirtualPath? {
    guard let pathHandle = pathHandle, isSwiftModule
    else {
      return nil
    }
    return TypedVirtualPath(file: pathHandle, type: .swiftModule)
  }

  public var path: VirtualPath? {
    pathHandle.map(VirtualPath.lookup)
  }

  public var description: String {
    guard let path = path else {
      return "non-path: '\(fileName)'"
    }
    return path.externalDependencyPathDescription
  }

  public var shortDescription: String {
    pathHandle.map { pathHandle in
      DependencySource(ifAppropriateFor: pathHandle, internedString: fileName).map { $0.shortDescription }
        ?? VirtualPath.lookup(pathHandle).basename
    }
    ?? description
  }
}

extension VirtualPath {
  var externalDependencyPathDescription: String {
    switch self.extension {
    case FileType.swiftModule.rawValue:
      // Swift modules have an extra component at the end that is not descriptive
      return parentDirectory.basename
    default:
      return basename
    }
  }
}

/// Since the integration surfaces all externalDependencies to be processed later,
/// a combination of the dependency and fingerprint are needed.
public struct FingerprintedExternalDependency: Hashable, Equatable, ExternalDependencyAndFingerprintEnforcer {
  let externalDependency: ExternalDependency
  let fingerprint: InternedString?

  @_spi(Testing) public init(_ externalDependency: ExternalDependency, _ fingerprint: InternedString?) {
    self.externalDependency = externalDependency
    self.fingerprint = fingerprint
    assert(verifyExternalDependencyAndFingerprint())
  }
  var externalDependencyToCheck: ExternalDependency? { externalDependency }

  var incrementalDependencySource: DependencySource? {
    guard let _ = fingerprint,
          let swiftModuleFile = externalDependency.swiftModuleFile
    else {
      return nil
    }
    return DependencySource(typedFile: swiftModuleFile,
                            internedFileName: externalDependency.fileName)
  }
}

extension FingerprintedExternalDependency {
  public func description(in holder: InternedStringTableHolder) -> String {
    "\(externalDependency) \(fingerprint.map {"fingerprint: \($0.description(in: holder))"} ?? "no fingerprint")"
  }
}

/// A `DependencyKey` carries all of the information necessary to uniquely
/// identify a dependency node in the graph, and serves as a point of identity
/// for the dependency graph's map from definitions to uses.
public struct DependencyKey {
  /// Captures which facet of the dependency structure a dependency key represents.
  ///
  /// A `DeclAspect` is used to separate dependencies with a scope limited to
  /// a single file (or declaration within a file) from dependencies with a
  /// scope that may affect many files.
  ///
  /// Those dependencies that are localized to a single file or declaration are
  /// a part of the "implementation" aspect. Changes to nodes with the
  /// implementation aspect do not require uses of that node to be recompiled.
  /// The Swift frontend models all uses of declarations in a file as part of
  /// the implementation aspect.
  ///
  /// The remaining kind of dependencies are a part of the "interface" aspect.
  /// Changes to nodes with the interface aspect *require* all uses of the node
  /// to be rebuilt. The Swift frontend models the definitions of types,
  /// functions, and members with an interface node.
  ///
  /// Special Considerations
  /// ======================
  ///
  /// When the Swift frontend creates dependency nodes, they occur in
  /// interface/implementation pairs. The idea being that the implementation
  /// aspect node depends on the interface aspect node but, crucially, not
  /// vice versa. This models the fact that changes to the interface of a node
  /// must cause its implementation to be recompiled.
  ///
  /// Dumping Dependency Graphs
  /// =========================
  ///
  /// When the driver's dependency graph is dumped as a dot file, nodes with
  /// the interface aspect are yellow and nodes with the implementations aspect
  /// are white. Each node holds an instance variable describing which
  /// aspect of the entity it represents.
  /*@_spi(Testing)*/ public enum DeclAspect: Comparable {
    /// The "interface" aspect.
    case interface
    /// The "implementation" aspect.
    case implementation
  }

  /// Enumerates the current sorts of dependency nodes in the dependency graph.
  /*@_spi(Testing)*/ public enum Designator: Hashable {
    /// A top-level name.
    ///
    /// Corresponds to the top-level names that occur in a given file. When
    /// a top-level name matching this name is added, removed, or modified
    /// the corresponding dependency node will be marked for recompilation.
    ///
    /// The `name` parameter is the human-readable name of the top-level
    /// declaration.
    case topLevel(name: InternedString)
    /// A dependency originating from the lookup of a "dynamic member".
    ///
    /// A "dynamic member lookup" is the Swift frontend's term for lookups that
    /// occur against instances of `AnyObject`. Because an `AnyObject` node
    /// behaves like `id` in that it can receive any kind of Objective-C
    /// message, the compiler takes care to log these names separately.
    ///
    /// The `name` parameter is the human-readable base name of the Swift method
    /// the dynamic member was imported as. e.g. `-[NSString initWithString:]`
    /// appears as `init`.
    ///
    /// - Note: This is distinct from "dynamic member lookup", which uses
    ///         a normal `member` constraint.
    case dynamicLookup(name: InternedString)
    /// A dependency that resides outside of the module being built.
    ///
    /// These dependencies correspond to clang modules and their immediate
    /// dependencies, header files imported via the bridging header, and Swift
    /// modules that do not have embedded incremental dependency information.
    /// Because of this, the Swift compiler and Driver have very little
    /// information at their disposal to make scheduling decisions relative to
    /// the other kinds of dependency nodes. Thus, when the modification time of
    /// an external dependency node changes, the Driver is forced to rebuild all
    /// uses of the dependency.
    ///
    /// The full path to the external dependency as seen by the frontend is
    /// available from this node.
    case externalDepend(ExternalDependency)
    /// A source file - acts as the root for all dependencies provided by
    /// declarations in that file.
    ///
    /// The `name` of the file is a path to the `swiftdeps` file named in
    /// the output file map for a given Swift file.
    ///
    /// Swiftmodule files may contain a special section with swiftdeps information
    /// for the module. In that case the enclosing node should have a fingerprint.
    case sourceFileProvide(name: InternedString)
    /// A "nominal" type that is used, or defined by this file.
    ///
    /// Unlike a top-level name, a `nominal` dependency always names exactly
    /// one unique declaration (opp. many declarations with the same top-level
    /// name). The `context` field of this type is the mangled name of this
    /// type. When a component of the mangling for the nominal type changes,
    /// the corresponding dependency node will be marked for recompilation.
    /// These nodes generally capture the space of ABI-breaking changes made to
    /// types themselves such as the addition or removal of generic parameters,
    /// or a change in base name.
    case nominal(context: InternedString)
    /// A "potential member" constraint models the abstract interface of a
    /// particular type or protocol. They can be thought of as a kind of
    /// "globstar" member constraint. Whenever a member is added, removed or
    /// modified, or the type itself is deleted, the corresponding dependency
    /// node will be marked for recompilation.
    ///
    /// Potential member nodes are used to model protocol conformances and
    /// superclass constraints where the modification of members affects the
    /// layout of subclasses or protocol conformances.
    ///
    /// Like `nominal` nodes, the `context` field is the mangled name of the
    /// subject type.
    case potentialMember(context: InternedString)
    /// A member of a type.
    ///
    /// The `context` field corresponds to the mangled name of the type. The
    /// `name` field corresponds to the *unmangled* name of the member.
    case member(context: InternedString, name: InternedString)

    var externalDependency: ExternalDependency? {
      switch self {
      case let .externalDepend(externalDependency):
        return externalDependency
      default:
        return nil
      }
    }

    public var context: InternedString? {
      switch self {
      case .topLevel(name: _):
        return nil
      case .dynamicLookup(name: _):
        return nil
      case .externalDepend(_):
        return nil
      case .sourceFileProvide(name: _):
        return nil
      case .nominal(context: let context):
        return context
      case .potentialMember(context: let context):
        return context
      case .member(context: let context, name: _):
        return context
      }
    }

    public var name: InternedString? {
      switch self {
      case .topLevel(name: let name):
        return name
      case .dynamicLookup(name: let name):
        return name
      case .externalDepend(let externalDependency):
        return externalDependency.fileName
      case .sourceFileProvide(name: let name):
        return name
      case .member(context: _, name: let name):
        return name
      case .nominal(context: _):
        return nil
      case .potentialMember(context: _):
        return nil
      }
    }

    public var kindName: String {
      switch self {
      case .topLevel: return "top-level"
      case .nominal: return "nominal"
      case .potentialMember: return "potential member"
      case .member: return "member"
      case .dynamicLookup: return "dynamic lookup"
      case .externalDepend: return "external"
      case .sourceFileProvide: return "source file"
      }
    }

    public func description(in holder: InternedStringTableHolder) -> String {
      switch self {
      case let .topLevel(name: name):
        return "top-level name '\(name.lookup(in: holder))'"
      case let .nominal(context: context):
        return "type '\(context.lookup(in: holder))'"
      case let .potentialMember(context: context):
        return "potential members of '\(context.lookup(in: holder))'"
      case let .member(context: context, name: name):
        return "member '\(name.lookup(in: holder))' of '\(context.lookup(in: holder))'"
      case let .dynamicLookup(name: name):
        return "AnyObject member '\(name.lookup(in: holder))'"
      case let .externalDepend(externalDependency):
        return "import '\(externalDependency.shortDescription)'"
      case let .sourceFileProvide(name: name):
        return "source file from \((try? VirtualPath(path: name.lookup(in: holder)).basename) ?? name.lookup(in: holder))"
      }
    }
  }

  /*@_spi(Testing)*/ public let aspect: DeclAspect
  /*@_spi(Testing)*/ public let designator: Designator

  /*@_spi(Testing)*/ public init(
    aspect: DeclAspect,
    designator: Designator)
  {
    self.aspect = aspect
    self.designator = designator
  }

  /*@_spi(Testing)*/ public var correspondingImplementation: Self? {
    guard aspect == .interface  else {
      return nil
    }
    return Self(aspect: .implementation, designator: designator)
  }

  public func description(in holder: InternedStringTableHolder) -> String {
    "\(aspect) of \(designator.description(in: holder))"
  }

  @discardableResult
  func verify() -> Bool {
    // This space reserved for future use.
    return true
  }
}

extension DependencyKey: Equatable, Hashable {}

/// See ``ModuleDependencyGraph/Node/isInIncreasingOrder(::in:)``
public func isInIncreasingOrder(_ lhs: DependencyKey,
                                _ rhs: DependencyKey,
                                in holder: InternedStringTableHolder) -> Bool {
  guard lhs.aspect == rhs.aspect else {
    return lhs.aspect < rhs.aspect
  }
  return isInIncreasingOrder(lhs.designator, rhs.designator, in: holder)
}

/// Takes the place of `<` by expanding the interned strings.
public func isInIncreasingOrder(_ lhs: DependencyKey.Designator,
                                _ rhs: DependencyKey.Designator,
                                in holder: InternedStringTableHolder) -> Bool {
  func f(_ s: InternedString) -> String {
    s.lookup(in: holder)
  }
  switch (lhs, rhs) {
  case
    let (.topLevel(ln), .topLevel(rn)),
    let (.dynamicLookup(ln), .dynamicLookup(rn)),
    let (.sourceFileProvide(ln), .sourceFileProvide(rn)),
    let (.nominal(ln), .nominal(rn)),
    let (.potentialMember(ln), .potentialMember(rn)):
    return f(ln) < f(rn)

  case let (.externalDepend(ld), .externalDepend(rd)):
    return ld < rd

  case let (.member(lc, ln), .member(rc, rn)):
    return lc == rc ? f(ln) < f(rn) : f(lc) < f(rc)

  default: break
  }

  /// Preserves the ordering that obtained before interned strings were introduced.
  func kindOrdering(_ d: DependencyKey.Designator) -> Int {
    switch d {
    case .topLevel: return 1
    case .dynamicLookup: return 2
    case .externalDepend: return 3
    case .sourceFileProvide: return 4
    case .nominal: return 5
    case .potentialMember: return 6
    case .member: return 7
    }
  }
  assert(kindOrdering(lhs) != kindOrdering(rhs))
  return kindOrdering(lhs) < kindOrdering(rhs)
}

//extension DependencyKey.Designator: Comparable {}

// MARK: - InvalidationReason
extension ExternalDependency {
  /// When explaining incremental decisions, it helps to know why a particular external dependency
  /// caused invalidation.
  public enum InvalidationReason: String, CustomStringConvertible {
    /// An `import` of this file was added to the source code.
    case added

    /// The imported file is newer.
    case newer

    /// Used when testing
    case testing

    public var description: String { rawValue }
  }
}
