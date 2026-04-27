//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Testing
import SwiftDriver

@Suite struct TwoDMapTests {

  @Test func twoDMap() {
    var indices = [Int]()
    var m = TwoDMap<Int, String, Double>()

    m.verify { _, _, _ in Issue.record() }
    #expect(nil == m.updateValue(3.4, forKey: (1, "a")))
    m.verify { k, v, i in
      #expect(k.0 == 1 && k.1 == "a" && v == 3.4)
      indices.append(i)
    }
    #expect(indices == [0, 1])
    indices.removeAll()

    #expect(3.4 == m.updateValue(11, forKey: (1, "a")))
    m.verify {  _, _, _ in }

    #expect(nil == m.updateValue(21, forKey: (2, "a")))
    m.verify { _, _, _ in }

    #expect(nil == m.updateValue(12, forKey: (1, "b")))
    m.verify {  _, _, _ in }

    #expect(nil == m.updateValue(22, forKey: (2, "b")))
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
        default: Issue.record()
      }
    }
    #expect(n == 8)

    #expect(21 == m.removeValue(forKey: (2, "a")))
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
        default: Issue.record()
      }
    }
    #expect(n == 6)

    do {
      let a =  m[1]
      #expect(a == ["a": 11, "b": 12])

      let b = m[2]
      #expect(b == ["b": 22])

      let c = m["a"]
      #expect(c == [1: 11])

      let d = m["b"]
      #expect(d == [1: 12, 2: 22])

      let e = m[3]
      #expect(e == nil)

      let f = m["c"]
      #expect(f == nil)
    }
    do {
      let a = m[(1, "a")]
      let b = m[(1, "b")]
      let c = m[(2, "a")]
      let d = m[(2, "b")]
      let e = m[(3, "b")]
      let f = m[(3, "c")]
      #expect([a, b, c, d, e, f] == [11, 12, nil, 22, nil, nil])
    }
  }

}
