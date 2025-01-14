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

import struct Foundation.Data
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder

import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import struct TSCBasic.RelativePath

/// Mapping of input file paths to specific output files.
public struct OutputFileMap: Hashable, Codable {
  static let singleInputKey = try! VirtualPath.intern(path: ".")

  /// The known mapping from input file to specific output files.
  public var entries: [VirtualPath.Handle: [FileType: VirtualPath.Handle]] = [:]

  public init() { }

  public init(entries: [VirtualPath.Handle: [FileType: VirtualPath.Handle]]) {
    self.entries = entries
  }

  /// For the given input file, retrieve or create an output file for the given
  /// file type.
  public func getOutput(inputFile: VirtualPath.Handle, outputType: FileType) throws -> VirtualPath.Handle {
    // If we already have an output file, retrieve it.
    if let output = try existingOutput(inputFile: inputFile, outputType: outputType) {
      return output
    }

    let inputFile = VirtualPath.lookup(inputFile)
    if inputFile == .standardOutput {
      fatalError("Standard output cannot be an input file")
    }

    // Form the virtual path.
    return try VirtualPath.createUniqueTemporaryFile(RelativePath(validating: inputFile.basenameWithoutExt.appendingFileTypeExtension(outputType))).intern()
  }

  public func existingOutput(inputFile: VirtualPath.Handle, outputType: FileType) throws -> VirtualPath.Handle? {
    if let path = entries[inputFile]?[outputType] {
      return path
    }
    switch outputType {
    case .swiftDocumentation, .swiftSourceInfoFile:
      // Infer paths for these entities using .swiftmodule path.
      guard let path = entries[inputFile]?[.swiftModule] else {
        return nil
      }
      return try VirtualPath.lookup(path).replacingExtension(with: outputType).intern()

    case .jsonAPIBaseline, .jsonABIBaseline:
      // Infer paths for these entities using .swiftsourceinfo path.
      guard let path = entries[inputFile]?[.swiftSourceInfoFile] else {
        return nil
      }
      return try VirtualPath.lookup(path).replacingExtension(with: outputType).intern()

    case .object:
      // We may generate .o files from bitcode .bc files, but the output file map
      // uses .swift file as the key for .o file paths. So we need to dig further.
      let entry = entries.first {
        return $0.value.contains { return $0.value == inputFile }
      }
      if let entry = entry {
        if let path = entries[entry.key]?[outputType] {
          return path
        }
      }
      return nil
    default:
      return nil
    }
  }

  public func existingOutputForSingleInput(outputType: FileType) throws -> VirtualPath.Handle? {
    try existingOutput(inputFile: Self.singleInputKey, outputType: outputType)
  }

  public func resolveRelativePaths(relativeTo absPath: AbsolutePath) -> OutputFileMap {
    let resolvedKeyValues: [(VirtualPath.Handle, [FileType : VirtualPath.Handle])] = entries.map { entry in
      let resolvedKey: VirtualPath.Handle
      // Special case for single dependency record, leave it as is
      if entry.key == Self.singleInputKey {
        resolvedKey = entry.key
      } else {
        resolvedKey = try! VirtualPath.intern(path: VirtualPath.lookup(entry.key).resolvedRelativePath(base: absPath).description)
      }
      let resolvedValue = entry.value.mapValues {
        try! VirtualPath.intern(path: VirtualPath.lookup($0).resolvedRelativePath(base: absPath).description)
      }
      return (resolvedKey, resolvedValue)
    }
    return OutputFileMap(entries: .init(resolvedKeyValues, uniquingKeysWith: { _, _ in
      fatalError("Paths collided after resolving")
    }))
  }

  /// Slow, but only for debugging output
  public func getInput(outputFile: VirtualPath) -> VirtualPath? {
    entries
      .compactMap {
        $0.value.values.contains(outputFile.intern())
          ? VirtualPath.lookup($0.key)
          : nil
      }
      .first
  }

  /// Load the output file map at the given path.
  @_spi(Testing) public static func load(
    fileSystem: FileSystem,
    file: VirtualPath,
    diagnosticEngine: DiagnosticsEngine
  ) throws -> OutputFileMap {
    // Load and decode the file.
    let contents = try fileSystem.readFileContents(file)
    let result = try JSONDecoder().decode(OutputFileMapJSON.self, from: Data(contents.contents))

    // Convert the loaded entries into virtual output file map.
    var outputFileMap = OutputFileMap()
    outputFileMap.entries = try result.toVirtualOutputFileMap()

    return outputFileMap
  }

  /// Store the output file map at the given path.
  public func store(
    fileSystem: FileSystem,
    file: AbsolutePath
  ) throws {
    let encoder = JSONEncoder()

  #if os(Linux) || os(Android)
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  #else
    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }
  #endif

    let contents = try encoder.encode(OutputFileMapJSON.fromVirtualOutputFileMap(entries).entries)
    try fileSystem.writeFileContents(file, bytes: ByteString(contents))
  }

  /// Human-readable textual representation
  var description: String {
    var result = ""
    func outputPairDescription(inputPath: VirtualPath.Handle, outputPair: (FileType, VirtualPath.Handle))
    -> String {
      "\(inputPath.description) -> \(outputPair.0.description): \"\(outputPair.1.description)\"\n"
    }
    let maps = entries.map { ($0, $1) }.sorted { VirtualPath.lookup($0.0).description < VirtualPath.lookup($1.0).description }
    for (input, map) in maps {
      let pairs = map.map { ($0, $1) }.sorted { $0.0.description < $1.0.description }
      for (outputType, outputPath) in pairs {
        result += outputPairDescription(inputPath: input, outputPair: (outputType, outputPath))
      }
    }
    return result
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
  /// `fileprivate` so that the `store` method above can see it
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
  /// `fileprivate` so that the `store` method above can see it
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
  func toVirtualOutputFileMap() throws -> [VirtualPath.Handle : [FileType : VirtualPath.Handle]] {
    Dictionary(try entries.map { input, entry in
      (try VirtualPath.intern(path: input), try entry.paths.mapValues(VirtualPath.intern(path:)))
    }, uniquingKeysWith: { $1 })
  }

  /// Converts from virtual path entries
  static func fromVirtualOutputFileMap(
    _ entries: [VirtualPath.Handle : [FileType : VirtualPath.Handle]]
  ) -> Self {
    func convert(entry: (key: VirtualPath.Handle, value: [FileType: VirtualPath.Handle])) -> (String, Entry) {
      // We use a VirtualPath with an empty path for the master entry, but its name is "." and we need ""
      let fixedIfMaster = VirtualPath.lookup(entry.key).name == "." ? "" : VirtualPath.lookup(entry.key).name
      return (fixedIfMaster, convert(outputs: entry.value))
    }
    func convert(outputs: [FileType: VirtualPath.Handle]) -> Entry {
      Entry(paths: outputs.mapValues({ VirtualPath.lookup($0).name }))
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
