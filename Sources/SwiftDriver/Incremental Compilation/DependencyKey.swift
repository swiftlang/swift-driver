
import Foundation

/// A filename from another module
struct ExternalDependency: Hashable, CustomStringConvertible {
  let fileName: String

  var file: VirtualPath? {
    try? VirtualPath(path: fileName)
  }
  init(_ path: String) {
    self.fileName = path
  }
  public var description: String {
    fileName.description
  }
}



public struct DependencyKey: Hashable, CustomStringConvertible {
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

  enum DeclAspect {
    case interface, implementation
  }

  /// Encode the current sorts of dependencies as kinds of nodes in the dependency
  /// graph, splitting the current *member* into \ref member and \ref
  /// potentialMember and adding \ref sourceFileProvide.
  ///
  enum Designator: Hashable, CustomStringConvertible {
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

    public var description: String {
      switch self {
      case let .topLevel(name: name):
        return "top-level name \(name)"
      case let .nominal(context: context):
        return "type \(context)"
      case let .potentialMember(context: context):
        return "potential members of \(context)"
      case let .member(context: context, name: name):
        return "member \(name) of \(context)"
      case let .dynamicLookup(name: name):
        return "AnyObject member \(name)"
      case let .externalDepend(externalDependency):
        return "module \(externalDependency)"
      case let .sourceFileProvide(name: name):
        return (try? VirtualPath(path: name).basename) ?? name
      }
    }
  }

  let aspect: DeclAspect
  let designator: Designator


  init(
    aspect: DeclAspect,
    designator: Designator)
  {
    self.aspect = aspect
    self.designator = designator
  }


var correspondingImplementation: Self? {
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

