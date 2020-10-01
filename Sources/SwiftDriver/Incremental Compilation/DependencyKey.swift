
import Foundation


@_spi(Testing) public struct DependencyKey: Hashable {
  // Encode the current sorts of dependencies as kinds of nodes in the dependency
  /// graph, splitting the current *member* into \ref member and \ref
  /// potentialMember and adding \ref sourceFileProvide.

  public enum Kind: String, CaseIterable {
    case topLevel
    case nominal
    /// In the status quo scheme, *member* dependencies could have blank names
    /// for the member, to indicate that the provider might add members.
    /// This code uses a separate kind, \ref potentialMember. The holder field is
    /// unused.
    case potentialMember
    /// Corresponding to the status quo *member* dependency with a non-blank
    /// member.
    case member
    case dynamicLookup
    case externalDepend
    case sourceFileProvide
  }

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


  public let kind: Kind
  public let aspect: DeclAspect
  public let context: String?
  public let name: String?

  @_spi(Testing) public init(
    kind: Kind,
    aspect: DeclAspect,
    context: String?,
    name: String?)
  {
    self.kind = kind
    self.aspect = aspect
    self.context = context
    self.name = name
  }

  @_spi(Testing) public var correspondingImplementation: Self {
    assert(aspect == .interface)
    return Self(kind: kind, aspect: .implementation, context: context, name: name)
  }

  public func verify() {
    assert(kind != .externalDepend || aspect == .interface, "All external dependencies must be interfaces.")
    switch kind {
    case .topLevel, .dynamicLookup, .externalDepend, .sourceFileProvide:
      assert(context == nil && name != nil, "Must only have a name")
    case .nominal, .potentialMember:
      assert(context != nil && name == nil, "Must only have a context")
    case .member:
      assert(context != nil && name != nil, "Must have both")
    }
  }
}

