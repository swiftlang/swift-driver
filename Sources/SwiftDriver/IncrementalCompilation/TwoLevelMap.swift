//===----------------------- TwoLevelMap.swift ----------------------------===//
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

/// A `TwoLevelMap` is a dictionary of dictionaries.
///
/// This data structure is particularly efficient when locality of access
/// matters after a lookup for an inner dictionary. When locality does not
/// matter, use a plain dictionary and a custom key type that hashes two
/// sub-keys instead.
///
/// This collection supports an additional two-level subscript operation with
/// a tuple of an outer key and an inner key.
public struct TwoLevelMap<OuterKey: Hashable, InnerKey: Hashable, Value> {
  public typealias InnerDict = [InnerKey: Value]
  public typealias OuterDict = [OuterKey: InnerDict]

  public typealias Key = (OuterKey, InnerKey)
  public typealias Element = (Key, Value)

  private var outerDict = [OuterKey: [InnerKey: Value]]()
}

// MARK: - Indexing

extension TwoLevelMap: Collection {
  /// The position of a two-level key-value pair in a two-level map.
  ///
  /// - Warning: Do not attempt to iterate over a two-level map.
  ///   Use of the indices is unergonomic, inefficient, and will lead to
  ///   non-deterministic behaviors in the driver under many conditions.
  ///   Always prefer a sorted collection unless you are absolutely sure the
  ///   operation in question is order-independent.
  public enum Index: Comparable {
    case end
    case notEnd(OuterDict.Index, InnerDict.Index)

    public static func < (lhs: Self, rhs: Self) -> Bool {
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

  /// The position of the first element in a nonempty two-level map.
  public var startIndex: Index {
    guard !outerDict.isEmpty else {
      return .end
    }

    guard let firstNonEmptyIndex = outerDict.firstIndex(where: { !$1.isEmpty }) else {
      return .end
    }

    let innerStartIndex = outerDict[firstNonEmptyIndex].value.startIndex
    return .notEnd(firstNonEmptyIndex, innerStartIndex)
  }

  /// The collection’s “past the end” position—that is, the position one greater
  /// than the last valid subscript argument.
  public var endIndex: Index {
    return .end
  }

  /// Computes the position immediately after the given index.
  ///
  /// - Parameter i: A valid index of the collection. i must be less than endIndex.
  /// - Returns: The position immediately after the given index.
  public func index(after i: Index) -> Index {
    switch i {
    case .end: fatalError("index at end")
    case let .notEnd(outerIndex, innerIndex):
      let innerDict = outerDict[outerIndex].value
      let nextInnerIndex = innerDict.index(after: innerIndex)
      if nextInnerIndex < innerDict.endIndex {
        return .notEnd(outerIndex, nextInnerIndex)
      }

      let nextOuterIndex = outerDict.index(after: outerIndex)
      guard let firstNonEmpty = outerDict[nextOuterIndex...].firstIndex(where: { !$1.isEmpty }) else {
        return .end
      }

      return .notEnd(firstNonEmpty, outerDict[firstNonEmpty].value.startIndex)
    }
  }

  /// Accesses the value associated with the given index.
  ///
  /// - Returns: The element at the given index.
  public subscript(position: Index) -> Element {
    switch position {
    case .end: fatalError("index at end")
    case let .notEnd(outerIndex, innerIndex):
      let (outerKey, innerDict) = outerDict[outerIndex]
      let (innerKey, value) = innerDict[innerIndex]
      return (key: (outerKey, innerKey), value: value)
    }
  }
}

extension TwoLevelMap {
  /// Accesses the value associated with the given two-level key for reading and writing.
  ///
  /// - Returns: The value associated with two-level key if key is in the two-level map;
  ///   otherwise, `nil`.
  public subscript(key: Key) -> Value? {
    get { outerDict[key.0]?[key.1] }
    set { outerDict[key.0, default: [:]][key.1] = newValue }
  }

  /// Accesses all values associated with the given single-level key.
  ///
  /// - Returns: A dictionary of values associated with key if key is in the two-level map;
  ///   otherwise, `nil`.
  public subscript(key: OuterKey) -> [InnerKey: Value]? {
    get { outerDict[key] }
    set { outerDict[key] = newValue }
  }
}

// MARK: - Updating Keys and Values

extension TwoLevelMap {
  /// Updates the value stored in the two-level map for the given two-level key,
  /// or adds a new two-level key-value pair if the two-level key does not
  /// exist.
  ///
  /// If access to the old value is not necessary, it is more efficient to use
  /// the subscript operator to perform an in-place update.
  ///
  /// - Parameters:
  ///   - v: The new value to add to the two-level map.
  ///   - key: The two-level key to associate with value.
  /// - Returns: The value that was replaced, or `nil` if a new key-value pair was added.
  mutating func updateValue(_ v: Value, forKey key: Key) -> Value? {
    let old = self[key]
    self[key] = v
    return old
  }

  /// Removes the given key and its associated value from the two-level map.
  ///
  /// If access to the old value is not necessary, it is more efficient to use
  /// the subscript operator to perform an in-place update.
  ///
  /// - Parameter key: The two-level key to remove along with its
  ///   associated value.
  /// - Returns: The value that was removed, or `nil` if the key was not present
  ///   in the two-level map.
  mutating func removeValue(forKey key: Key) -> Value? {
    let old = self[key]
    self[key] = nil
    return old
  }
}

// MARK: - Identity

 extension TwoLevelMap: Equatable where Value: Equatable {}
