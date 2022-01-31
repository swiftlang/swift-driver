//===--------------- LinkKind.swift - Swift Linking Kind ------------------===//
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

/// Describes the kind of linker output we expect to produce.
public enum LinkOutputType {
  /// An executable file.
  case executable

  /// A shared library (e.g., .dylib or .so)
  case dynamicLibrary

  /// A static library (e.g., .a or .lib)
  case staticLibrary
}

/// Describes the kind of link-time-optimization we expect to perform.
public enum LTOKind: String, Hashable, CaseIterable {
  /// Perform LLVM ThinLTO.
  case llvmThin = "llvm-thin"
  /// Perform LLVM full LTO.
  case llvmFull = "llvm-full"
}
