//===--------------- FileType.swift - Swift File Types --------------------===//
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

/// Describes the kinds of files that the driver understands.
///
/// The raw values for these enumerations describe the default extension for]
/// the file type.
public enum FileType: String, Hashable, CaseIterable, Codable {
  /// Swift source file.
  case swift

  /// (Canonical) SIL source file
  case sil

  /// (Canonical) SIB files
  case sib

  /// AST dump
  case ast

  /// An executable image.
  case image = "out"

  /// An object file.
  case object = "o"

  /// A dSYM directory.
  case dSYM

  /// A file containing make-style dependencies.
  case dependencies = "d"

  /// An autolink input file
  case autolink

  /// A compiled Swift module file.
  case swiftModule = "swiftmodule"

  /// Swift documentation for amodule.
  case swiftDocumentation = "swiftdoc"

  /// A textual Swift interface file.
  case swiftInterface = "swiftinterface"

  /// Assembler source.
  case assembly = "s"

  /// Raw SIL source file
  case raw_sil

  /// Raw sib file
  case raw_sib

  /// LLVM IR file
  case llvmIR = "ll"

  /// LLVM bitcode
  case llvmBitcode = "bc"

  /// Clang/Swift serialized diagnostics
  case diagnostics = "dia"

  /// Objective-C header
  case objcHeader = "h"

  /// Swift dependencies file.
  case swiftDeps = "swiftdeps"

  /// Remapping file
  case remap

  /// Imported modules.
  case importedModules = "importedmodules"

  /// Text-based dylib (TBD) file.
  case tbd

  /// Module trace file.
  ///
  /// Module traces are used by Apple's internal build infrastructure. Apple
  /// engineers can see more details on the "Swift module traces" page in the
  /// Swift section of the internal wiki.
  case moduleTrace = "trace.json"

  /// Indexing data directory.
  ///
  /// The extension isn't real.
  case indexData

  /// Optimization record.
  case optimizationRecord = "opt.yaml"

  /// Clang compiler module file
  case pcm

  /// Clang precompiled header
  case pch
}

extension FileType: CustomStringConvertible {
  public var description: String {
    switch self {
    case .swift, .sil, .sib, .image, .object, .dSYM, .dependencies, .autolink,
         .swiftModule, .swiftDocumentation, .swiftInterface, .assembly,
         .remap, .tbd, .pcm, .pch:
      return rawValue

    case .ast:
      return "ast-dump"

    case .raw_sil:
      return "raw-sil"

    case .raw_sib:
      return "raw-sib"

    case .llvmIR:
      return "llvm-ir"

    case .llvmBitcode:
      return "llvm-bc"

    case .objcHeader:
      return "objc-header"

    case .swiftDeps:
      return "swift-dependencies"

    case .importedModules:
      return "imported-modules"

    case .moduleTrace:
      return "module-trace"

    case .indexData:
      return "index-data"

    case .optimizationRecord:
      return "opt-record"

    case .diagnostics:
      return "diagnostics"
    }
  }
}

extension FileType {
  /// Whether a file of this type is an input to a Swift compilation, such as
  /// a Swift or SIL source file.
  public var isPartOfSwiftCompilation: Bool {
    switch self {
    case .swift, .raw_sil, .sil, .raw_sib, .sib:
      return true
    case .object, .pch, .ast, .llvmIR, .llvmBitcode, .assembly, .swiftModule,
         .importedModules, .indexData, .remap, .dSYM, .autolink, .dependencies,
         .swiftDocumentation, .pcm, .diagnostics, .objcHeader, .image,
         .swiftDeps, .moduleTrace, .tbd, .optimizationRecord, .swiftInterface:
      return false
    }
  }
}
