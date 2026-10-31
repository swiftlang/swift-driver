//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import SwiftDriver
import Testing

@Suite struct MultidictionaryTests {

  private func multidictionaryWith<K: Hashable, V: Hashable>(_ keysAndValues: [K: [V]]) -> Multidictionary<K, V> {
    var dict = Multidictionary<K, V>()
    for (k, vals) in keysAndValues {
      for v in vals {
        dict.insertValue(v, forKey: k)
      }
    }
    return dict
  }

  @Test func `init`() throws {
    let dict = Multidictionary<String, Int>()

    #expect(dict.count == 0)
    #expect(dict.keys.count == 0)
    #expect(dict.values.count == 0)
    #expect(dict.startIndex == dict.endIndex)
  }

  @Test func insertion() throws {
    var dict = Multidictionary<String, Int>()

    dict.insertValue(1, forKey: "a")
    dict.insertValue(1, forKey: "b")
    dict.insertValue(2, forKey: "b")
    dict.insertValue(1, forKey: "c")
    dict.insertValue(2, forKey: "c")
    dict.insertValue(3, forKey: "c")
    dict.insertValue(4, forKey: "c")

    #expect(dict.count == 3)
    #expect(dict["a"] == [1])
    #expect(dict["b"] == [1, 2])
    #expect(dict["c"] == [1, 2, 3, 4])
    #expect(dict.keysContainingValue(1) == ["a", "b", "c"])
    #expect(dict.keysContainingValue(2) == ["b", "c"])
    #expect(dict.keysContainingValue(3) == ["c"])
    #expect(dict.keysContainingValue(4) == ["c"])
  }

  @Test func insertion_existingPair() {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    // Inserting an existing k:v pair a second time should do nothing.
    let inserted = dict.insertValue(1, forKey: "a")
    #expect(!inserted)

    #expect(dict.count == 3)
    #expect(dict["a"] == [1])
    #expect(dict["b"] == [1, 2])
    #expect(dict["c"] == [1, 2, 3, 4])
    #expect(dict.keysContainingValue(1) == ["a", "b", "c"])
    #expect(dict.keysContainingValue(2) == ["b", "c"])
    #expect(dict.keysContainingValue(3) == ["c"])
    #expect(dict.keysContainingValue(4) == ["c"])
  }

  @Test func removeValue() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    #expect(dict.removeValue(2, forKey: "c") != nil)

    #expect(dict.count == 3)
    #expect(dict["a"] == [1])
    #expect(dict["b"] == [1, 2])
    #expect(dict["c"] == [1, 3, 4])
    #expect(dict.keysContainingValue(1) == ["a", "b", "c"])
    #expect(dict.keysContainingValue(2) == ["b"])
    #expect(dict.keysContainingValue(3) == ["c"])
    #expect(dict.keysContainingValue(4) == ["c"])
  }

  @Test func removeValue_nonExistentValue() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    #expect(dict.removeValue(5, forKey: "c") == nil)

    #expect(dict.count == 3)
    #expect(dict["a"] == [1])
    #expect(dict["b"] == [1, 2])
    #expect(dict["c"] == [1, 2, 3, 4])
    #expect(dict.keysContainingValue(1) == ["a", "b", "c"])
    #expect(dict.keysContainingValue(2) == ["b", "c"])
    #expect(dict.keysContainingValue(3) == ["c"])
    #expect(dict.keysContainingValue(4) == ["c"])
  }

  @Test func removeValue_nonExistentKey() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    #expect(dict.removeValue(1, forKey: "d") == nil)

    #expect(dict.count == 3)
    #expect(dict["a"] == [1])
    #expect(dict["b"] == [1, 2])
    #expect(dict["c"] == [1, 2, 3, 4])
    #expect(dict.keysContainingValue(1) == ["a", "b", "c"])
    #expect(dict.keysContainingValue(2) == ["b", "c"])
    #expect(dict.keysContainingValue(3) == ["c"])
    #expect(dict.keysContainingValue(4) == ["c"])
  }

  @Test func removeOccurencesOf() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    dict.removeOccurrences(of: 1)

    #expect(dict.count == 3)
    #expect(dict["a"] == [])
    #expect(dict["b"] == [2])
    #expect(dict["c"] == [2, 3, 4])
    #expect(dict.keysContainingValue(1) == [])
    #expect(dict.keysContainingValue(2) == ["b", "c"])
    #expect(dict.keysContainingValue(3) == ["c"])
    #expect(dict.keysContainingValue(4) == ["c"])
  }

  @Test func removeOccurencesOf_nonExistentValue() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    dict.removeOccurrences(of: 5)

    #expect(dict.count == 3)
    #expect(dict["a"] == [1])
    #expect(dict["b"] == [1, 2])
    #expect(dict["c"] == [1, 2, 3, 4])
    #expect(dict.keysContainingValue(1) == ["a", "b", "c"])
    #expect(dict.keysContainingValue(2) == ["b", "c"])
    #expect(dict.keysContainingValue(3) == ["c"])
    #expect(dict.keysContainingValue(4) == ["c"])
  }

  /// The reverse index is only built by the first `removeOccurrences(of:)`; insertions and removals afterwards keep it
  /// up to date.
  @Test func reverseIndexMaintainedAfterRemoveOccurrences() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
    ])
    #expect(dict.keysContainingValue(1) == ["a", "b"])

    dict.removeOccurrences(of: 1)
    dict.insertValue(3, forKey: "a")
    dict.insertValue(2, forKey: "c")
    dict.removeValue(2, forKey: "b")

    #expect(dict.keysContainingValue(1) == [])
    #expect(dict.keysContainingValue(2) == ["c"])
    #expect(dict.keysContainingValue(3) == ["a"])
    dict.removeOccurrences(of: 2)
    #expect(dict["c"] == [])
    #expect(dict.keysContainingValue(2) == [])
  }

  /// Building the reverse index in one copy doesn't affect another, and doesn't affect equality.
  @Test func copiesWithAndWithoutReverseIndex() throws {
    let original = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
    ])
    var copy = original
    copy.removeOccurrences(of: 3)
    #expect(copy == original)

    copy.removeOccurrences(of: 1)
    #expect(copy != original)
    #expect(original["a"] == [1])
    #expect(original.keysContainingValue(1) == ["a", "b"])
    #expect(copy.keysContainingValue(1) == [])

    var copy2 = copy
    copy2.insertValue(1, forKey: "a")
    #expect(copy.keysContainingValue(1) == [])
    #expect(copy2.keysContainingValue(1) == ["a"])
  }
}
