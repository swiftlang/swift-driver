//===------------ MultidictionaryTests.swift - Swift Testing ----===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
@_spi(Testing) import SwiftDriver

class MultidictionaryTests: XCTestCase {

  private func multidictionaryWith<K: Hashable, V: Hashable>(_ keysAndValues: Dictionary<K, [V]>) -> Multidictionary<K, V>{
    var dict = Multidictionary<K, V>()
    for (k, vals) in keysAndValues {
      for v in vals {
        dict.insertValue(v, forKey: k)
      }
    }
    return dict
  }

  func testInit() throws {
    let dict = Multidictionary<String, Int>()

    XCTAssertEqual(dict.count, 0)
    XCTAssertEqual(dict.keys.count, 0)
    XCTAssertEqual(dict.values.count, 0)
    XCTAssertEqual(dict.startIndex, dict.endIndex)
  }

  func testInsertion() throws {
    var dict = Multidictionary<String, Int>()

    dict.insertValue(1, forKey: "a")
    dict.insertValue(1, forKey: "b")
    dict.insertValue(2, forKey: "b")
    dict.insertValue(1, forKey: "c")
    dict.insertValue(2, forKey: "c")
    dict.insertValue(3, forKey: "c")
    dict.insertValue(4, forKey: "c")

    XCTAssertEqual(dict.count, 3)
    XCTAssertEqual(dict["a"], [1])
    XCTAssertEqual(dict["b"], [1, 2])
    XCTAssertEqual(dict["c"], [1, 2, 3, 4])
    XCTAssertEqual(dict.keysContainingValue(1), ["a", "b", "c"])
    XCTAssertEqual(dict.keysContainingValue(2), ["b", "c"])
    XCTAssertEqual(dict.keysContainingValue(3), ["c"])
    XCTAssertEqual(dict.keysContainingValue(4), ["c"])
  }

  func testInsertion_existingPair() {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    // Inserting an existing k:v pair a second time should do nothing.
    XCTAssertFalse(dict.insertValue(1, forKey: "a"))

    XCTAssertEqual(dict.count, 3)
    XCTAssertEqual(dict["a"], [1])
    XCTAssertEqual(dict["b"], [1, 2])
    XCTAssertEqual(dict["c"], [1, 2, 3, 4])
    XCTAssertEqual(dict.keysContainingValue(1), ["a", "b", "c"])
    XCTAssertEqual(dict.keysContainingValue(2), ["b", "c"])
    XCTAssertEqual(dict.keysContainingValue(3), ["c"])
    XCTAssertEqual(dict.keysContainingValue(4), ["c"])
  }

  func testRemoveValue() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    XCTAssertNotNil(dict.removeValue(2, forKey: "c"))

    XCTAssertEqual(dict.count, 3)
    XCTAssertEqual(dict["a"], [1])
    XCTAssertEqual(dict["b"], [1, 2])
    XCTAssertEqual(dict["c"], [1, 3, 4])
    XCTAssertEqual(dict.keysContainingValue(1), ["a", "b", "c"])
    XCTAssertEqual(dict.keysContainingValue(2), ["b"])
    XCTAssertEqual(dict.keysContainingValue(3), ["c"])
    XCTAssertEqual(dict.keysContainingValue(4), ["c"])
  }

  func testRemoveValue_nonExistentValue() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    XCTAssertNil(dict.removeValue(5, forKey: "c"))

    XCTAssertEqual(dict.count, 3)
    XCTAssertEqual(dict["a"], [1])
    XCTAssertEqual(dict["b"], [1, 2])
    XCTAssertEqual(dict["c"], [1, 2, 3, 4])
    XCTAssertEqual(dict.keysContainingValue(1), ["a", "b", "c"])
    XCTAssertEqual(dict.keysContainingValue(2), ["b", "c"])
    XCTAssertEqual(dict.keysContainingValue(3), ["c"])
    XCTAssertEqual(dict.keysContainingValue(4), ["c"])
  }

  func testRemoveValue_nonExistentKey() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    XCTAssertNil(dict.removeValue(1, forKey: "d"))

    XCTAssertEqual(dict.count, 3)
    XCTAssertEqual(dict["a"], [1])
    XCTAssertEqual(dict["b"], [1, 2])
    XCTAssertEqual(dict["c"], [1, 2, 3, 4])
    XCTAssertEqual(dict.keysContainingValue(1), ["a", "b", "c"])
    XCTAssertEqual(dict.keysContainingValue(2), ["b", "c"])
    XCTAssertEqual(dict.keysContainingValue(3), ["c"])
    XCTAssertEqual(dict.keysContainingValue(4), ["c"])
  }

  func testRemoveOccurencesOf() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    dict.removeOccurrences(of: 1)

    XCTAssertEqual(dict.count, 3)
    XCTAssertEqual(dict["a"], [])
    XCTAssertEqual(dict["b"], [2])
    XCTAssertEqual(dict["c"], [2, 3, 4])
    XCTAssertEqual(dict.keysContainingValue(1), [])
    XCTAssertEqual(dict.keysContainingValue(2), ["b", "c"])
    XCTAssertEqual(dict.keysContainingValue(3), ["c"])
    XCTAssertEqual(dict.keysContainingValue(4), ["c"])
  }

  func testRemoveOccurencesOf_nonExistentValue() throws {
    var dict = multidictionaryWith([
      "a": [1],
      "b": [1, 2],
      "c": [1, 2, 3, 4],
    ])

    dict.removeOccurrences(of: 5)

    XCTAssertEqual(dict.count, 3)
    XCTAssertEqual(dict["a"], [1])
    XCTAssertEqual(dict["b"], [1, 2])
    XCTAssertEqual(dict["c"], [1, 2, 3, 4])
    XCTAssertEqual(dict.keysContainingValue(1), ["a", "b", "c"])
    XCTAssertEqual(dict.keysContainingValue(2), ["b", "c"])
    XCTAssertEqual(dict.keysContainingValue(3), ["c"])
    XCTAssertEqual(dict.keysContainingValue(4), ["c"])
  }
}
