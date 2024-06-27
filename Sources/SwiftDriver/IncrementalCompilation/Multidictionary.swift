//===------------------------- Multidictionary.swift ----------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A collection that associates keys with one or more values.
@_spi(Testing) public struct Multidictionary<Key: Hashable, Value: Hashable>: Collection, Equatable {
  private var forwardDictionary: Dictionary<Key, Set<Value>> = [:]

  /// Reverse index used to make value removal more efficient.
  private var reverseIndex: Dictionary<Value, Set<Key>> = [:]

  public typealias Element = (Key, Set<Value>)
  public typealias Index = Dictionary<Key, Set<Value>>.Index

  public init() {}

  /// The number of key-value pairs in this multi-dictionary.
  public var count: Int {
    self.forwardDictionary.count
  }

  /// The position of the first element in a nonempty multi-dictionary.
  public var startIndex: Index {
    self.forwardDictionary.startIndex
  }

  /// The collection’s “past the end” position—that is, the position one greater
  /// than the last valid subscript argument.
  public var endIndex: Index {
    self.forwardDictionary.endIndex
  }

  /// Returns the index for the given key.
  ///
  /// - Parameter key: The key to find in the multi-dictionary.
  /// - Returns: The index for key and its associated value if key is in the
  ///            multi-dictionary; otherwise, nil.
  public func index(forKey key: Key) -> Dictionary<Key, Set<Value>>.Index? {
    self.forwardDictionary.index(forKey: key)
  }

  /// Computes the position immediately after the given index.
  ///
  /// - Parameter i: A valid index of the collection. i must be less than endIndex.
  /// - Returns: The position immediately after the given index.
  @_spi(Testing) public func index(after i: Dictionary<Key, Set<Value>>.Index) -> Dictionary<Key, Set<Value>>.Index {
    self.forwardDictionary.index(after: i)
  }

  @_spi(Testing) public subscript(position: Dictionary<Key, Set<Value>>.Index) -> (Key, Set<Value>) {
    self.forwardDictionary[position]
  }

  /// A collection containing just the keys of this multi-dictionary.
  public var keys: Dictionary<Key, Set<Value>>.Keys {
    return self.forwardDictionary.keys
  }

  /// A collection containing just the values of this multi-dictionary.
  public var values: Dictionary<Key, Set<Value>>.Values {
    return self.forwardDictionary.values
  }

  /// Accesses the values associated with the given key for reading and writing.
  public subscript(key: Key) -> Set<Value>? {
    self.forwardDictionary[key]
  }

  /// Accesses the values associated with the given key for reading and writing.
  ///
  /// If this multi-dictionary doesn’t contain the given key, accesses the
  /// provided default value as if the key and default value existed in
  /// this multi-dictionary.
  public subscript(key: Key, default defaultValues: @autoclosure () -> Set<Value>) -> Set<Value> {
    self.forwardDictionary[key, default: defaultValues()]
  }

  /// Returns a set of keys that the given value is associated with.
  ///
  /// - Parameter v: The value to search for among the key-value associations in
  ///                this dictionary.
  /// - Returns: The set of keys associated with the given value.
  public func keysContainingValue(_ v: Value) -> Set<Key> {
    return self.reverseIndex[v] ?? []
  }

  /// Inserts the given value in the set of values associated with the given key.
  ///
  /// - Parameters:
  ///   - v: The value to insert.
  ///   - key: The key used to associate the given value with a set of elements.
  /// - Returns: `true` if the value was not previously associated with any
  ///            other values for the given key. Else, returns `false.
  @discardableResult
  public mutating func insertValue(_ v: Value, forKey key: Key) -> Bool {
    let inserted1 = self.reverseIndex[v, default: []].insert(key).inserted
    let inserted2 = self.forwardDictionary[key, default: []].insert(v).inserted
    assert(inserted1 == inserted2)
    return inserted1
  }

  /// Removes the given value from the set of values associated with the given key.
  ///
  /// - Parameters:
  ///   - v: The value to remove.
  ///   - key: The key used to associate the given value with a set of elements.
  /// - Returns: The removed element, if any.
  @discardableResult
  public mutating func removeValue(_ v: Value, forKey key: Key) -> Value? {
    let removedKey = self.reverseIndex[v]?.remove(key)
    let removedVal = self.forwardDictionary[key]?.remove(v)
    assert((removedKey == nil && removedVal == nil) ||
           (removedKey != nil && removedVal != nil))
    return removedVal
  }

  /// Removes all occurrences of the given value from all entries in this
  /// multi-dictionary.
  ///
  /// - Note: If this value is used as a key, this function does not erase its
  ///         entries from the underlying dictionary.
  ///
  /// - Parameter v: The value to remove.
  public mutating func removeOccurrences(of v: Value) {
    for k in self.reverseIndex.removeValue(forKey: v) ?? [] {
      self.forwardDictionary[k]!.remove(v)
    }
    assert(expensivelyCheckThatValueIsRemoved(v))
  }

  /// For assertions. Returns true `v` is removed from all `forwardDictionary` values.
  private func expensivelyCheckThatValueIsRemoved(_ v: Value) -> Bool {
    if self.reverseIndex[v] != nil {
      return false
    }
    return !self.forwardDictionary.values.contains(where: { $0.contains(v) })
  }
}
