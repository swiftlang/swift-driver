import TSCBasic

/// A virtual path.
public struct VirtualPath: Codable, Hashable {
  /// A description of the file or directory, which must be unique.
  ///
  /// This will be used to map to the actual path.
  let file: File

  /// True if this path represents a temporary file that is cleaned up after job execution.
  ///
  /// Temporary files are always relative.
  let isTemporary: Bool

  public static func path(_ file: File) -> VirtualPath {
    return VirtualPath(file: file, isTemporary: false)
  }

  public static func temporaryFile(_ name: String) -> VirtualPath {
    return VirtualPath(file: .relative(try! RelativePath(validating: name)), isTemporary: true)
  }
}
