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

/// Like a two-way dictionary
///
// FIXME: The current use of this abstraction in the driver is
// fundamentally broken. This data structure should be retired ASAP.
// See the extended FIXME in its use in
// `ModuleDependencyGraph.inputDependencySourceMap`
public struct BidirectionalMap<T1: Hashable, T2: Hashable>: Equatable, Sequence {
  private var map1: [T1: T2] = [:]
  private var map2: [T2: T1] = [:]

  public init() {}

  /// Accesses the value associated with the given key for reading and writing.
  ///
  /// - Parameter key: The key to find in the dictionary.
  /// - Returns: The value associated with key if key is in the bidirectional
  /// map; otherwise, `nil`.
  public subscript(_ key: T1) -> T2? {
    get {
      return self.map1[key]
    }
    set {
      // First, strike any existing mappings.
      if let oldTarget = self.map1.removeValue(forKey: key) {
        self.map2.removeValue(forKey: oldTarget)
      }
      // Then construct the forward mapping (or removal).
      self.map1[key] = newValue
      if let newValue = newValue {
        // And finally, the backwards mapping (or removal).
        self.map2[newValue] = key
      }
    }
  }

  /// Accesses the value associated with the given key for reading and writing.
  ///
  /// - Parameter key: The key to find in the dictionary.
  /// - Returns: The value associated with key if key is in the bidirectional
  /// map; otherwise, `nil`.
  public subscript(_ key: T2) -> T1? {
    get {
      return self.map2[key]
    }
    set {
      // First, strike any existing mappings.
      if let oldSource = self.map2.removeValue(forKey: key) {
        self.map1.removeValue(forKey: oldSource)
      }
      // Then construct the reverse mapping (or removal).
      self.map2[key] = newValue
      if let newValue = newValue {
        // And finally the forwards mapping (or removal).
        self.map1[newValue] = key
      }
    }
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
