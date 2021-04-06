//===-------- TemporaryFileMatch.swift - Driver Testing Extensions --------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic
import SwiftDriver


public func matchTemporary(_ path: VirtualPath, basename: String, fileExtension: String?) -> Bool {
  let relativePath: RelativePath
  switch path {
    case .temporary(let tempPath):
      relativePath = tempPath
    case .temporaryWithKnownContents(let tempPath, _):
      relativePath = tempPath
    default:
      return false
  }
  return relativePath.basenameWithoutExt.hasPrefix(basename) &&
         fileExtension == relativePath.extension
}

public func matchTemporary(_ path: VirtualPath, _ filename: String) -> Bool {
  let components = filename.components(separatedBy: ".")
  if components.count == 1 {
    return matchTemporary(path, basename: filename, fileExtension: nil)
  } else if components.count == 2 {
    return matchTemporary(path, basename: components[0], fileExtension: components[1])
  } else {
    let basename = components[0 ..< components.count - 1].joined()
    return matchTemporary(path, basename: basename, fileExtension: components.last)
  }
}

public func commandContainsFlagTemporaryPathSequence(_ cmd: [Job.ArgTemplate],
                                                     flag: Job.ArgTemplate,
                                                     filename: String)
-> Bool {
  for (index, element) in cmd.enumerated() {
    if element == flag,
       (index + 1) < cmd.count {
      guard case .path(let relativePath) = cmd[index + 1] else {
        continue
      }
      if matchTemporary(relativePath, filename) {
        return true
      }
    }
  }
  return false
}

public func commandContainsTemporaryPath(_ cmd: [Job.ArgTemplate],
                                         _ filename: String)
-> Bool {
  return cmd.contains {
    guard case .path(let path) = $0 else { return false }
    return matchTemporary(path, filename)
  }
}

public func commandContainsTemporaryResponsePath(_ cmd: [Job.ArgTemplate],
                                                 _ filename: String)
-> Bool {
  return cmd.contains {
    guard case .responseFilePath(let path) = $0 else { return false }
    return matchTemporary(path, filename)
  }
}

