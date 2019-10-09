//===--------------- Sanitizer.swift - Swift Sanitizers -------------------===//
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

/// Defines a sanitizer that can be used to instrument the resulting product of
/// this build.
public enum Sanitizer: String, Hashable {
  /// Address sanitizer (ASan)
  case address

  /// Thread sanitizer (TSan)
  case thread

  /// Undefined behavior sanitizer (UBSan)
  case undefinedBehavior = "undefined"

  /// libFuzzer integration
  /// - Note: libFuzzer is technically not a sanitizer, but
  ///         it's distributed exactly the same as the sanitizers.
  case fuzzer

  /// The name inside the `compiler_rt` library path (e.g. libclang_rt.{name}.a)
  var libraryName: String {
    switch self {
    case .address: return "asan"
    case .thread: return "tsan"
    case .undefinedBehavior: return "ubsan"
    case .fuzzer: return "fuzzer"
    }
  }
}

extension Sanitizer {
  /// The boundaries at which to place certain coverage instrumentation.
  public enum CoverageType: Hashable {
    /// Instrumentation will be placed once, in the entry block of each
    /// function.
    case function

    /// Instrumentation will be placed at the beginning of each basic block in
    /// each function.
    case basicBlock

    /// Instrumentation will be placed at each edge between each basic block
    /// in each function.
    case edge
  }

  public struct CoverageOptions {
    /// Defines the possible ways to customize code coverage instrumentation.
    public struct Flags: OptionSet {
      public let rawValue: UInt8

      /// Instruments the binary with calls to
      /// `__sanitizer_cov_trace_pc_indirect` at every indirect call.
      public static let indirectCalls = Flags(rawValue: 1 << 0)

      /// Currently unused by LLVM
      /// (see llvm/lib/Transforms/SanitizerCoverage.cpp)
      public static let traceBasicBlock = Flags(rawValue: 1 << 1)

      /// Instruments the binary with calls to
      /// `__sanitizer_cov_trace_cmp{N}` at every comparison instruction.
      public static let traceComparisons = Flags(rawValue: 1 << 2)

      /// Currently unused by LLVM
      /// (see llvm/lib/Transforms/SanitizerCoverage.cpp)
      public static let use8BitCounters = Flags(rawValue: 1 << 3)

      /// Instruments the binary with calls to `__sanitizer_cov_trace_pc` at
      /// the boundary specified in the `CoverageType`.
      public static let traceProgramCounter = Flags(rawValue: 1 << 4)

      /// Instruments the binary with calls to `__sanitizer_cov_trace_pc_guard`
      /// the boundary specified in the `CoverageType`, introducing a new
      /// guard variable for each boundary specified in the `CoverageType`.
      public static let traceProgramCounterGuard = Flags(rawValue: 1 << 5)

      /// Creates a set of `Flags` from the provided raw value.
      public init(rawValue: UInt8) {
        self.rawValue = rawValue
      }
    }

    /// The boundary at which to place certain instrumentation calls or guard
    /// variables.
    public var coverageType: CoverageType

    /// The set of flags that control sanitizer instrumentation.
    public var flags: Flags
  }
}
