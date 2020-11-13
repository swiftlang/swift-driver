//===--------------- BuildRecord.swift - Swift Input File Info Map -------===//
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
/// A.k.a. BuildRecord was the legacy name
public struct BuildRecord {
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
    couldNotDecodeBuildRecord,
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
  private enum SectionName: String, CaseIterable {
  case
    swiftVersion = "version",
    argsHash = "options",
    buildTime = "build_time",
    inputInfos = "inputs"

    var serializedName: String { rawValue }
  }
}

// MARK: - Reading the old map and deciding whether to use it
public extension BuildRecord {
  init(contents: String) throws {
    guard let sections = try Parser(yaml: contents, resolver: .basic, encoding: .utf8)
      .singleRoot()?.mapping
      else { throw SimpleErrors.couldNotDecodeBuildRecord }
    var argsHash, swiftVersion: String?
    var buildTime: Date?
    var inputInfos: [VirtualPath: InputInfo]?
    for (key, value) in sections {
      guard let k = key.string else { throw SimpleErrors.sectionNameNotString }
      switch k {
      case SectionName.swiftVersion.serializedName:
        swiftVersion = value.string
      case SectionName.argsHash.serializedName:
        argsHash = value.string
      case SectionName.buildTime.serializedName:
        buildTime = try Self.decodeDate(value)
      case SectionName.inputInfos.serializedName:
        inputInfos = try Self.decodeInputInfos(value)
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
}

// MARK: - Creating and writing a new map
extension BuildRecord {
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
          .map {(Yams.Node($0.0, .implicit, .doubleQuoted), Self.encode($0.1))}
      )
    let fieldNodes = [
      (SectionName.swiftVersion, Yams.Node(swiftVersion, .implicit, .doubleQuoted)),
      (SectionName.argsHash,     Yams.Node(argsHash, .implicit, .doubleQuoted)),
      (SectionName.buildTime,    Self.encode(buildTime)),
      (SectionName.inputInfos,   inputInfosNode )
      ] .map { (Yams.Node($0.0.serializedName), $0.1) }

    let buildRecordNode = Yams.Node(fieldNodes, .implicit, .block)
   // let options = Yams.Emitter.Options(canonical: true)
    return try Yams.serialize(node: buildRecordNode,
                              width: -1,
                              sortKeys: false)
  }

  private static func encode(_ date: Date, tag tagString: String? = nil) -> Yams.Node {
    let secsAndNanos = date.legacyDriverSecsAndNanos
    return Yams.Node(
      secsAndNanos.map {Yams.Node(String($0))},
      tagString.map {Yams.Tag(Yams.Tag.Name(rawValue: $0))} ?? .implicit,
      .flow)
  }

  private static func encode(_ inputInfo: InputInfo) -> Yams.Node {
    encode(inputInfo.previousModTime, tag: inputInfo.tag)
  }

}

extension Diagnostic.Message {
  static func warning_could_not_serialize_build_record(_ err: Error
  ) -> Diagnostic.Message {
    .warning("next compile won't be incremental; Could not serialize build record: \(err.localizedDescription)")
  }
  static func warning_could_not_write_build_record_not_absolutePath(
    _ path: VirtualPath
  ) -> Diagnostic.Message {
    .warning("next compile won't be incremental; build record path was not absolute: \(path)")
  }
  static func warning_could_not_write_build_record(_ path: AbsolutePath
  ) -> Diagnostic.Message {
    .warning("next compile won't be incremental; could not write build record to \(path)")
  }
}
