//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Testing
import SwiftOptions

@Suite struct PrefixTrieTests {
  @Test func simpleTrie() {
    var trie = PrefixTrie<Int>()

    trie["1234"] = nil
    #expect(trie.nodeCount == 2)

    trie["a"] = 0
    trie["b"] = 1
    trie["abcd"] = 2
    trie["abc"] = 3

    #expect(trie.nodeCount == 6)

    #expect(trie["a"] == 0)
    #expect(trie["ab"] == 0)
    #expect(trie["b"] == 1)
    #expect(trie["abcd"] == 2)
    #expect(trie["abcdefg"] == 2)
    #expect(trie["abc"] == 3)
    #expect(trie["c"] == nil)
  }

  @Test func manyMatchingPrefixes() {
    var trie = PrefixTrie<Int>()
    trie["an"] = 0
    trie["ant"] = 1
    trie["anteater"] = 2
    trie["anteaters"] = 3

    #expect(trie["a"] == nil)
    #expect(trie["an"] == 0)
    #expect(trie["ant"] == 1)
    #expect(trie["ante"] == 1)
    #expect(trie["antea"] == 1)
    #expect(trie["anteat"] == 1)
    #expect(trie["anteate"] == 1)
    #expect(trie["anteater"] == 2)
    #expect(trie["anteaters"] == 3)
  }

  @Test func updating() {

    var trie = PrefixTrie<Int>()
    trie["garbage"] = 0
    #expect(trie["garbage"] == 0)

    trie["garbage"] = 1
    #expect(trie["garbage"] == 1)

    trie["garbage"] = nil
    #expect(trie["garbage"] == nil)
    #expect(trie.nodeCount == 2)
    // Removing a node leaves the entry in the trie

    trie["12345"] = 12345 // 5 nodes
    trie["12367"] = 12367 // 3 common nodes, 2 new nodes
    #expect(trie.nodeCount == 5)
    trie["123890"] = 123890 // 3 common nodes, 3 new nodes
    #expect(trie.nodeCount == 6)
    trie["123890"] = nil
    #expect(trie.nodeCount == 6)
    #expect(trie["123890"] == nil)
    trie["abc"] = 979899 // 1 new node, 0 common nodes
    #expect(trie.nodeCount == 7)
    // existing prefix that cannot be deleted since
    // 12345 & 12367 exist
    trie["123"] = nil
    #expect(trie.nodeCount == 7)

  }
}
