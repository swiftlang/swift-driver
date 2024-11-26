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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

func argumentNeedsQuoting(_ argument: String) -> Bool {
  if argument.isEmpty { return false }
  let chars: Set<Character> = Set("\t \"&'()*<>\\`^|\n")
  return argument.firstIndex(where: { chars.contains($0) }) != argument.endIndex
}

func quoteArgument(_ argument: String) -> String {
#if os(Windows)
  var unquoted: Substring = argument[...]
  var quoted: String = "\""
  while !unquoted.isEmpty {
    guard let firstNonBS = unquoted.firstIndex(where: { $0 != "\\" }) else {
      // The rest of the string is backslashes. Escape all of them and exit.
      (0 ..< (2 * unquoted.count)).forEach { _ in quoted += "\\" }
      break
    }

    let bsCount = unquoted.distance(from: unquoted.startIndex, to: firstNonBS)
    if unquoted[firstNonBS] == "\"" {
      // This is an embedded quote. Escape all preceding backslashes, then
      // add one additional backslash to escape the quote.
      (0 ..< (2 * bsCount + 1)).forEach { _ in quoted += "\\" }
      quoted += "\""
    } else {
      // This is just a normal character. Don't escape any of the preceding
      // backslashes, just append them as they are and then append the
      // character.
      (0 ..< bsCount).forEach { _ in quoted += "\\" }
      quoted += "\(unquoted[firstNonBS])"
    }

    unquoted = unquoted.dropFirst(bsCount + 1)
  }
  return quoted + "\""
#else
  return "'" + argument + "'"
#endif
}

#if canImport(Darwin) || os(Linux) || os(Android) || os(OpenBSD) || os(FreeBSD)
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
#elseif os(Windows)
func commandLineFitsWithinSystemLimits(path: String, args: [String]) -> Bool {
  func flattenWindowsCommandLine(_ arguments: [String]) -> String {
    var quoted: String = ""
    for arg in arguments {
      if argumentNeedsQuoting(arg) {
        quoted += quoteArgument(arg)
      } else {
        quoted += arg
      }
      quoted += " "
    }
    return quoted
  }

  let arguments: [String] = [path] + args
  let commandLine = flattenWindowsCommandLine(arguments)
  // `CreateProcessW` requires the length of `lpCommandLine` not exceed 32767
  // characters, including the Unicode terminating null character.  We use a
  // smaller value to reduce risk of getting invalid command line due to
  // unaccounted factors.
  return commandLine.count <= 32000
}
#else
func commandLineFitsWithinSystemLimits(path: String, args: [String]) -> Bool {
  #warning("missing implementation for current platform")
  return true
}
#endif
