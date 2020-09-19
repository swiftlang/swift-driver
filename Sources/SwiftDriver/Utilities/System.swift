//===------------ System.swift - Swift Driver System Utilities ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(macOS)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(macOS) || os(Linux) || os(Android)
// Adapted from llvm::sys::commandLineFitsWithinSystemLimits.
func commandLineFitsWithinSystemLimits(path: String, args: [String]) -> Bool {
  let upperBound = sysconf(Int32(_SC_ARG_MAX))
  guard upperBound != -1 else {
    // The system reports no limit.
    return true
  }
  // The lower bound for ARG_MAX on a POSIX system
  let lowerBound = Int(_POSIX_ARG_MAX)
  // This the same baseline used by xargs.
  let baseline = 128 * 1024

  var effectiveArgMax = max(min(baseline, upperBound), lowerBound)
  // Conservatively assume environment variables consume half the space.
  effectiveArgMax /= 2

  var commandLineLength = path.utf8.count + 1
  for arg in args {
    #if os(Linux) || os(Android)
      // Linux limits the length of each individual argument to MAX_ARG_STRLEN.
      // There is no available constant, so it is hardcoded here.
      guard arg.utf8.count < 32 * 4096 else {
        return false
      }
    #endif
    commandLineLength += arg.utf8.count + 1
  }
  return commandLineLength < effectiveArgMax
}
#else
func commandLineFitsWithinSystemLimits(path: String, args: [String]) -> Bool {
  #warning("missing implementation for current platform")
  return true
}
#endif

struct Microseconds {
  var value: UInt64
  private static let usecPerSec: UInt64 = 1_000_000

  static func +(lhs: Microseconds, rhs: Microseconds) -> Microseconds {
    .init(value: lhs.value + rhs.value)
  }

  static func -(lhs: Microseconds, rhs: Microseconds) -> Microseconds {
    .init(value: lhs.value - rhs.value)
  }

  init(value: UInt64) {
    self.value = value
  }

  #if os(macOS) || os(Linux)
  init(timeVal: timeval) {
    value = Self.usecPerSec * UInt64(timeVal.tv_sec) + UInt64(timeVal.tv_usec)
  }
  #endif

  var seconds: Double {
    Double(value) / 1_000_000
  }
}

struct TimeValues {
  let userTime: Microseconds
  let systemTime: Microseconds
  let wallTime: Microseconds
}

#if os(macOS) || os(Linux)
func currentTimeValues() -> TimeValues? {
  var resourceUsage: rusage = .init()
  #if os(macOS)
  guard getrusage(RUSAGE_SELF, &resourceUsage) == 0 else { return nil }
  #else
  guard getrusage(RUSAGE_SELF.rawValue, &resourceUsage) == 0 else { return nil }
  #endif
  
  var wallTimeVal: timeval = .init()
  guard gettimeofday(&wallTimeVal, nil) == 0 else { return nil }

  let userTime = Microseconds(timeVal: resourceUsage.ru_utime)
  let systemTime = Microseconds(timeVal: resourceUsage.ru_stime)
  let wallTime = Microseconds(timeVal: wallTimeVal)

  return .init(userTime: userTime, systemTime: systemTime, wallTime: wallTime)
}
#else
func currentTimeValues() -> TimeValues? {
  #warning("missing implementation for current platform")
  return nil
}
#endif
