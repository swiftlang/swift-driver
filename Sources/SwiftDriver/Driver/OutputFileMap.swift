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

    // Create a temporary file
    let baseName: String
    switch inputFile {
    case .absolute(let path):
      baseName = path.basenameWithoutExt
    case .relative(let path), .temporary(let path):
      baseName = path.basenameWithoutExt
    case .standardInput:
      baseName = ""
    case .standardOutput:
      fatalError("Standard output cannot be an input file")
    }

    // Form the virtual path.
    return .temporary(RelativePath(baseName.appendingFileTypeExtension(outputType)))
  }

  public func existingOutput(inputFile: VirtualPath, outputType: FileType) -> VirtualPath? {
    entries[inputFile]?[outputType]
  }

  public func existingOutputForSingleInput(outputType: FileType) -> VirtualPath? {
    try! existingOutput(inputFile: VirtualPath(path: ""), outputType: outputType)
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
    enum CodingKeys: String, CodingKey {
      case dependencies
      case object
      case swiftmodule
      case swiftinterface
      case swiftDependencies = "swift-dependencies"
      case diagnostics
    }

    let dependencies: String?
    let object: String?
    let swiftmodule: String?
    let swiftinterface: String?
    let swiftDependencies: String?
    let diagnostics: String?
  }

  /// The parsed entires
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
    var result: [VirtualPath : [FileType : VirtualPath]] = [:]

    for (input, entry) in entries {
      let input = try VirtualPath(path: input)

      var map: [FileType: String] = [:]
      map[.dependencies] = entry.dependencies
      map[.object] = entry.object
      map[.swiftModule] = entry.swiftmodule
      map[.swiftInterface] = entry.swiftinterface
      map[.swiftDeps] = entry.swiftDependencies
      map[.diagnostics] = entry.diagnostics

      result[input] = try map.mapValues(VirtualPath.init(path:))
    }

    return result
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
      Entry(
        dependencies: outputs[.dependencies]?.name,
        object: outputs[.object]?.name,
        swiftmodule: outputs[.swiftModule]?.name,
        swiftinterface: outputs[.swiftInterface]?.name,
        swiftDependencies: outputs[.swiftDeps]?.name,
        diagnostics: outputs[.diagnostics]?.name)
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
