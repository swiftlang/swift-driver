//===------------------ BidirectionalMap.swift ----------------------------===//
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

/// Like a two-way dictionary, only works for accessing present members
public struct BidirectionalMap<T1: Hashable, T2: Hashable>: Equatable, Sequence {
  private var map1: [T1: T2] = [:]
  private var map2: [T2: T1] = [:]

  public init() {}

  public subscript(_ key: T1) -> T2 {
    get {
      guard let value = map1[key]
      else {
        fatalError("\(key) was not present")
      }
      return value
    }
    set {
      map1[key] = newValue
      map2[newValue] = key
    }
  }
  public subscript(_ key: T2) -> T1 {
    get {
      guard let value = map2[key]
      else {
        fatalError("\(key) was not present")
      }
      return value
    }
    set { self[newValue] = key }
  }
  public func contains(key: T1) -> Bool {
    map1.keys.contains(key)
  }
  public func contains(key: T2) -> Bool {
    map2.keys.contains(key)
  }
  public mutating func removeValue(forKey t1: T1) {
    if let t2 = map1[t1] {
      map2.removeValue(forKey: t2)
    }
    map1.removeValue(forKey: t1)
  }
  public mutating func removeValue(forKey t2: T2) {
    if let t1 = map2[t2] {
      map1.removeValue(forKey: t1)
    }
    map2.removeValue(forKey: t2)
  }
  public func makeIterator() -> Dictionary<T1, T2>.Iterator {
    map1.makeIterator()
  }
}
