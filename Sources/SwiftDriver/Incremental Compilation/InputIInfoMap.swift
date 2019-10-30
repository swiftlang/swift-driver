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
}

// Reading
public extension InputInfoMap {
  private enum SectionName: String, CaseIterable {
  case
    swiftVersion = "version",
    argsHash = "options",
    buildTime = "build_time",
    inputInfos = "inputs"
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
    unexpectedSection(String)
    public var localizedDescription: String {
      switch self {
      case .unexpectedSection(let s): return "unexpected section \(s)"
      }
    }
  }

  init(contents: String) throws {
    guard let sections = try Parser(yaml: contents, resolver: .basic, encoding: .utf8)
      .singleRoot()?.mapping
      else { throw SimpleErrors.couldNotDecodeInputInfoMap }
    var argsHash, swiftVersion: String?
    var buildTime: Date?
    var inputInfos: [VirtualPath: InputInfo]?
    for (key, value) in sections {
      guard let k = key.string else {throw SimpleErrors.sectionNameNotString}
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
      guard let a = argsHash else {throw SimpleErrors.noArgsHash}
      guard let s = swiftVersion else {throw SimpleErrors.noVersion}
      guard let b = buildTime else {throw SimpleErrors.noBuildTime }
      guard let i = inputInfos else {throw SimpleErrors.noInputInfos }
      self.init( argsHash: a, swiftVersion: s, buildTime: b, inputInfos: i)
  }

  static private func decodeDate(_ node: Yams.Node) throws -> Date {
    guard let vals = node.sequence else {throw SimpleErrors.dateValuesNotSequence}
    guard vals.count == 2 else {throw SimpleErrors.dateValuesNotDuo}
    guard let secs = vals[0].int, let ns = vals[1].int
    else {throw SimpleErrors.dateValuesNotInts}
    return Date(legacyDriverSecs: secs, nanos: ns)
  }

  static private func decodeInputInfos(_ node: Yams.Node) throws -> [VirtualPath: InputInfo] {
    guard let map = node.mapping else {throw SimpleErrors.inputInfosNotAMap}
    return try Dictionary(uniqueKeysWithValues:
      map.map {
        keyNode, valueNode in
        guard let path = keyNode.string else {throw SimpleErrors.inputNotString}
        return try (
          VirtualPath(path: path),
          InputInfo(tag: valueNode.tag.description, previousModTime: decodeDate(valueNode))
        )
    }
    )
  }
}



/// Reading the old map and deciding whether to use it
public extension InputInfoMap {
  static func populateOutOfDateMap(
    argsHash: String,
    lastBuildTime: Date,
    inputFiles: [TypedVirtualPath],
    buildRecordPath: AbsolutePath,
    showIncrementalBuildDecisions: Bool,
    diagnosticEngine: DiagnosticsEngine
  ) -> Self? {
    let contents: String
    do {
      contents = try localFileSystem.readFileContents(buildRecordPath).cString
      return try Self(contents: contents)
    }
    catch {
      if showIncrementalBuildDecisions {
        diagnosticEngine.emit(.remark_could_not_read_build_record(error))
      }
      return nil
    }
  }

  /// Returns why it did not match
  func matches(argsHash: String, inputFiles: [TypedVirtualPath], actualSwiftVersion: String?) -> String? {
    guard let actualSwiftVersion = actualSwiftVersion else {
      return "the version of the compiler we will be using could not determined"
    }
    guard actualSwiftVersion == self.swiftVersion else {
      return "the compiler version has changed from \(self.swiftVersion) to \(actualSwiftVersion)"
    }
    guard argsHash == self.argsHash else {
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


extension Diagnostic.Message {
  static func remark_could_not_read_build_record(_ error: Error) -> Diagnostic.Message {
    .remark("Incremental compilation could not read build record: \(error.localizedDescription).")
  }
}
