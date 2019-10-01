/// A virtual path.
public struct VirtualPath: Codable, Hashable {
  /// The name of the file must be unique. This will be used to map to the actual path.
  var name: String

  /// True if this path represents a temporary file that is cleaned up after job execution.
  var isTemporary: Bool

  init(name: String, isTemporary: Bool) {
    self.name = name
    self.isTemporary = isTemporary
  }

  public static func path(_ name: String) -> VirtualPath {
    return VirtualPath(name: name, isTemporary: false)
  }

  public static func temporaryFile(_ name: String) -> VirtualPath {
    return VirtualPath(name: name, isTemporary: true)
  }
}
