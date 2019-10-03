/// A path for which the type of the input is known.
public struct TypedVirtualPath: Hashable {
  /// The file this input refers to.
  public let file: VirtualPath

  /// The type of file we are working with.
  public let type: FileType

  public init(file: VirtualPath, type: FileType) {
    self.file = file
    self.type = type
  }
}
