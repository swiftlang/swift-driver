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

import Foundation
import TSCBasic

/// A filename from another module
/*@_spi(Testing)*/ public struct ExternalDependency: Hashable, Comparable, CustomStringConvertible {
  
  /// Delay computing the path as an optimization.
  let fileName: String

  /// Cache this
  let isSwiftModule: Bool

  /*@_spi(Testing)*/ public init(fileName: String) {
    self.fileName = fileName
    self.isSwiftModule = fileName.hasSuffix(FileType.swiftModule.rawValue)
  }

  /// Should only be called by debugging functions or functions that are cached
  private func getPath() -> VirtualPath? {
    try? VirtualPath(path: fileName)
  }

  func slowModTime(_ fileSystem: FileSystem) -> Date? {
    getPath().flatMap {
      try? fileSystem.getFileInfo($0).modTime
    }
  }

  var swiftModuleFile: TypedVirtualPath? {
    isSwiftModule ? getPath().map {TypedVirtualPath(file: $0, type: .swiftModule)} : nil
  }

  public var description: String {
    guard let path = getPath() else {
      return "non-path: '\(fileName)'"
    }
    switch path.extension {
    case FileType.swiftModule.rawValue:
      // Swift modules have an extra component at the end that is not descriptive
      return path.parentDirectory.basename
    default:
      return path.basename
    }
  }

  public var shortDescription: String {
    getPath().map { path in
      DependencySource(path).map { $0.shortDescription }
        ?? path.basename
    }
    ?? description
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.fileName < rhs.fileName
  }
}

/// Since the integration surfaces all externalDependencies to be processed later,
/// a combination of the dependency and fingerprint are needed.
public struct FingerprintedExternalDependency: Hashable, Equatable, ExternalDependencyAndFingerprintEnforcer {
  let externalDependency: ExternalDependency
  let fingerprint: String?
  
  @_spi(Testing) public init(_ externalDependency: ExternalDependency, _ fingerprint: String?) {
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
    return DependencySource(swiftModuleFile)
  }
}

/// A `DependencyKey` carries all of the information necessary to uniquely
/// identify a dependency node in the graph, and serves as a point of identity
/// for the dependency graph's map from definitions to uses.
public struct DependencyKey: Hashable, CustomStringConvertible {
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
  /*@_spi(Testing)*/ public enum Designator: Hashable, CustomStringConvertible {
    /// A top-level name.
    ///
    /// Corresponds to the top-level names that occur in a given file. When
    /// a top-level name matching this name is added, removed, or modified
    /// the corresponding dependency node will be marked for recompilation.
    ///
    /// The `name` parameter is the human-readable name of the top-level
    /// declaration.
    case topLevel(name: String)
    /// A dependency originating from the lookup of a "dynamic member".
    ///
    /// A "dynamic member lookup" is the Swift frontend's term for lookups that
    /// occur against instances of `AnyObject`. Because an `AnyObject` node
    /// behaves like `id` in that it can recieve any kind of Objective-C
    /// message, the compiler takes care to log these names separately.
    ///
    /// The `name` parameter is the human-readable base name of the Swift method
    /// the dynamic member was imported as. e.g. `-[NSString initWithString:]`
    /// appears as `init`.
    ///
    /// - Note: This is distinct from "dynamic member lookup", which uses
    ///         a normal `member` constraint.
    case dynamicLookup(name: String)
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
    case sourceFileProvide(name: String)
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
    case nominal(context: String)
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
    case potentialMember(context: String)
    /// A member of a type.
    ///
    /// The `context` field corresponds to the mangled name of the type. The
    /// `name` field corresponds to the *unmangled* name of the member.
    case member(context: String, name: String)

    var externalDependency: ExternalDependency? {
      switch self {
      case let .externalDepend(externalDependency):
        return externalDependency
      default:
        return nil
      }
    }

    public var context: String? {
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

    public var name: String? {
      switch self {
      case .topLevel(name: let name):
        return name
      case .dynamicLookup(name: let name):
        return name
      case .externalDepend(let path):
        return path.fileName
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

    public var description: String {
      switch self {
      case let .topLevel(name: name):
        return "top-level name '\(name)'"
      case let .nominal(context: context):
        return "type '\(context)'"
      case let .potentialMember(context: context):
        return "potential members of '\(context)'"
      case let .member(context: context, name: name):
        return "member '\(name)' of '\(context)'"
      case let .dynamicLookup(name: name):
        return "AnyObject member '\(name)'"
      case let .externalDepend(externalDependency):
        return "import '\(externalDependency.shortDescription)'"
      case let .sourceFileProvide(name: name):
        return "source file \((try? VirtualPath(path: name).basename) ?? name)"
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

  public var description: String {
    "\(aspect) of \(designator)"
  }

  @discardableResult
  func verify() -> Bool {
    // This space reserved for future use.
    return true
  }
}

// MARK: - Comparing
/// Needed to sort nodes to make tracing deterministic to test against emitted diagnostics
extension DependencyKey: Comparable {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.aspect != rhs.aspect ? lhs.aspect < rhs.aspect :
      lhs.designator < rhs.designator
  }
}

extension DependencyKey.Designator: Comparable {
}

