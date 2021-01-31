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
  public typealias OuterDict = [Key: Set<Value>]
  public typealias InnerSet = Set<Value>
  private var outerDict = OuterDict()
  
  public typealias Element = (key: Key, value: Value)
  
  public enum Index: Comparable {
    case end
    case notEnd(OuterDict.Index, InnerSet.Index)
  }
  
  public var startIndex: Index {
    outerDict.first.map {Index.notEnd(outerDict.startIndex, $0.value.startIndex)} ?? .end
  }
  public var endIndex: Index {.end}
  
  public func index(after i: Index) -> Index {
    switch i {
    case .end: fatalError()
    case let .notEnd(outerIndex, innerIndex):
      let innerSet = outerDict[outerIndex].value
      let nextInner = innerSet.index(after: innerIndex)
      if nextInner < innerSet.endIndex {
        return .notEnd(outerIndex, nextInner)
      }
      let nextOuter = outerDict.index(after: outerIndex)
      if nextOuter < outerDict.endIndex {
        return .notEnd(nextOuter, outerDict[nextOuter].value.startIndex)
      }
      return .end
    }
  }
  
  public subscript(position: Index) -> (key: Key, value: Value) {
    switch position {
    case .end: fatalError()
    case  let .notEnd(outerIndex, innerIndex):
      let (key, vals) = outerDict[outerIndex]
      return (key: key, value: vals[innerIndex])
    }
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
