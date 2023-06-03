//===------------------------ Node.swift ----------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class TSCBasic.DiagnosticsEngine

// MARK: - DependencySource
/// Points to the source of dependencies, i.e. the file read to obtain the information.
/*@_spi(Testing)*/
public struct DependencySource: Hashable, CustomStringConvertible {

  public let typedFile: TypedVirtualPath
  /// Keep this for effiencient lookups into the ``ModuleDependencyGraph``
  public let internedFileName: InternedString

  init(typedFile: TypedVirtualPath, internedFileName: InternedString) {
    assert( typedFile.type == .swift ||
            typedFile.type == .swiftModule)
    self.typedFile = typedFile
    self.internedFileName = internedFileName
  }

  public init(_ swiftSourceFile: SwiftSourceFile, _ t: InternedStringTable) {
    let typedFile = swiftSourceFile.typedFile
    self.init(typedFile: typedFile,
              internedFileName: typedFile.file.name.intern(in: t))
  }

  init?(ifAppropriateFor file: VirtualPath.Handle,
        internedString: InternedString) {
    let ext = VirtualPath.lookup(file).extension
    guard let type =
      ext == FileType.swift      .rawValue ? FileType.swift :
      ext == FileType.swiftModule.rawValue ? FileType.swiftModule
      : nil
    else {
      return nil
    }
    self.init(typedFile: TypedVirtualPath(file: file, type: type),
              internedFileName: internedString)
  }

  public var file: VirtualPath { typedFile.file }

  public var description: String {
    typedFile.file.externalDependencyPathDescription
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(internedFileName)
  }
  static public func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.internedFileName == rhs.internedFileName
  }
}

// MARK: - reading
extension DependencySource {
  /// Throws if a read error
  /// Returns nil if no dependency info there.
  public func read(
    info: IncrementalCompilationState.IncrementalDependencyAndInputSetup,
    internedStringTable: InternedStringTable
  ) -> SourceFileDependencyGraph? {
    guard let fileToRead = try? fileToRead(info: info) else {return nil}
    do {
      info.reporter?.report("Reading dependencies from \(description)")
      return try SourceFileDependencyGraph.read(from: fileToRead,
                                                on: info.fileSystem,
                                                internedStringTable: internedStringTable)
    }
    catch {
      let msg = "Could not read \(fileToRead) \(error.localizedDescription)"
      info.reporter?.report(msg, fileToRead)
      return nil
    }
  }

  /// Find the file to actually read the dependencies from
  /// - Parameter info: a bundle of useful information
  /// - Returns: The corresponding swiftdeps file for a swift file, or the swiftmodule file for an incremental imports source.
  public func fileToRead(
    info: IncrementalCompilationState.IncrementalDependencyAndInputSetup
  ) throws -> TypedVirtualPath? {
    typedFile.type != .swift
    ? typedFile
    : try info.outputFileMap.getSwiftDeps(for: typedFile, diagnosticEngine: info.diagnosticEngine)
  }
}


extension OutputFileMap {
  fileprivate func getSwiftDeps(
    for sourceFile: TypedVirtualPath,
    diagnosticEngine: DiagnosticsEngine
  ) throws -> TypedVirtualPath? {
    assert(sourceFile.type == FileType.swift)
    guard let swiftDepsHandle = try existingOutput(inputFile: sourceFile.fileHandle,
                                             outputType: .swiftDeps)
    else {
      // The legacy driver fails silently here.
      diagnosticEngine.emit(
        .remarkDisabled("\(sourceFile.file.basename) has no swiftDeps file")
      )
      return nil
    }
    assert(VirtualPath.lookup(swiftDepsHandle).extension == FileType.swiftDeps.rawValue)
    return TypedVirtualPath(file: swiftDepsHandle, type: .swiftDeps)
  }
}


// MARK: - comparing
extension DependencySource: Comparable {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.file.name < rhs.file.name
  }
}

// MARK: - describing
extension DependencySource {
  /// Answer a single name; for swift modules, the right thing is one level up
  public var shortDescription: String {
    switch typedFile.type {
    case .swiftDeps:
      return file.basename
    case .swiftModule:
      return file.parentDirectory.basename
    default:
      return file.name
    }
  }
}

