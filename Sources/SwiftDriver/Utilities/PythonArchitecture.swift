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

/// Check that the architecture of the toolchain matches the architecture
/// of the Python installation.
///
/// When installing the x86 toolchain on ARM64 Windows, if the user does not
/// install an x86 version of Python, they will get acryptic error message
/// when running lldb (`0xC000007B`). Calling this function before invoking
/// lldb gives them a warning to help troublshoot the issue.
///
/// - Parameters:
///   - cwd: The current working directory.
///   - env: A dictionary of the environment variables and their values. Usually of the parent shell.
///   - diagnosticsEngine: DiagnosticsEngine instance to use for printing the warning.
public func checkIfMatchingPythonArch(
  cwd: AbsolutePath?, envBlock: ProcessEnvironmentBlock, diagnosticsEngine: DiagnosticsEngine
) {
  #if arch(arm64)
    let toolchainArchitecture = COFFBinaryExecutableArchitecture.arm64
  #elseif arch(x86_64)
    let toolchainArchitecture = COFFBinaryExecutableArchitecture.x64
  #elseif arch(x86)
    let toolchainArchitecture = COFFBinaryExecutableArchitecture.x86
  #else
    return
  #endif
  let pythonArchitecture = COFFBinaryExecutableArchitecture.readWindowsExecutableArchitecture(
    cwd: cwd, envBlock: envBlock, filename: "python.exe")

  if toolchainArchitecture != pythonArchitecture {
    diagnosticsEngine.emit(
      .warning(
        """
        There is an architecture mismatch between the installed toolchain and the resolved Python's architecture:
        Toolchain: \(toolchainArchitecture)
        Python: \(pythonArchitecture)
        """))
  }
}

/// Some of the architectures that can be stored in a COFF header.
enum COFFBinaryExecutableArchitecture: String {
  case x86 = "X86"
  case x64 = "X64"
  case arm64 = "ARM64"
  case unknown = "Unknown"

  static func fromPEMachineByte(machine: UInt16) -> Self {
    // https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#machine-types
    switch machine {
    case 0x014c: return .x86
    case 0x8664: return .x64
    case 0xAA64: return .arm64
    default: return .unknown
    }
  }

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
  ) -> Self {
    let searchPaths = getEnvSearchPaths(pathString: envBlock["Path"], currentWorkingDirectory: cwd)
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
    fileHandle.seek(toFileOffset: 0x3C)
    guard let offsetPointer = try? fileHandle.read(upToCount: 4),
      offsetPointer.count == 4
    else {
      return .unknown
    }

    let peHeaderOffset = offsetPointer.withUnsafeBytes { $0.load(as: UInt32.self) }

    fileHandle.seek(toFileOffset: UInt64(peHeaderOffset))
    guard let coffHeader = try? fileHandle.read(upToCount: 6), coffHeader.count == 6 else {
      return .unknown
    }

    let signature = coffHeader.prefix(4)
    let machineBytes = coffHeader.suffix(2)

    guard signature == Data([0x50, 0x45, 0x00, 0x00]) else {
      return .unknown
    }

    return .fromPEMachineByte(machine: machineBytes.withUnsafeBytes { $0.load(as: UInt16.self) })
  }
}
