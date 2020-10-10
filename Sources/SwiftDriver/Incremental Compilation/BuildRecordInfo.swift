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
@_spi(Testing) public class BuildRecordInfo {
  let buildRecordPath: VirtualPath
  let fileSystem: FileSystem
  let argsHash: String
  let actualSwiftVersion: String
  let timeBeforeFirstJob: Date
  let diagnosticEngine: DiagnosticsEngine
  let outputBuildRecordForModuleOnlyBuild: Bool
  let compilationInputModificationDates: [TypedVirtualPath: Date]

  var finishedJobResults  = [Job: ProcessResult]()

  init?(
    actualSwiftVersion: String,
    compilerOutputType: FileType?,
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
    // If we emit module along with full compilation, emit build record
    // file for '-emit-module' only mode as well.
    self.outputBuildRecordForModuleOnlyBuild = moduleOutputInfo.output?.isTopLevel ?? false
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
    return SHA256().hash(hashInput).hexadecimalRepresentation
  }

  /// Determine the input and output path for the build record
  private static func computeBuildRecordPath(
    outputFileMap: OutputFileMap?,
    compilerOutputType: FileType?,
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
    // In 'emit-module' only mode, use build-record filename suffixed with
    // '~moduleonly', so that module-only mode doesn't mess up build-record
    // file for full compilation.
    return compilerOutputType == .swiftModule
      ? partialBuildRecordPath.appendingToBaseName("~moduleonly")
      : partialBuildRecordPath
  }

  /// Write out the build record.
  /// \c Jobs must include all of the compilation jobs.
  /// \c Inputs will hold all the primary inputs that were not compiled because of incremental compilation
  func writeBuildRecord(_ jobs: [Job], _ skippedInputs: Set<TypedVirtualPath>? ) {
    let buildRecord = InputInfoMap(
      jobs: jobs,
      finishedJobResults: finishedJobResults,
      skippedInputs: skippedInputs,
      compilationInputModificationDates: compilationInputModificationDates,
      actualSwiftVersion: actualSwiftVersion,
      argsHash: argsHash,
      timeBeforeFirstJob: timeBeforeFirstJob)

    let contents: String
    do {  contents = try buildRecord.encode() }
    catch let InputInfoMap.Errors.notAbsolutePath(p) {
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

    if outputBuildRecordForModuleOnlyBuild {
      // If we emit module along with full compilation, emit build record
      // file for '-emit-module' only mode as well.
      // TODO: Optimize with clonefile(2)
      try? fileSystem.copy(
        from: absPath,
        to: AbsolutePath(buildRecordPath.absolutePath!.pathString + "~moduleonly"))
    }
  }

// TODO: Incremental too many names, buildRecord InputInfoMap outofdatemap
  func populateOutOfDateMap() -> InputInfoMap? {
    do {
      let contents = try fileSystem.readFileContents(buildRecordPath).cString
      return try InputInfoMap(contents: contents)
    }
    catch {
      diagnosticEngine.emit(.remark_could_not_read_build_record(buildRecordPath, error))
      return nil
    }
  }

  func job(_ job: Job, finishedWithResult result: ProcessResult) {
    // REDUNDANT?
    if let _ = finishedJobResults.updateValue(result, forKey: job) {
      fatalError("job finished twice?!")
    }
  }
}
