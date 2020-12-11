//===------------------------ TwoDMapTests.swift --------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import SwiftDriver

class TwoDMapTests: XCTestCase {

  func testTwoDMap() {
    var indices = [Int]()
    var m = TwoDMap<Int, String, Double>()

    m.verify { _, _, _ in XCTFail() }
    XCTAssertEqual(nil, m.updateValue(3.4, forKey: (1, "a")))
    m.verify { k, v, i in
      XCTAssert(k.0 == 1 && k.1 == "a" && v == 3.4)
      indices.append(i)
    }
    XCTAssertEqual(indices, [0, 1])
    indices.removeAll()

    XCTAssertEqual(3.4, m.updateValue(11, forKey: (1, "a")))
    m.verify {  _, _, _ in }

    XCTAssertEqual(nil, m.updateValue(21, forKey: (2, "a")))
    m.verify { _, _, _ in }

    XCTAssertEqual(nil, m.updateValue(12, forKey: (1, "b")))
    m.verify {  _, _, _ in }

    XCTAssertEqual(nil, m.updateValue(22, forKey: (2, "b")))
    m.verify {  _, _, _ in }

    var n = 0
    m.verify { k, v, i in
      switch (k.0, k.1, v, i) {
        case
          (1, "a", 11, 0),
          (1, "a", 11, 1),
          (2, "a", 21, 0),
          (2, "a", 21, 1),
          (1, "b", 12, 0),
          (1, "b", 12, 1),
          (2, "b", 22, 0),
          (2, "b", 22, 1):
          n += 1
        default: XCTFail()
      }
    }
    XCTAssertEqual(n, 8)

    XCTAssertEqual(21, m.removeValue(forKey: (2, "a")))
    n = 0
    m.verify { k, v, i in
      switch (k.0, k.1, v, i) {
        case
          (1, "a", 11, 0),
          (1, "a", 11, 1),
          (1, "b", 12, 0),
          (1, "b", 12, 1),
          (2, "b", 22, 0),
          (2, "b", 22, 1):
          n += 1
        default: XCTFail()
      }
    }
    XCTAssertEqual(n, 6)

    do {
      let a =  m[1]
      XCTAssertEqual(a, ["a": 11, "b": 12])

      let b = m[2]
      XCTAssertEqual(b, ["b": 22])

      let c = m["a"]
      XCTAssertEqual(c, [1: 11])

      let d = m["b"]
      XCTAssertEqual(d, [1: 12, 2: 22])

      let e = m[3]
      XCTAssertEqual(e, nil)

      let f = m["c"]
      XCTAssertEqual(f, nil)
    }
    do {
      let a = m[(1, "a")]
      let b = m[(1, "b")]
      let c = m[(2, "a")]
      let d = m[(2, "b")]
      let e = m[(3, "b")]
      let f = m[(3, "c")]
      XCTAssertEqual([a, b, c, d, e, f], [11, 12, nil, 22, nil, nil])
    }
  }

}
