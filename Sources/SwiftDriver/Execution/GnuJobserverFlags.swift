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

import typealias TSCBasic.ProcessEnvironmentBlock

/// Reading and rewriting the GNU make jobserver advertisement in `MAKEFLAGS`.
public enum GnuJobserverFlags {
  /// GNU make 4.2 renamed `--jobserver-fds` to `--jobserver-auth`; the old
  /// spelling is still what make 3.81 (macOS's `/usr/bin/make`) emits, so both
  /// are accepted.
  private static let authenticationPrefixes = ["--jobserver-auth=", "--jobserver-fds="]

  /// Extracts the jobserver authentication string from the value of
  /// `MAKEFLAGS`, or returns `nil` if it does not advertise a pool. The last
  /// occurrence wins.
  public static func parseAuthentication(from makeFlags: String) -> String? {
    var authentication: String? = nil
    for word in words(in: makeFlags) {
      if let prefix = authenticationPrefix(of: word) {
        authentication = unescaped(word.dropFirst(prefix.count))
      }
    }
    return authentication
  }

  /// Returns `env` with the jobserver authentication stripped from `MAKEFLAGS`,
  /// leaving the rest of the value intact.
  ///
  /// The compiler frontends we launch are not jobserver clients -- their copies
  /// of the pool descriptors are closed on exec -- so advertising the pool to
  /// them would only invite a stray client to drain it. This mirrors how make
  /// omits the pool from a recipe it does not treat as recursive.
  public static func censoringAuthentication(in env: ProcessEnvironmentBlock) -> ProcessEnvironmentBlock {
    guard let makeFlags = env["MAKEFLAGS"] else { return env }
    let kept = words(in: makeFlags).filter { authenticationPrefix(of: $0) == nil }
    var censored = env
    censored["MAKEFLAGS"] = kept.isEmpty ? nil : kept.joined(separator: " ")
    return censored
  }

  private static func authenticationPrefix(of word: Substring) -> String? {
    authenticationPrefixes.first { word.hasPrefix($0) }
  }

  /// Splits `MAKEFLAGS` on spaces, except those make escaped with a backslash
  /// (e.g. in a FIFO path). Words keep their escapes, so they can be rejoined
  /// verbatim.
  private static func words(in makeFlags: String) -> [Substring] {
    var words: [Substring] = []
    var wordStart = makeFlags.startIndex
    var isEscaped = false
    for index in makeFlags.indices {
      let character = makeFlags[index]
      if isEscaped {
        isEscaped = false
      } else if character == "\\" {
        isEscaped = true
      } else if character == " " {
        if wordStart < index {
          words.append(makeFlags[wordStart..<index])
        }
        wordStart = makeFlags.index(after: index)
      }
    }
    if wordStart < makeFlags.endIndex {
      words.append(makeFlags[wordStart...])
    }
    return words
  }

  /// Removes make's backslash escapes from a word of `MAKEFLAGS`.
  private static func unescaped(_ word: Substring) -> String {
    var result = ""
    var isEscaped = false
    for character in word {
      if !isEscaped && character == "\\" {
        isEscaped = true
        continue
      }
      isEscaped = false
      result.append(character)
    }
    return result
  }
}
