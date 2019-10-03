import TSCBasic
import Foundation

/// Mapping of input file paths to specific output files.
public struct OutputFileMap {
  /// The known mapping from input file to specific output files.
  public var entries: [VirtualPath : [FileType : VirtualPath]] = [:]

  public init() { }

  /// For the given input file, retrieve or create an output file for the given
  /// file type.
  public func getOutput(inputFile: VirtualPath, outputType: FileType) -> VirtualPath {
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

  /// Load the output file map at the given path.
  public static func load(
    file: AbsolutePath,
    diagnosticEngine: DiagnosticsEngine
  ) throws -> OutputFileMap {
    // Load and decode the file.
    let contents = try localFileSystem.readFileContents(file)
    let result = try JSONDecoder().decode(OutputFileMapJSON.self, from: Data(contents.contents))

    // Convert the loaded entries into virual output file map.
    var outputFileMap = OutputFileMap()
    outputFileMap.entries = try result.toVirtualOutputFileMap()

    return outputFileMap
  }
}

/// Struct for loading the JSON file from disk.
fileprivate struct OutputFileMapJSON: Decodable {
  /// The top-level key.
  private struct Key: CodingKey {
    var stringValue: String

    init?(stringValue: String) {
      self.stringValue = stringValue
    }

    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
  }

  /// The data associated with an input file.
  private struct Entry: Decodable {
    enum CodingKeys: String, CodingKey {
      case dependencies
      case object
      case swiftmodule
      case swiftDependencies = "swift-dependencies"
    }

    let dependencies: String?
    let object: String?
    let swiftmodule: String?
    let swiftDependencies: String?
  }

  /// The parsed entires
  private let entries: [String: Entry]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    let result = try container.allKeys.map { ($0.stringValue, try container.decode(Entry.self, forKey: $0)) }
    self.entries = Dictionary(uniqueKeysWithValues: result)
  }

  /// Converts into virtual path entries.
  func toVirtualOutputFileMap() throws -> [VirtualPath : [FileType : VirtualPath]] {
    var result: [VirtualPath : [FileType : VirtualPath]] = [:]

    for (input, entry) in entries {
      let input = try VirtualPath(path: input)

      var map: [FileType: String] = [:]
      map[.dependencies] = entry.dependencies
      map[.object] = entry.object
      map[.swiftModule] = entry.swiftmodule
      map[.swiftDeps] = entry.swiftDependencies

      result[input] = try map.mapValues(VirtualPath.init(path:))
    }

    return result
  }
}

extension String {
  /// Append the extension for the given file type to the string.
  func appendingFileTypeExtension(_ type: FileType) -> String {
    let ext = type.rawValue
    if ext.isEmpty { return self }

    return self + "." + ext
  }
}
