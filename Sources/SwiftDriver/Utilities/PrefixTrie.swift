/// A prefix trie is a data structure for quickly matching prefixes of strings.
/// It's a tree structure where each node in the tree corresponds to another
/// element in the prefix of whatever you're looking for.
///
/// For example, the strings 'Hello' and 'Help' would look like this:
///
/// ```
///                      ┌───┐  ┌───┐
///                 ┌───▶│ l │─▶│ o │
/// ┌───┐  ┌───┐  ┌───┐  └───┘  └───┘
/// │ H │─▶│ e │─▶│ l │
/// └───┘  └───┘  └───┘  ┌───┐
///                 └───▶│ p │
///                      └───┘
/// ```
///
/// Traversing this trie is O(min(n, m)) with `n` representing the length of the
/// key being searched and `m` representing the longest matching prefix in the
/// tree.
///
/// Inserting into the trie is also O(n) with the length of the key being
/// inserted.
public struct PrefixTrie<Key: Collection, Value> where Key.Element: Hashable {
  internal class Node {
    var value: Value?
    var next = [Key.Element: Node]()

    init(value: Value?) {
      self.value = value
    }
  }

  /// Creates a prefix trie with nothing inside.
  public init() {}

  // Start with an empty node at the root, to make traversal easy
  var root = Node(value: nil)

  /// Finds the value associated with the longest prefix that matches the
  /// provided key.
  /// For example, for a trie that has `["Help", "Hello", "Helping"]` inside,
  /// Searching for `"Helper"` gives you the value associated with `"Help"`,
  /// while searching for `"Helping a friend"` gives you `"Helping"`.
  public subscript(key: Key) -> Value? {
    get {
      var bestMatch: Value?
      var current = root
      for elt in key {
        guard let next = current.next[elt] else { break }
        current = next
        if let value = current.value {
          bestMatch = value
        }
      }
      return bestMatch
    }
    set {
      var index = key.startIndex
      var current = root
      // Keep track of which nodes we've visited along the way,
      // so we can walk back up this if we need to prune dead branches.
      // Note: This is only used (and is only appended to) if the new
      //       value being stored is `nil`.
      var traversed: [(node: Node, step: Key.Element?)] = [(root, nil)]

      // Traverse as much of the prefix as we can, keeping track of the index
      // we ended on
      while index < key.endIndex, let next = current.next[key[index]] {
        if newValue == nil {
            traversed.append((next, key[index]))
        }

        key.formIndex(after: &index)
        current = next
      }

      // We're matching a prefix of an existing key in the trie
      if index == key.endIndex {
        // Update the value in the trie with the new value
        current.value = newValue
        // backtrack and remove dead branches
        if newValue == nil {
            var current = traversed.popLast()
            while let parent = traversed.popLast(), let currentStep = current?.step {
                if parent.node.next[currentStep]?.value == nil
                  && parent.node.next[currentStep]?.next.keys.count == 0 {
                    parent.node.next[currentStep] = nil
                    current = parent
                }
            }
        }
        return
      }

      // If the value we're adding is `nil` just return and don't create the trie
      guard newValue != nil else {
        return
      }

      while index < key.endIndex {
        // Fill out the remaining nodes with nils, until we get to the last
        // element
        let step = key[index]

        key.formIndex(after: &index)
        let new = Node(value: index == key.endIndex ? newValue : nil)
        current.next[step] = new
        current = new
      }
    }
  }

  /// Returns the number of nodes in the trie
  public var nodeCount: Int {

      var count = 0

      var nodes = [self.root]
      while let currentNode = nodes.popLast() {
          nodes.append(contentsOf: currentNode.next.values)
          count += currentNode.next.keys.count
      }

      return count
  }
}
