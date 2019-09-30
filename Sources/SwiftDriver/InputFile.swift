import TSCBasic

/// Describes a file to which jobs may refer.
public enum File: Equatable {
  case relative(RelativePath)
  case absolute(AbsolutePath)
  case standardInput
}

/// An input to the compilation job.
public struct InputFile: Equatable {
  /// The file this input refers to.
  public let file: File

  /// The type of file we are working with.
  public let type: FileType

  public init(file: File, type: FileType) {
    self.file = file
    self.type = type
  }
}
