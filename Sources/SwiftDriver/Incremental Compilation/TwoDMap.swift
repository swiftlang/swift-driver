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
@_spi(Testing) public struct TwoDMap<Key1: Hashable, Key2: Hashable, Value: Equatable> {

  private var map1 = [Key1: [Key2: Value]]()
  private var map2 = [Key2: [Key1: Value]]()

  public init() {}

  public mutating func updateValue(_ v: Value, forKey keys: (Key1, Key2)) -> Value? {
    let inserted1 = map1.updateValue(v, forKey:  keys           )
    let inserted2 = map2.updateValue(v, forKey: (keys.1, keys.0))
    assert(inserted1 == inserted2)
    return inserted1
  }

  public subscript( _ keys: (Key1, Key2) ) -> Value? {
    let v = map1[keys.0, keys.1]
    assert(map2[keys.1, keys.0] == v)
    return v
  }

  public subscript( _ k1: Key1) -> [Key2: Value]? { map1[k1] }
  public subscript( _ k2: Key2) -> [Key1: Value]? { map2[k2] }

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
  public func verify(_ fn: (Key1, Key2, Value, Int) -> Void) -> Bool {
    map1.forEach { k1, inner in
      inner.forEach {k2, v in
        assert(v == map1[k1, k2])
        fn(k1, k2, v, 0)
      }
    }
    map2.forEach { k2, inner in
      inner.forEach {k1, v in
        assert(v == map2[k2, k1])
        fn(k1, k2, v, 1)
      }
    }
    return true
  }
}

fileprivate extension Dictionary {
  mutating func updateValue<Key2, V>(_ v: V, forKey keys: (Key, Key2)) -> V?
  where Value == [Key2: V]
  {
    var inner = self[keys.0, default: Value()]
    let r = inner.updateValue(v, forKey: keys.1)
    updateValue(inner, forKey: keys.0)
    return r
  }

  mutating func removeValue<Key2, V>(forKey keys: (Key, Key2)) -> V?
  where Value == [Key2: V]
  {
    guard var inner = self[keys.0] else {return nil}
    let r = inner.removeValue(forKey: keys.1)
    if inner.isEmpty { removeValue(forKey: keys.0) }
    else { updateValue(inner, forKey: keys.0) }
    return r
  }

  subscript<Key2, V>(_ k1: Key, _ k2: Key2) -> V?
  where Value == [Key2: V]
  {
    self[k1].flatMap { $0[k2] }
  }
}
