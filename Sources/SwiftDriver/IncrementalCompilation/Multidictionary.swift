//===------------------------- Multidictionary.swift ----------------------===//
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

/// Like a Dictionary, but can have >1 value per key (i.e., a multimap)
struct Multidictionary<Key: Hashable, Value: Hashable>: Collection, Equatable {
  private var dictionary: Dictionary<Key, Set<Value>> = [:]
  
  public typealias Element = (Key, Set<Value>)
  public typealias Index = Dictionary<Key, Set<Value>>.Index

  /// The number of key-value pairs in this multi-dictionary.
  public var count: Int {
    self.dictionary.count
  }

  /// The position of the first element in a nonempty multi-dictionary.
  public var startIndex: Index {
    self.dictionary.startIndex
  }

  /// The collection’s “past the end” position—that is, the position one greater
  /// than the last valid subscript argument.
  public var endIndex: Index {
    self.dictionary.endIndex
  }

  /// Returns the index for the given key.
  ///
  /// - Parameter key: The key to find in the multi-dictionary.
  /// - Returns: The index for key and its associated value if key is in the
  ///            multi-dictionary; otherwise, nil.
  public func index(forKey key: Key) -> Dictionary<Key, Set<Value>>.Index? {
    self.dictionary.index(forKey: key)
  }

  /// Computes the position immediately after the given index.
  ///
  /// - Parameter i: A valid index of the collection. i must be less than endIndex.
  /// - Returns: The position immediately after the given index.
  func index(after i: Dictionary<Key, Set<Value>>.Index) -> Dictionary<Key, Set<Value>>.Index {
    self.dictionary.index(after: i)
  }

  subscript(position: Dictionary<Key, Set<Value>>.Index) -> (Key, Set<Value>) {
    self.dictionary[position]
  }

  /// A collection containing just the keys of this multi-dictionary.
  public var keys: Dictionary<Key, Set<Value>>.Keys {
    return self.dictionary.keys
  }

  /// A collection containing just the values of this multi-dictionary.
  public var values: Dictionary<Key, Set<Value>>.Values {
    return self.dictionary.values
  }

  /// Accesses the values associated with the given key for reading and writing.
  public subscript(key: Key) -> Set<Value>? {
    self.dictionary[key]
  }

  /// Accesses the values associated with the given key for reading and writing.
  ///
  /// If this multi-dictionary doesn’t contain the given key, accesses the
  /// provided default value as if the key and default value existed in
  /// this multi-dictionary.
  public subscript(key: Key, default defaultValues: @autoclosure () -> Set<Value>) -> Set<Value> {
    self.dictionary[key, default: defaultValues()]
  }

  /// Returns a set of keys that the given value is associated with.
  ///
  /// - Parameter v: The value to search for among the key-value associations in
  ///                this dictionary.
  /// - Returns: The set of keys associated with the given value.
  public func keysContainingValue(_ v: Value) -> Set<Key> {
    return self.dictionary.reduce(into: Set<Key>()) { acc, next in
      guard next.value.contains(v) else {
        return
      }
      acc.insert(next.key)
    }
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
    return self.dictionary[key, default: []].insert(v).inserted
  }

  /// Removes the given value from the set of values associated with the given key.
  ///
  /// - Parameters:
  ///   - v: The value to remove.
  ///   - key: The key used to associate the given value with a set of elements.
  /// - Returns: The removed element, if any.
  @discardableResult
  public mutating func removeValue(_ v: Value, forKey key: Key) -> Value? {
    return self.dictionary[key, default: []].remove(v)
  }

  /// Removes all occurrences of the given value from all entries in this
  /// multi-dictionary.
  ///
  /// - Note: If this value is used as a key, this function does not erase its
  ///         entries from the underlying dictionary.
  ///
  /// - Parameter v: The value to remove.
  public mutating func removeOccurrences(of v: Value) {
    for k in self.dictionary.keys {
      self.dictionary[k]!.remove(v)
    }
  }
}
