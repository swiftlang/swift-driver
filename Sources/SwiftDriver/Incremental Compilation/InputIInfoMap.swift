//===--------------- InputInfoMap.swift - Swift Input File Info Map -------===//
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
@_implementationOnly import Yams

/// Holds the info about inputs needed to plan incremenal compilation
public struct InputInfoMap {
  public let swiftVersion: String
  public let argsHash: String
  public let buildTime: Date
  /// The date is the modification time of the main input file the last time the driver ran
  public let inputInfos: [VirtualPath: InputInfo]

  public init(  argsHash: String,
                swiftVersion: String,
                buildTime: Date,
                inputInfos: [VirtualPath: InputInfo]) {
    self.argsHash = argsHash
    self.swiftVersion = swiftVersion
    self.buildTime = buildTime
    self.inputInfos = inputInfos
  }

  enum SimpleErrors: String, LocalizedError {
    case
    couldNotDecodeInputInfoMap,
    sectionNameNotString,
    dateValuesNotSequence,
    dateValuesNotDuo,
    dateValuesNotInts,
    inputInfosNotAMap,
    inputNotString,
    noVersion,
    noArgsHash,
    noBuildTime,
    noInputInfos

    var localizedDescription: String { return rawValue }
  }
  enum Errors: LocalizedError {
    case
    unexpectedSection(String),
    notAbsolutePath(VirtualPath)

    public var localizedDescription: String {
      switch self {
      case .unexpectedSection(let s): return "unexpected section \(s)"
      case .notAbsolutePath(let p): return "not absolute path \(p)"
      }
    }
  }
}

// MARK: - Reading the old map and deciding whether to use it
public extension InputInfoMap {
  private enum SectionName: String, CaseIterable {
  case
    swiftVersion = "version",
    argsHash = "options",
    buildTime = "build_time",
    inputInfos = "inputs"
  }


  init(contents: String) throws {
    guard let sections = try Parser(yaml: contents, resolver: .basic, encoding: .utf8)
      .singleRoot()?.mapping
      else { throw SimpleErrors.couldNotDecodeInputInfoMap }
    var argsHash, swiftVersion: String?
    var buildTime: Date?
    var inputInfos: [VirtualPath: InputInfo]?
    for (key, value) in sections {
      guard let k = key.string else { throw SimpleErrors.sectionNameNotString }
      // TODO: Incremental use SectionNames here
      switch k {
      case "version": swiftVersion = value.string
      case "options": argsHash = value.string
      case "build_time": buildTime = try Self.decodeDate(value)
      case "inputs": inputInfos = try Self.decodeInputInfos(value)
      default: throw Errors.unexpectedSection(k)
      }
    }
    try self.init(argsHash: argsHash, swiftVersion: swiftVersion, buildTime: buildTime,
                  inputInfos: inputInfos)
  }

  private init(argsHash: String?, swiftVersion: String?, buildTime: Date?,
               inputInfos: [VirtualPath: InputInfo]?)
    throws {
      guard let a = argsHash else { throw SimpleErrors.noArgsHash }
      guard let s = swiftVersion else { throw SimpleErrors.noVersion }
      guard let b = buildTime else { throw SimpleErrors.noBuildTime }
      guard let i = inputInfos else { throw SimpleErrors.noInputInfos }
      self.init(argsHash: a, swiftVersion: s, buildTime: b, inputInfos: i)
  }

  private static func decodeDate(_ node: Yams.Node) throws -> Date {
    guard let vals = node.sequence else { throw SimpleErrors.dateValuesNotSequence }
    guard vals.count == 2 else {throw SimpleErrors.dateValuesNotDuo}
    guard let secs = vals[0].int, let ns = vals[1].int
    else {throw SimpleErrors.dateValuesNotInts}
    return Date(legacyDriverSecs: secs, nanos: ns)
  }

  private static func decodeInputInfos(_ node: Yams.Node) throws -> [VirtualPath: InputInfo] {
    guard let map = node.mapping else { throw SimpleErrors.inputInfosNotAMap }
    return try Dictionary(uniqueKeysWithValues:
      map.map {
        keyNode, valueNode in
        guard let path = keyNode.string else { throw SimpleErrors.inputNotString }
        return try (
          VirtualPath(path: path),
          InputInfo(tag: valueNode.tag.description, previousModTime: decodeDate(valueNode))
        )
      }
    )
  }

