//===--------------- BuildRecordInfo.swift --------------------------------===//
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

import Foundation
import TSCBasic
import SwiftOptions

/// Holds information required to read and write the build record (aka compilation record)
/// This info is always written, but only read for incremental compilation.
 class BuildRecordInfo {
  let buildRecordPath: VirtualPath
  let fileSystem: FileSystem
  let argsHash: String
  let actualSwiftVersion: String
  let timeBeforeFirstJob: Date
  let diagnosticEngine: DiagnosticsEngine
  let compilationInputModificationDates: [TypedVirtualPath: Date]

  var finishedJobResults  = [Job: ProcessResult]()

  init?(
    actualSwiftVersion: String,
    compilerOutputType: FileType?,
    workingDirectory: AbsolutePath?,
    diagnosticEngine: DiagnosticsEngine,
    fileSystem: FileSystem,
    moduleOutputInfo: ModuleOutputInfo,
    outputFileMap: OutputFileMap?,
    parsedOptions: ParsedOptions,
    recordedInputModificationDates: [TypedVirtualPath: Date]
  ) {
    // Cannot write a buildRecord without a path.
    guard let buildRecordPath = Self.computeBuildRecordPath(
            outputFileMap: outputFileMap,
            compilerOutputType: compilerOutputType,
            workingDirectory: workingDirectory,
            diagnosticEngine: diagnosticEngine)
    else {
      return nil
    }
    self.actualSwiftVersion = actualSwiftVersion
    self.argsHash = Self.computeArgsHash(parsedOptions)
    self.buildRecordPath = buildRecordPath
    self.compilationInputModificationDates =
      recordedInputModificationDates.filter { input, _ in
        input.type.isPartOfSwiftCompilation
      }
    self.diagnosticEngine = diagnosticEngine
    self.fileSystem = fileSystem
    self.timeBeforeFirstJob = Date()
   }

  private static func computeArgsHash(_ parsedOptionsArg: ParsedOptions
  ) -> String {
    var parsedOptions = parsedOptionsArg
    let hashInput = parsedOptions
      .filter { $0.option.affectsIncrementalBuild && $0.option.kind != .input}
      .map { $0.option.spelling }
      .sorted()
      .joined()
    #if os(macOS)
    if #available(macOS 10.15, iOS 13, *) {
      return CryptoKitSHA256().hash(hashInput).hexadecimalRepresentation
    } else {
      return SHA256().hash(hashInput).hexadecimalRepresentation
    }
    #else
    return SHA256().hash(hashInput).hexadecimalRepresentation
    #endif
  }

  /// Determine the input and output path for the build record
  private static func computeBuildRecordPath(
    outputFileMap: OutputFileMap?,
    compilerOutputType: FileType?,
    workingDirectory: AbsolutePath?,
    diagnosticEngine: DiagnosticsEngine
  ) -> VirtualPath? {
    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard let ofm = outputFileMap else {
      return nil
    }
    guard let partialBuildRecordPath =
            ofm.existingOutputForSingleInput(outputType: .swiftDeps)
    else {
      diagnosticEngine.emit(.warning_incremental_requires_build_record_entry)
      return nil
    }
    return workingDirectory
      .map(partialBuildRecordPath.resolvedRelativePath(base:))
      ?? partialBuildRecordPath
  }

  /// Write out the build record.
  /// `Jobs` must include all of the compilation jobs.
  /// `Inputs` will hold all the primary inputs that were not compiled because of incremental compilation
  func writeBuildRecord(_ jobs: [Job], _ skippedInputs: Set<TypedVirtualPath>? ) {
    let buildRecord = BuildRecord(
      jobs: jobs,
      finishedJobResults: finishedJobResults,
      skippedInputs: skippedInputs,
      compilationInputModificationDates: compilationInputModificationDates,
      actualSwiftVersion: actualSwiftVersion,
      argsHash: argsHash,
      timeBeforeFirstJob: timeBeforeFirstJob)

    let contents: String
    do {  contents = try buildRecord.encode() }
    catch let BuildRecord.Errors.notAbsolutePath(p) {
      diagnosticEngine.emit(
        .warning_could_not_write_build_record_not_absolutePath(p))
      return
    }
    catch {
      diagnosticEngine.emit(.warning_could_not_serialize_build_record(error))
      return
    }
    guard let absPath = buildRecordPath.absolutePath else {
      diagnosticEngine.emit(
        .warning_could_not_write_build_record_not_absolutePath(buildRecordPath))
      return
    }
    do {
      try fileSystem.writeFileContents(absPath,
                                       bytes: ByteString(encodingAsUTF8: contents))
    }
    catch {
      diagnosticEngine.emit(.warning_could_not_write_build_record(absPath))
      return
    }
 }

// TODO: Incremental too many names, buildRecord BuildRecord outofdatemap
  func populateOutOfDateBuildRecord(
    inputFiles: [TypedVirtualPath],
    failed: (String) -> Void
  ) -> BuildRecord? {
    let outOfDateBuildRecord: BuildRecord
    do {
      let contents = try fileSystem.readFileContents(buildRecordPath).cString
      outOfDateBuildRecord  = try BuildRecord(contents: contents)
    }
    catch {
      failed("incremental compilation could not read build record at \(buildRecordPath): \(error.localizedDescription).")
      return nil
    }
    guard actualSwiftVersion == outOfDateBuildRecord.swiftVersion else {
      failed(
        "the compiler version has changed from \(outOfDateBuildRecord.swiftVersion) to \(actualSwiftVersion)"
      )
      return nil
    }
    guard argsHash == outOfDateBuildRecord.argsHash else {
      failed( "different arguments were passed to the compiler" )
      return nil
    }
    let missingInputs = Set(outOfDateBuildRecord.inputInfos.keys).subtracting(inputFiles.map {$0.file})
    guard missingInputs.isEmpty else {
      failed( "the following inputs were used in the previous compilation but not in this one: "
                + missingInputs.map {$0.basename} .joined(separator: ", "))
      return nil
    }
    return outOfDateBuildRecord
  }

  func jobFinished(job: Job, result: ProcessResult) {
    // REDUNDANT?
    if let _ = finishedJobResults.updateValue(result, forKey: job) {
      fatalError("job finished twice?!")
    }
  }
}
