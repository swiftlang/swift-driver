//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif
import class Foundation.FileHandle
import class Foundation.FileManager
import class Foundation.JSONEncoder
import class Foundation.NSLock
import struct Foundation.Data
import struct Foundation.URL

import struct TSCBasic.AbsolutePath
import class TSCBasic.DiagnosticsEngine
import struct TSCBasic.FileSystemError

// NOTE: Cribbed from SwiftPM's 'Sources/SwiftBuildSupport/TraceEventsWriter.swift'
// and modified to support writing from multiple threads
@_spi(Testing) public final class TraceEventsWriter: @unchecked Sendable {

  private let lock = NSLock()

  private let fileHandle: FileHandle
  private let encoder: JSONEncoder
  private let diagnosticEngine: DiagnosticsEngine
  private var needsComma: Bool = false
  private var isClosed: Bool = false

  public init(path: AbsolutePath, diagnosticEngine: DiagnosticsEngine) throws {
    #if os(Windows)
    if !FileManager.default.fileExists(atPath: path.pathString) {
      FileManager.default.createFile(atPath: path.pathString, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path.pathString))
    try handle.truncate(atOffset: 0)
    #else
    // Close-on-exec: child processes the driver starts must not inherit an
    // open file.
    let fd = open(path.pathString, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o644)
    guard fd >= 0 else {
      throw TSCBasic.FileSystemError(errno: errno, path)
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    #endif
    try handle.write(contentsOf: Data("[\n".utf8))
    self.fileHandle = handle
    self.diagnosticEngine = diagnosticEngine
    let encoder = JSONEncoder()
    #if os(Linux) || os(Android)
    encoder.outputFormatting = [.sortedKeys]
    #else
    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    } else {
      encoder.outputFormatting = [.sortedKeys]
    }
    #endif
    self.encoder = encoder
  }

  /// Immediately write an event to the file
  public func write(_ event: TraceEvent) {
    let failure: Error? = lock.withLock { () -> Error? in
      guard !isClosed, let data = try? encoder.encode(event) else { return nil }

      var bytes = needsComma ? Data(",\n".utf8) : Data()
      bytes.append(data)
      do {
        try fileHandle.write(contentsOf: bytes)
      } catch {
        // Give up and let the client know
        isClosed = true
        try? fileHandle.close()
        return error
      }
      needsComma = true
      return nil
    }
    if let failure {
      diagnosticEngine.emit(
        .warning("could not write the trace events file; tracing disabled: \(failure.localizedDescription)"))
    }
  }

  public func close() {
    lock.withLock {
      guard !isClosed else { return }
      isClosed = true
      try? fileHandle.write(contentsOf: Data("\n]\n".utf8))
      try? fileHandle.close()
    }
  }

  /// Trace file descriptor
  ///
  /// - Note: Exposed for testing.
  public var fileDescriptor: Int32 { fileHandle.fileDescriptor }
}
