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

import class TSCBasic.DiagnosticsEngine
import struct TSCBasic.AbsolutePath
import struct TSCBasic.Diagnostic

@_implementationOnly import Yams

/// Holds the info about inputs needed to plan incremenal compilation
/// A.k.a. BuildRecord was the legacy name
public struct BuildRecord {
  public let swiftVersion: String
  /// When testing, the argsHash may be missing from the build record
  public let argsHash: String
  /// Next compile, will compare an input mod time against the start time of the previous build
  public let buildStartTime: TimePoint
  /// Next compile, will compare an output mod time against the end time of the previous build
  public let buildEndTime: TimePoint
  /// The date is the modification time of the main input file the last time the driver ran
  public let inputInfos: [VirtualPath: InputInfo]

  public init(argsHash: String,
              swiftVersion: String,
              buildStartTime: TimePoint,
              buildEndTime: TimePoint,
              inputInfos: [VirtualPath: InputInfo]) {
    self.argsHash = argsHash
    self.swiftVersion = swiftVersion
    self.buildStartTime = buildStartTime
    self.buildEndTime = buildEndTime
    self.inputInfos = inputInfos
  }

  public enum SectionName: String, CaseIterable {
    case swiftVersion = "version"
    case argsHash = "options"
    // Implement this for a smoother transition
    case legacyBuildStartTime = "build_time"
    case buildStartTime = "build_start_time"
    case buildEndTime = "build_end_time"
    case inputInfos = "inputs"

    var serializedName: String { rawValue }
  }

  var allInputs: Set<VirtualPath> {
    Set(inputInfos.map { $0.key })
  }
}

// MARK: - Reading the old map and deciding whether to use it
public extension BuildRecord {
  enum Error: Swift.Error {
    case malformedYAML
    case invalidKey
    case missingTimeStamp
    case missingInputSequenceNode
    case missingInputEntryNode
    case missingPriorBuildState
    case unexpectedKey(String)
    case malformed(SectionName)

    var reason: String {
      switch self {
      case .malformedYAML:
        return ""
      case .invalidKey:
        return ""
      case .missingTimeStamp:
        return "could not read time value in build record"
      case .missingInputSequenceNode:
        return "no sequence node for input entry in build record"
      case .missingInputEntryNode:
        return "no input entry in build record"
      case .missingPriorBuildState:
        return "no previous build state in build record"
      case .unexpectedKey(let key):
        return "Unexpected key '\(key)'"
      case .malformed(let section):
        return "Malformed value for key '\(section.serializedName)'"
      }
    }
  }
  init(contents: String) throws {
    guard let sections = try? Parser(yaml: contents, resolver: .basic, encoding: .utf8)
            .singleRoot()?.mapping
    else {
      throw Error.malformedYAML
    }
    var argsHash: String?
    var swiftVersion: String?
    // Legacy driver does not disable incremental if no buildTime field.
    var buildStartTime: TimePoint = .distantPast
    var buildEndTime: TimePoint = .distantFuture
    var inputInfos: [VirtualPath: InputInfo]?
    for (key, value) in sections {
      guard let k = key.string else {
        throw Error.invalidKey
      }
      switch k {
      case SectionName.swiftVersion.serializedName:
        // There's a test that uses "" for an illegal value
        guard let s = value.string, s != "" else {
          break
        }
        swiftVersion = s
      case SectionName.argsHash.serializedName:
        guard let s = value.string, s != "" else {
          break
        }
        argsHash = s
      case SectionName.buildStartTime.serializedName,
           SectionName.legacyBuildStartTime.serializedName:
        buildStartTime = try Self.decodeDate(value, forInputInfo: false)
      case SectionName.buildEndTime.serializedName:
        buildEndTime = try Self.decodeDate(value, forInputInfo: false)
      case SectionName.inputInfos.serializedName:
        inputInfos = try Self.decodeInputInfos(value)
      default:
        throw Error.unexpectedKey(k)
      }
    }
    // The legacy driver allows argHash to be absent to ease testing.
    // Mimic the legacy driver for testing ease: If no `argsHash` section,
    // record still matches.
    guard let sv = swiftVersion else {
      throw Error.malformed(.swiftVersion)
    }
    guard let iis = inputInfos else {
      throw Error.malformed(.inputInfos)
    }
    guard let argsHash = argsHash else {
      throw Error.malformed(.argsHash)
    }
    self.init(argsHash: argsHash,
              swiftVersion: sv,
              buildStartTime: buildStartTime,
              buildEndTime: buildEndTime,
              inputInfos: iis)
  }

