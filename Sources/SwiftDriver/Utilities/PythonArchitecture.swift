//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import Foundation

import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import struct TSCBasic.Diagnostic
import protocol TSCBasic.DiagnosticData
import class TSCBasic.DiagnosticsEngine
import protocol TSCBasic.FileSystem
import protocol TSCBasic.OutputByteStream
import typealias TSCBasic.ProcessEnvironmentBlock
import func TSCBasic.getEnvSearchPaths
import func TSCBasic.lookupExecutablePath

#if os(Windows)
  import WinSDK
#endif

/// Check that the architecture of the toolchain matches the architecture
/// of the Python installation.
///
/// When installing the x86 toolchain on ARM64 Windows, if the user does not
/// install an x86 version of Python, they will get a cryptic error message
/// when running lldb (`0xC000007B`). Calling this function before invoking
/// lldb gives them a warning to help troubleshoot the issue.
///
/// - Parameters:
///   - cwd: The current working directory.
///   - env: The parent shell's ProcessEnvironmentBlock.
///   - diagnosticsEngine: DiagnosticsEngine instance to use for printing the warning.
public func checkIfMatchingPythonArch(
  cwd: AbsolutePath?, envBlock: ProcessEnvironmentBlock,
  toolchainArchitecture: ExecutableArchitecture, diagnosticsEngine: DiagnosticsEngine
) {
  #if os(Windows) || os(macOS)
    #if os(Windows)
      let pythonArchitecture = Process.readWindowsExecutableArchitecture(
        cwd: cwd, envBlock: envBlock, filename: "python.exe")
    #elseif os(macOS)
      let pythonArchitecture = Process.readDarwinExecutableArchitecture(
        cwd: cwd, envBlock: envBlock, filename: "python3")
      if pythonArchitecture == .universal {
        return
      }
    #endif

    guard toolchainArchitecture == pythonArchitecture else {
      diagnosticsEngine.emit(
        .warning(
          """
          There is an architecture mismatch between the installed toolchain and the resolved Python's architecture:
          Toolchain: \(toolchainArchitecture)
          Python: \(pythonArchitecture)
          """))
      return
    }
  #endif
}

/// Some of the architectures that can be stored in a COFF header.
public enum ExecutableArchitecture: String {
  case x86 = "X86"
  case x64 = "X64"
  case arm64 = "ARM64"
  case universal = "Universal"
  case unknown = "Unknown"

  #if os(Windows)
    static func fromPEMachineByte(machine: Int32) -> Self {
      // https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#machine-types
      switch machine {
      case IMAGE_FILE_MACHINE_I386: return .x86
      case IMAGE_FILE_MACHINE_AMD64: return .x64
      case IMAGE_FILE_MACHINE_ARM64: return .arm64
      default: return .unknown
      }
    }
  #endif

  #if os(macOS)
    static func fromMachoCPUType(cpuType: Int32) -> Self {
      // https://en.wikipedia.org/wiki/Mach-O
      switch cpuType {
      case 0x0100_0007: return .x86
      case 0x0100_000c: return .arm64
      default: return .unknown
      }
    }
  #endif
}

#if os(Windows)
extension Process {
  /// Resolves the filename from the `Path` environment variable and read its COFF header to determine the architecture
  /// of the binary.
  ///
  /// - Parameters:
  ///   - cwd: The current working directory.
  ///   - env: A dictionary of the environment variables and their values. Usually of the parent shell.
  ///   - filename: The name of the file we are resolving the architecture of.
  /// - Returns: The architecture of the file which was found in the `Path`.
  static func readWindowsExecutableArchitecture(
    cwd: AbsolutePath?, envBlock: ProcessEnvironmentBlock, filename: String
  ) -> ExecutableArchitecture {
    let searchPaths = getEnvSearchPaths(
      pathString: envBlock["Path"], currentWorkingDirectory: cwd)
    guard
      let filePath = lookupExecutablePath(
        filename: filename, currentWorkingDirectory: cwd, searchPaths: searchPaths)
    else {
      return .unknown
    }
    guard let fileHandle = FileHandle(forReadingAtPath: filePath.pathString) else {
      return .unknown
    }

    defer { fileHandle.closeFile() }

    // Infering the architecture of a Windows executable from its COFF header involves the following:
    // 1. Get the COFF header offset from the pointer located at the 0x3C offset (4 bytes long).
    // 2. Jump to that offset and read the next 6 bytes.
    // 3. The first 4 are the signature which should be equal to 0x50450000.
    // 4. The last 2 are the machine architecture which can be infered from the value we get.
    //
    // The link below provides a visualization of the COFF header and the process to get to it.
    // https://upload.wikimedia.org/wikipedia/commons/1/1b/Portable_Executable_32_bit_Structure_in_SVG_fixed.svg
    guard (try? fileHandle.seek(toOffset: 0x3C)) != nil else {
      return .unknown
    }
    guard let offsetPointer = try? fileHandle.read(upToCount: 4),
      offsetPointer.count == 4
    else {
      return .unknown
    }

    let peHeaderOffset = offsetPointer.withUnsafeBytes { $0.load(as: UInt32.self) }

    guard (try? fileHandle.seek(toOffset: UInt64(peHeaderOffset))) != nil else {
      return .unknown
    }
    guard let coffHeader = try? fileHandle.read(upToCount: 6), coffHeader.count == 6 else {
      return .unknown
    }

    let signature = coffHeader.prefix(4)
    let machineBytes = coffHeader.suffix(2)

    guard signature == Data([0x50, 0x45, 0x00, 0x00]) else {
      return .unknown
    }

    let machine = machineBytes.withUnsafeBytes { $0.load(as: UInt16.self) }
    return .fromPEMachineByte(machine: Int32(machine))
  }
}
#endif

#if os(macOS)
extension Process {
  static func readDarwinExecutableArchitecture(
    cwd: AbsolutePath?, envBlock: ProcessEnvironmentBlock, filename: String
  ) -> ExecutableArchitecture {
    let magicNumber: UInt32 = 0xcafe_babe

    let searchPaths = getEnvSearchPaths(
      pathString: envBlock["PATH"], currentWorkingDirectory: cwd)
    guard
      let filePath = lookupExecutablePath(
        filename: filename, currentWorkingDirectory: cwd, searchPaths: searchPaths)
    else {
      return .unknown
    }
    guard let fileHandle = FileHandle(forReadingAtPath: filePath.pathString) else {
      return .unknown
    }

    defer {
      try? fileHandle.close()
    }

    // The first 4 bytes of a Mach-O header contain the magic number. We use it to determine if the binary is
    // universal.
    // https://github.com/apple/darwin-xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
    let magicData = fileHandle.readData(ofLength: 4)
    let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

    if magic == magicNumber {
      return .universal
    }

    // If the binary is not universal, the next 4 bytes contain the CPU type.
    guard (try? fileHandle.seek(toOffset: 4)) != nil else {
      return .unknown
    }
    let cpuTypeData = fileHandle.readData(ofLength: 4)
    let cpuType = cpuTypeData.withUnsafeBytes { $0.load(as: Int32.self) }
    return .fromMachoCPUType(cpuType: cpuType)
  }
}
#endif
