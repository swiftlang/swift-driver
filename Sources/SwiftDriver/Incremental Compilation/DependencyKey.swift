
import Foundation

/// A filename from another module
@_spi(Testing) public struct ExternalDependency: Hashable, CustomStringConvertible {
  let fileName: String

  @_spi(Testing) public init(_ path: String) {
    self.fileName = path
  }

  public var description: String {
    fileName.description
  }
}



@_spi(Testing) public struct DependencyKey: Hashable {
  /// Instead of the status quo scheme of two kinds of "Depends", cascading and
  /// non-cascading this code represents each entity ("Provides" in the status
  /// quo), by a pair of nodes. One node represents the "implementation." If the
  /// implementation changes, users of the entity need not be recompiled. The
  /// other node represents the "interface." If the interface changes, any uses of
  /// that definition will need to be recompiled. The implementation always
  /// depends on the interface, since any change that alters the interface will
  /// require the implementation to be rebuilt. The interface does not depend on
  /// the implementation. In the dot files, interfaces are yellow and
  /// implementations white. Each node holds an instance variable describing which
  /// aspect of the entity it represents.

  @_spi(Testing) public enum DeclAspect {
    case interface, implementation
  }

  /// Encode the current sorts of dependencies as kinds of nodes in the dependency
  /// graph, splitting the current *member* into \ref member and \ref
  /// potentialMember and adding \ref sourceFileProvide.
  ///
  @_spi(Testing) public enum Designator: Hashable {
    case
      topLevel(name: String),
      dynamicLookup(name: String),
      externalDepend(ExternalDependency),
      sourceFileProvide(name: String)

    case
      nominal(context: String),
      potentialMember(context: String)

    case
      member(context: String, name: String)

    var externalDependency: ExternalDependency? {
      switch self {
      case let .externalDepend(externalDependency):
        return externalDependency
      default:
        return nil}
    }
 }

  @_spi(Testing) public let aspect: DeclAspect
  @_spi(Testing) public let designator: Designator


  @_spi(Testing) public init(
    aspect: DeclAspect,
    designator: Designator)
  {
    self.aspect = aspect
    self.designator = designator
  }


  @_spi(Testing) public var correspondingImplementation: Self {
    assert(aspect == .interface)
    return Self(aspect: .implementation, designator: designator)
  }

  @discardableResult
  func verify() -> Bool {
    // This space reserved for future use.
    return true
  }
}

