import XCTest
import SwiftOptions

final class PrefixTrieTests: XCTestCase {
  func testSimpleTrie() {
    var trie = PrefixTrie<String, Int>()

    trie["1234"] = nil
    XCTAssertEqual(trie.nodeCount, 0)

    trie["a"] = 0
    trie["b"] = 1
    trie["abcd"] = 2
    trie["abc"] = 3

    XCTAssertEqual(trie.nodeCount, 5)

    XCTAssertEqual(trie["a"], 0)
    XCTAssertEqual(trie["ab"], 0)
    XCTAssertEqual(trie["b"], 1)
    XCTAssertEqual(trie["abcd"], 2)
    XCTAssertEqual(trie["abcdefg"], 2)
    XCTAssertEqual(trie["abc"], 3)
    XCTAssertNil(trie["c"])
  }

  func testManyMatchingPrefixes() {
    var trie = PrefixTrie<String, Int>()
    trie["an"] = 0
    trie["ant"] = 1
    trie["anteater"] = 2
    trie["anteaters"] = 3

    XCTAssertNil(trie["a"])
    XCTAssertEqual(trie["an"], 0)
    XCTAssertEqual(trie["ant"], 1)
    XCTAssertEqual(trie["ante"], 1)
    XCTAssertEqual(trie["antea"], 1)
    XCTAssertEqual(trie["anteat"], 1)
    XCTAssertEqual(trie["anteate"], 1)
    XCTAssertEqual(trie["anteater"], 2)
    XCTAssertEqual(trie["anteaters"], 3)
  }

  func testUpdating() {

    var trie = PrefixTrie<String, Int>()
    trie["garbage"] = 0
    XCTAssertEqual(trie["garbage"], 0)

    trie["garbage"] = 1
    XCTAssertEqual(trie["garbage"], 1)

    trie["garbage"] = nil
    XCTAssertNil(trie["garbage"])
    XCTAssertEqual(trie.nodeCount, 0)

    trie["12345"] = 12345 // 5 nodes
    trie["12367"] = 12367 // 3 common nodes, 2 new nodes
    XCTAssertEqual(trie.nodeCount, 7)
    trie["123890"] = 123890 // 3 common nodes, 3 new nodes
    XCTAssertEqual(trie.nodeCount, 10)
    trie["123890"] = nil
    XCTAssertEqual(trie.nodeCount, 7)
    XCTAssertNil(trie["123890"])
    trie["abc"] = 979899 // 3 new nodes, 0 common nodes
    XCTAssertEqual(trie.nodeCount, 10)
    // existing prefix that cannot be deleted since
    // 12345 & 12367 exist
    trie["123"] = nil
    XCTAssertEqual(trie.nodeCount, 10)

  }

  func testCollectionMatching() {
    var trie = PrefixTrie<[Int], Int>()
    trie[[1, 2, 3]] = 0
    trie[[1, 2]] = 1
    trie[[0, 1, 2]] = 2

    XCTAssertEqual(trie[[1, 2]], 1)
    XCTAssertEqual(trie[[1, 2, 3, 4]], 0)
    XCTAssertNil(trie[[0, 1]])
    XCTAssertEqual(trie[[0, 1, 2]], 2)
  }
}
