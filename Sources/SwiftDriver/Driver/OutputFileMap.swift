//===--------------- OutputFileMap.swift - Swift Output File Map ----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic
import Foundation

/// Mapping of input file paths to specific output files.
public struct OutputFileMap: Equatable {
  /// The known mapping from input file to specific output files.
  public var entries: [VirtualPath : [FileType : VirtualPath]] = [:]

  public init() { }

  public init(entries: [VirtualPath : [FileType : VirtualPath]]) {
    self.entries = entries
  }

  /// For the given input file, retrieve or create an output file for the given
  /// file type.
  public func getOutput(inputFile: VirtualPath, outputType: FileType) -> VirtualPath {
    // If we already have an output file, retrieve it.
    if let output = existingOutput(inputFile: inputFile, outputType: outputType) {
      return output
    }

    if inputFile == .standardOutput {
      fatalError("Standard output cannot be an input file")
    }

    // Form the virtual path.
    return .temporary(RelativePath(inputFile.basenameWithoutExt.appendingFileTypeExtension(outputType)))
  }

  public func existingOutput(inputFile: VirtualPath, outputType: FileType) -> VirtualPath? {
    entries[inputFile]?[outputType]
  }

  public func existingOutputForSingleInput(outputType: FileType) -> VirtualPath? {
    try! existingOutput(inputFile: VirtualPath(path: ""), outputType: outputType)
  }

  public func resolveRelativePaths(relativeTo absPath: AbsolutePath) -> OutputFileMap {
    let resolvedKeyValues: [(VirtualPath, [FileType : VirtualPath])] = entries.map {
      let resolvedKey: VirtualPath
      // Special case for single dependency record, leave it as is
      if ($0.key == .relative(.init(""))) {
        resolvedKey = $0.key
      } else {
        resolvedKey = $0.key.resolvedRelativePath(base: absPath)
      }
      let resolvedValue = $0.value.mapValues {
        $0.resolvedRelativePath(base: absPath)
      }
      return (resolvedKey, resolvedValue)
    }
    return OutputFileMap(entries: .init(resolvedKeyValues, uniquingKeysWith: { _,_ in
      fatalError("Paths collided after resolving")
    }))
  }

  /// Load the output file map at the given path.
  public static func load(
    file: VirtualPath,
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

  /// Store the output file map at the given path.
  public func store(
    file: AbsolutePath,
    diagnosticEngine: DiagnosticsEngine
  ) throws {
    let encoder = JSONEncoder()

  #if os(Linux)
    encoder.outputFormatting = [.prettyPrinted]
  #else
    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    }
  #endif

    let contents = try encoder.encode(OutputFileMapJSON.fromVirtualOutputFileMap(entries).entries)
    try localFileSystem.writeFileContents(file, bytes: ByteString(contents))
  }
}

/// Struct for loading the JSON file from disk.
fileprivate struct OutputFileMapJSON: Codable {
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
  /// \c fileprivate so that the \c store method above can see it
  fileprivate struct Entry: Codable {

    private struct CodingKeys: CodingKey {

      let fileType: FileType

      init(fileType: FileType) {
        self.fileType = fileType
      }

      init?(stringValue: String) {
        guard let fileType = FileType(name: stringValue) else { return nil }
        self.fileType = fileType
      }

      var stringValue: String { fileType.name }
      var intValue: Int? { nil }
      init?(intValue: Int) { nil }
    }

    let paths: [FileType: String]

    fileprivate init(paths: [FileType: String]) {
      self.paths = paths
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)

      paths = try Dictionary(uniqueKeysWithValues:
        container.allKeys.map { key in (key.fileType, try container.decode(String.self, forKey: key)) }
      )
    }

    func encode(to encoder: Encoder) throws {

      var container = encoder.container(keyedBy: CodingKeys.self)

      try paths.forEach { fileType, path in try container.encode(path, forKey: CodingKeys(fileType: fileType)) }
    }
  }

  /// The parsed entries
  /// \c fileprivate so that the \c store method above can see it
  fileprivate let entries: [String: Entry]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    let result = try container.allKeys.map { ($0.stringValue, try container.decode(Entry.self, forKey: $0)) }
    self.init(entries: Dictionary(uniqueKeysWithValues: result))
  }
  private init(entries: [String: Entry]) {
    self.entries = entries
  }

  /// Converts into virtual path entries.
  func toVirtualOutputFileMap() throws -> [VirtualPath : [FileType : VirtualPath]] {
    Dictionary(try entries.map { input, entry in
      (try VirtualPath(path: input), try entry.paths.mapValues(VirtualPath.init(path:)))
    }, uniquingKeysWith: { $1 })
  }

  /// Converts from virtual path entries
  static func fromVirtualOutputFileMap(
    _ entries: [VirtualPath : [FileType : VirtualPath]]
  ) -> Self {
    func convert(entry: (key: VirtualPath, value: [FileType: VirtualPath])) -> (String, Entry) {
      // We use a VirtualPath with an empty path for the master entry, but its name is "." and we need ""
      let fixedIfMaster = entry.key.name == "." ? "" : entry.key.name
      return (fixedIfMaster, convert(outputs: entry.value))
    }
    func convert(outputs: [FileType: VirtualPath]) -> Entry {
      Entry(paths: outputs.mapValues({ $0.name }))
    }
    return Self(entries: Dictionary(uniqueKeysWithValues: entries.map(convert(entry:))))
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

extension VirtualPath {
  fileprivate func resolvedRelativePath(base: AbsolutePath) -> VirtualPath {
    guard case let .relative(relPath) = self else { return self }
    return .absolute(.init(base, relPath))
  }
}
