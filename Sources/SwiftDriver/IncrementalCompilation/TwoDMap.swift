//===---------------- TwoDMap.swift ---------------------------------------===//
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


/// A map with 2 keys that can iterate in a number of ways
public struct TwoDMap<Key1: Hashable, Key2: Hashable, Value: Equatable>: MutableCollection, Equatable {

  private var map1 = TwoLevelMap<Key1, Key2, Value>()
  private var map2 = TwoLevelMap<Key2, Key1, Value>()

  public typealias Key = (Key1, Key2)
  public typealias Element = (Key, Value)
  public typealias Index = TwoLevelMap<Key1, Key2, Value>.Index

  public init() {}

  public subscript(position: Index) -> Element {
    get { map1[position] }
    set {
      map1[newValue.0] = newValue.1
      map2[(newValue.0.1, newValue.0.0)] = newValue.1
    }
  }

  public subscript(key: Key) -> Value? {
    get { map1[key] }
  }

  public subscript(key: Key1) -> [Key2: Value]? {
    get { map1[key] }
  }

  public subscript(key: Key2) -> [Key1: Value]? {
    get { map2[key] }
  }

  public var startIndex: Index {
    map1.startIndex
  }

  public var endIndex: Index {
    map1.endIndex
  }

  public func index(after i: Index) -> Index {
    map1.index(after: i)
  }

  @discardableResult
  public mutating func updateValue(_ v: Value, forKey keys: (Key1, Key2)) -> Value? {
    let inserted1 = map1.updateValue(v, forKey:  keys           )
    let inserted2 = map2.updateValue(v, forKey: (keys.1, keys.0))
    assert(inserted1 == inserted2)
    return inserted1
  }

  @discardableResult
  public mutating func removeValue(forKey keys: (Key1, Key2)) -> Value? {
    let v1 = map1.removeValue(forKey:  keys           )
    let v2 = map2.removeValue(forKey: (keys.1, keys.0))
    assert(v1 == v2)
    return v1
  }

  /// Verify the integrity of each map and the cross-map consistency.
  /// Then call \p verifyFn for each entry found in each of the two maps,
  /// passing an index so that the verifyFn knows which map is being tested.
  @discardableResult
  public func verify(_ fn: ((Key1, Key2), Value, Int) -> Void) -> Bool {
    map1.forEach { (kv: ((Key1, Key2), Value)) in
      assert(kv.1 == map2[(kv.0.1, kv.0.0)])
      fn(kv.0, kv.1, 0)
    }
    map2.forEach { (kv: ((Key2, Key1), Value)) in
      assert(kv.1 == map1[(kv.0.1, kv.0.0)])
      fn((kv.0.1, kv.0.0), kv.1, 1)
    }
    return true
  }
}
