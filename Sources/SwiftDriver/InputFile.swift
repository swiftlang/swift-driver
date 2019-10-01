import TSCBasic

/// Describes a file to which jobs may refer.
public enum File: Hashable {
  case relative(RelativePath)
  case absolute(AbsolutePath)
  case standardInput
  case standardOutput
}

/// An input to the compilation job.
public struct InputFile: Hashable {
  /// The file this input refers to.
  public let file: File

  /// The type of file we are working with.
  public let type: FileType

  public init(file: File, type: FileType) {
    self.file = file
    self.type = type
  }
}
