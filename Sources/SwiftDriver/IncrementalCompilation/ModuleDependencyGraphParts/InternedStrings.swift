//===------------------ InteredStrings.swift ------------------------------===//
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

import Foundation

public struct InternedString: CustomStringConvertible, Equatable, Hashable {
  
  let index: Int
  
  fileprivate init(_ s: String, _ table: InternedStringTable) {
    self.init(index: s.isEmpty ? 0 : table.index(s))
  }
  
  public var isEmpty: Bool { index == 0 }
  
  // PRIVATE?
  init(index: Int) {
    self.index = index
  }
  
  public func string(`in` table: InternedStringTable) -> String {
    table.string(index)
  }
  
  public var description: String { "<<\(index)>>" }
}

extension InternedString: Comparable {
  public static func < (lhs: InternedString, rhs: InternedString) -> Bool {
    lhs.index < rhs.index
  }
}

/// Hardcode empty as 0
public class InternedStringTable {
  var strings = [""]
  private var indices = ["": 0]
  
  public init() {}
  
  fileprivate func index(_ s: String) -> Int {
    if let i = indices[s] { return i }
    let i = strings.count
    strings.append(s)
    indices[s] = i
    return i
  }
  
  fileprivate func string(_ i: Int) -> String {
    strings[i]
  }
  
  var endIndex: Int { strings.count }
}

public extension StringProtocol {
  func intern(in t: InternedStringTable) -> InternedString {
    InternedString(String(self), t)
  }
}