  /// Returns why it did not match
  @_spi(Testing) func mismatchReason(buildRecordInfo: BuildRecordInfo, inputFiles: [TypedVirtualPath]) -> String? {
    guard buildRecordInfo.actualSwiftVersion == self.swiftVersion else {
      return "the compiler version has changed from \(self.swiftVersion) to \(buildRecordInfo.actualSwiftVersion)"
    }
    guard buildRecordInfo.argsHash == self.argsHash else {
      return "different arguments were passed to the compiler"
    }
    let missingInputs = Set(self.inputInfos.keys).subtracting(inputFiles.map {$0.file})
    guard missingInputs.isEmpty else {
      return "the following inputs were used in the previous compilation but not in this one: "
        + missingInputs.map {$0.name} .joined(separator: ", ")
    }
    return nil
  }
}

// MARK: - Creating and writing a new map
extension InputInfoMap {
  /// Create a new buildRecord for writing
  init(jobs: [Job],
       finishedJobResults: [Job: ProcessResult],
       skippedInputs: Set<TypedVirtualPath>?,
       compilationInputModificationDates: [TypedVirtualPath: Date],
       actualSwiftVersion: String,
       argsHash: String,
       timeBeforeFirstJob: Date
  ) {
    let jobResultsByInput = Dictionary(
      uniqueKeysWithValues:
        finishedJobResults.flatMap { job, result in
          job.primaryInputs.map { ($0, result)  }
        }
    )
    let inputInfosArray = compilationInputModificationDates
      .map { input, modDate -> (VirtualPath, InputInfo) in
        let status = InputInfo.Status(  wasSkipped: skippedInputs?.contains(input),
                                        jobResult: jobResultsByInput[input])
        return (input.file, InputInfo(status: status, previousModTime: modDate))
      }

    self.init(
      argsHash: argsHash,
      swiftVersion: actualSwiftVersion,
      buildTime: timeBeforeFirstJob,
      inputInfos: Dictionary(uniqueKeysWithValues: inputInfosArray)
    )
  }

  func encode() throws -> String {
      let pathsAndInfos = try inputInfos.map {
        input, inputInfo -> (String, InputInfo) in
        guard let path = input.absolutePath else {
          throw Errors.notAbsolutePath(input)
        }
        return (path.pathString, inputInfo)
      }
      let inputInfosNode = Yams.Node(
        pathsAndInfos
          .sorted {$0.0 < $1.0}
          .map {(Yams.Node($0.0), Self.encode($0.1))}
      )
      let fieldNodes = [
        ("version", Yams.Node(swiftVersion)),
        ("options", Yams.Node(argsHash)),
        ("build_time", Self.encode(buildTime)),
        ("inputs", inputInfosNode )
      ] .map { (Yams.Node($0.0), $0.1) }

      let inputInfoMapNode = Yams.Node(fieldNodes)
      return try Yams.serialize(node: inputInfoMapNode)
  }

  private static func encode(_ date: Date, tag tagString: String? = nil) -> Yams.Node {
    let secsAndNanos = date.legacyDriverSecsAndNanos
    return Yams.Node(
      secsAndNanos.map {Yams.Node(String($0))},
      tagString.map {Yams.Tag(Yams.Tag.Name(rawValue: $0))} ?? .implicit)
  }

  private static func encode(_ inputInfo: InputInfo) -> Yams.Node {
    encode(inputInfo.previousModTime, tag: inputInfo.tag)
  }

}

extension Diagnostic.Message {
  static func warning_could_not_serialize_build_record(_ err: Error
  ) -> Diagnostic.Message {
    .warning("Next compile won't be incremental; Could not serialize build record: \(err.localizedDescription)")
  }
  static func warning_could_not_write_build_record_not_absolutePath(
    _ path: VirtualPath
  ) -> Diagnostic.Message {
    .warning("Next compile won't be incremental; build record path was not absolute: \(path)")
  }
  static func warning_could_not_write_build_record(_ path: AbsolutePath
  ) -> Diagnostic.Message {
    .warning("Next compile won't be incremental; could not write build record to \(path)")
  }
}

extension Diagnostic.Message {
  static func remark_could_not_read_build_record(_ path: VirtualPath,
                                                 _ error: Error
  ) -> Diagnostic.Message {
    .remark("Incremental compilation could not read build record at \(path): \(error.localizedDescription).")
  }
}
