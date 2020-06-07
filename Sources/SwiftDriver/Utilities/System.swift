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
