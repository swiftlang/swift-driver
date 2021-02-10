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
  public var keys: OuterDict.Keys {
    return self.outerDict.keys
  }
  
  public subscript(key: Key) -> (key: Key, values: Set<Value>)? {
    outerDict[key].map { (key: key, values: $0) }
  }

  public subscript(key: Key, default defaultValues: @autoclosure () -> Set<Value>) -> (key: Key, values: Set<Value>) {
    self[key] ?? (key: key, values: defaultValues())
  }
  
  public func keysContainingValue(_ v: Value) -> [Key] {
    outerDict.compactMap { (k, vs) in vs.contains(v) ? k : nil }
  }
  
  /// Returns true if inserted
  public mutating func addValue(_ v: Value, forKey key: Key) -> Bool {
    if var inner = outerDict[key] {
      let old = inner.insert(v).inserted
      outerDict[key] = inner
      return old
    }
    outerDict[key] = Set([v])
    return true
  }
  
  public mutating func removeValue(_ v: Value) {
    let changedPairs = outerDict.compactMap { kv -> (key: Key, value: Set<Value>?)? in
      var vals = kv.value
      guard vals.contains(v) else { return nil}
      vals.remove(v)
      return (key: kv.key, value: (vals.isEmpty ? nil : vals))
    }
    changedPairs.forEach {
      outerDict[$0.key] = $0.value
    }
  }
  
  @discardableResult
  public mutating func replace(_ original: Value,
                               with replacement: Value,
                               forKey key: Key)
  -> Bool
  {
    guard var vals = outerDict[key],
          let _ = vals.remove(original) else { return false }
    vals.insert(replacement)
    outerDict.updateValue(vals, forKey: key)
    return true
  }
}
