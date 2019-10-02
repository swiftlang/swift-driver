import TSCBasic

/// Mapping of input file paths to specific output files.
struct OutputFileMap {
  /// The known mapping from input file to specific output files.
  var entries: [VirtualPath : [FileType : VirtualPath]] = [:]

  init() { }

  /// For the given input file, retrieve or create an output file for the given
  /// file type.
  func getOutput(inputFile: VirtualPath, outputType: FileType) -> VirtualPath {
    // If we already have an output file, retrieve it.
    if let output = entries[inputFile]?[outputType] {
      return output
    }

    // Create a temporary file
    let baseName: String
    switch inputFile {
    case .absolute(let path):
      baseName = path.basenameWithoutExt
    case .relative(let path):
      baseName = path.basenameWithoutExt
    case .standardInput:
      baseName = ""
    case .standardOutput:
      fatalError("Standard output cannot be an input file")
    case .temporary(let name):
      baseName = name
    }

    // Form the virtual path.
    return .temporary(baseName.appendingFileTypeExtension(outputType))
  }
}

extension String {
  /// Append the extension for the given file type to the string.
  fileprivate func appendingFileTypeExtension(_ type: FileType) -> String {
    let ext = type.rawValue
    if ext.isEmpty { return self }

    return self + "." + ext
  }
}
