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
public struct BidirectionalMap<T1: Hashable, T2: Hashable>: Equatable {
  private var map1: [T1: T2] = [:]
  private var map2: [T2: T1] = [:]

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
}
