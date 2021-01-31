//===---------------- DictionaryOfDictionaries.swift ----------------------===//
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

/// A dictionary of dictionaries that also behaves like dictionary of tuples
/// It supports iterating over all 2nd-level pairs. See `subscript(key: OuterKey)`

import Foundation
public struct DictionaryOfDictionaries<OuterKey: Hashable, InnerKey: Hashable, Value>: Collection {
  public typealias InnerDict = [InnerKey: Value]
  public typealias OuterDict = [OuterKey: InnerDict]
  
  public typealias Key = (OuterKey, InnerKey)
  public typealias Element = (Key, Value)
  
  var outerDict = [OuterKey: [InnerKey: Value]]()
}

// MARK: indices
extension DictionaryOfDictionaries {
  public enum Index: Comparable {
    case end
    case notEnd(OuterDict.Index, InnerDict.Index)
    
    public static func < (lhs: Self, rhs: Self)
    -> Bool
    {
      switch (lhs, rhs) {
      case (.end, .end): return false
      case (_, .end): return true
      case (.end, _): return false
      case let (.notEnd(lo, li), .notEnd(ro, ri)):
        switch (lo, ro, li, ri) {
        case let (lo, ro, _, _) where lo != ro: return lo < ro
        case let (_, _, li, ri): return li < ri
        }
      }
    }
  }
  
  private func makeIndex(_ oi: OuterDict.Index, _ ii: InnerDict.Index) -> Index {
    assert(outerDict[oi].value.indices.contains(ii))
    return .notEnd(oi, ii)
  }
  
  public var startIndex: Index {
    return outerDict.isEmpty
      ? endIndex
      : makeIndex(outerDict.startIndex,
                  outerDict.first!.value.startIndex)
  }
  public var endIndex: Index {
    return .end
  }
  
  public func index(after i: Index) -> Index {
    switch i {
    case .end: fatalError("index at end")
    case let .notEnd(outerIndex, innerIndex):
      let innerDict = outerDict[outerIndex].value
      let nextInnerIndex = innerDict.index(after: innerIndex)
      if nextInnerIndex < innerDict.endIndex {
        return makeIndex(outerIndex, nextInnerIndex)
      }
      let nextOuterIndex = outerDict.index(after: outerIndex)
      if nextOuterIndex < outerDict.endIndex {
        return .notEnd(nextOuterIndex, outerDict[nextOuterIndex].value.startIndex)
      }
      return .end
    }
  }
}

// MARK: - subscripting
extension DictionaryOfDictionaries {
  public subscript(position: Index) -> Element {
    switch position {
    case .end: fatalError("index at end")
    case let .notEnd(outerIndex, innerIndex):
      let (outerKey, innerDict) = outerDict[outerIndex]
      let (innerKey, value) = innerDict[innerIndex]
      return (key: (outerKey, innerKey), value: value)
    }
  }
  
  public subscript(key: Key) -> Value? {
    get {outerDict[key.0]?[key.1]}
    set {
      if let v = newValue { _ = updateValue(v, forKey: key) }
      else { _ = removeValue(forKey: key) }
    }
  }
  
  public subscript(key: OuterKey) -> [InnerKey: Value]? {
    get {outerDict[key]}
    set {
      if let v = newValue { _ = outerDict.updateValue(v, forKey: key) }
      else { _ = outerDict.removeValue(forKey: key) }
    }
  }
}

// MARK: - mutating
extension DictionaryOfDictionaries {
  mutating func updateValue(_ v: Value, forKey keys : (OuterKey,InnerKey)
  ) -> Value? {
    if var innerDict = outerDict[keys.0] {
      let old = innerDict.updateValue(v, forKey: keys.1)
      outerDict.updateValue(innerDict, forKey: keys.0)
      return old
    }
    outerDict.updateValue([keys.1: v], forKey: keys.0)
    return nil
  }
  
  mutating func removeValue(forKey keys : (OuterKey,InnerKey)
  ) -> Value? {
    guard var innerDict = outerDict[keys.0]
    else { return nil }
    let old = innerDict.removeValue(forKey: keys.1)
    if innerDict.isEmpty {
      outerDict.removeValue(forKey: keys.0)
    }
    else {
      outerDict.updateValue(innerDict, forKey: keys.0)
    }
    return old
  }
}

// MARK: - comparing

extension DictionaryOfDictionaries: Equatable  where Value: Equatable {}