  private static func decodeDate(
    _ node: Yams.Node,
    forInputInfo: Bool
  ) throws -> TimePoint {
    guard let vals = node.sequence else {
      if forInputInfo {
        throw Error.missingInputSequenceNode
      } else {
        throw Error.missingTimeStamp
      }
    }
    guard vals.count == 2,
          let secs = vals[0].int,
          let ns = vals[1].int
    else {
      throw Error.missingTimeStamp
    }
    return TimePoint(seconds: UInt64(secs), nanoseconds: UInt32(ns))
  }

  private static func decodeInputInfos(
    _ node: Yams.Node
  ) throws -> [VirtualPath: InputInfo] {
    guard let map = node.mapping else {
      throw BuildRecord.Error.malformed(.inputInfos)
    }
    var infos = [VirtualPath: InputInfo]()
    for (keyNode, valueNode) in map {
      guard let pathString = keyNode.string,
            let path = try? VirtualPath(path: pathString)
      else {
        throw BuildRecord.Error.missingInputEntryNode
      }
      let previousModTime = try decodeDate(valueNode, forInputInfo: true)
      let inputInfo = try InputInfo(
        tag: valueNode.tag.description, previousModTime: previousModTime)
      infos[path] = inputInfo
    }
    return infos
   }
}

// MARK: - Creating and writing a new map
extension BuildRecord {
  /// Create a new buildRecord for writing
  init(jobs: [Job],
       finishedJobResults: [BuildRecordInfo.JobResult],
       skippedInputs: Set<TypedVirtualPath>?,
       compilationInputModificationDates: [TypedVirtualPath: TimePoint],
       actualSwiftVersion: String,
       argsHash: String,
       timeBeforeFirstJob: TimePoint,
       timeAfterLastJob: TimePoint
  ) {
    let jobResultsByInput = Dictionary(uniqueKeysWithValues:
      finishedJobResults.flatMap { entry in
        entry.job.inputsGeneratingCode.map { ($0, entry.result) }
    })
    let inputInfosArray = compilationInputModificationDates
      .map { input, modDate -> (VirtualPath, InputInfo) in
        let status = InputInfo.Status(  wasSkipped: skippedInputs?.contains(input),
                                        jobResult: jobResultsByInput[input])
        return (input.file, InputInfo(status: status, previousModTime: modDate))
      }

    self.init(
      argsHash: argsHash,
      swiftVersion: actualSwiftVersion,
      buildStartTime: timeBeforeFirstJob,
      buildEndTime: timeAfterLastJob,
      inputInfos: Dictionary(uniqueKeysWithValues: inputInfosArray)
    )
  }

  /// Pass in `currentArgsHash` to ensure it is non-nil
  public func encode(diagnosticEngine: DiagnosticsEngine) -> String? {
      let pathsAndInfos = inputInfos.map {
        input, inputInfo -> (String, InputInfo) in
        return (input.name, inputInfo)
      }
      let inputInfosNode = Yams.Node(
        pathsAndInfos
          .sorted {$0.0 < $1.0}
          .map {(Yams.Node($0.0, .implicit, .doubleQuoted), Self.encode($0.1))}
      )
    let fieldNodes = [
      (SectionName.swiftVersion,    Yams.Node(swiftVersion,    .implicit, .doubleQuoted)),
      (SectionName.argsHash,        Yams.Node(argsHash, .implicit, .doubleQuoted)),
      (SectionName.buildStartTime,  Self.encode(buildStartTime)),
      (SectionName.buildEndTime,    Self.encode(buildEndTime)),
      (SectionName.inputInfos,      inputInfosNode )
      ] .map { (Yams.Node($0.0.serializedName), $0.1) }

    let buildRecordNode = Yams.Node(fieldNodes, .implicit, .block)
   // let options = Yams.Emitter.Options(canonical: true)
    do {
      return try Yams.serialize(node: buildRecordNode,
                                width: -1,
                                sortKeys: false)
    } catch {
      diagnosticEngine.emit(.warning_could_not_serialize_build_record(error))
      return nil
    }
  }

  private static func encode(_ date: TimePoint, tag tagString: String? = nil) -> Yams.Node {
    return Yams.Node(
      [ Yams.Node(String(date.seconds)), Yams.Node(String(date.nanoseconds)) ],
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


// MARK: - reading
extension InputInfo {
  fileprivate init(
    tag: String,
    previousModTime: TimePoint
  ) throws {
    guard let status = Status(identifier: tag) else {
      throw BuildRecord.Error.missingPriorBuildState
    }
    self.init(status: status, previousModTime: previousModTime)
  }
}

// MARK: - writing
extension InputInfo {
  fileprivate var tag: String { status.identifier }
}
