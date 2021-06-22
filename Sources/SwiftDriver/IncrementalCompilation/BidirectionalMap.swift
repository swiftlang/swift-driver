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

/// Provides a bidirectional mapping between two keys.
///
/// `BidirectionalMap` provides efficient O(1) lookups in both directions.
public struct BidirectionalMap<T1: Hashable, T2: Hashable>: Equatable {
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
}

extension BidirectionalMap {
  /// Updates the value stored in the bidirectional map for the given key,
  /// or adds a new set of key-value pairs if the key have an entry in the map.
  ///
  /// If access to the old value is not necessary, it is more efficient to use
  /// the subscript operator to perform an in-place update.
  ///
  /// - Parameters:
  ///   - v: The new value to add to the two-level map.
  ///   - key: The two-level key to associate with value.
  /// - Returns: The value that was replaced, or `nil` if a new key-value pair was added.
  @discardableResult
  public mutating func updateValue(_ newValue: T2, forKey key: T1) -> T2? {
    let old = self[key]
    self[key] = newValue
    return old
  }

  /// Updates the value stored in the bidirectional map for the given key,
  /// or adds a new set of key-value pairs if the key have an entry in the map.
  ///
  /// If access to the old value is not necessary, it is more efficient to use
  /// the subscript operator to perform an in-place update.
  ///
  /// - Parameters:
  ///   - v: The new value to add to the two-level map.
  ///   - key: The two-level key to associate with value.
  /// - Returns: The value that was replaced, or `nil` if a new key-value pair was added.
  @discardableResult
  public mutating func updateValue(_ newValue: T1, forKey key: T2) -> T1? {
    let old = self[key]
    self[key] = newValue
    return old
  }
}

extension BidirectionalMap: Sequence {
  /// Provides an iterator that yields pairs of the key-to-key mappings.
  ///
  /// - Warning: The order of the returned mappings is not stable. In general,
  ///            avoid iterating over a bidirectional map unless order does not
  ///            matter for the algorithm in question.
  ///
  /// - Returns: An iterator value for this bidirectional map.
  public func makeIterator() -> Dictionary<T1, T2>.Iterator {
    self.map1.makeIterator()
  }
}
