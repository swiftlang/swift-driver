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

public struct InternedString: Hashable, Comparable, CustomStringConvertible {
  let index: Int
  let table: InternedStringTable
  
  fileprivate init(_ s: String, host: ModuleDependencyGraph) {
    let t = host.internedStringTable
    self.init(index: s.isEmpty ? 0 : t.index(s),
              table: t)
  }
  
  public var isEmpty: Bool { index == 0 }
  
  // PRIVATE?
  init(index: Int, table: InternedStringTable) {
    self.index = index
    self.table = table
  }
  
  public var string: String { table.string(index) }
    
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    assert(lhs.table === rhs.table)
    return lhs.index == rhs.index
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(index)
  }
  public static func <(lhs: Self, rhs: Self) -> Bool {
    assert(lhs.table === rhs.table)
    return lhs.string < rhs.string
  }
    
  public var description: String { string }
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
  func intern(_ g: ModuleDependencyGraph) -> InternedString {
    InternedString(String(self), host: g)
  }
}
