//==------------------ PrefixTrie.swift - Prefix Trie ---------------------===//
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

/// A prefix trie is a data structure for quickly matching prefixes of strings.
/// It's a tree structure where each node in the tree corresponds to another
/// element in the prefix of whatever you're looking for.
///
/// For example, if you entered these strings:
///
/// "Help", "Helper", "Helping", "Helicopters", "Helicoptering"
///
/// The resulting trie would look like this:
///
/// ```
///                      ┌───┐
///              ┌──────▶│ s │
///              │       └───┘
///         ┌─────────┐
///    ┌───▶│ icopter │
///    │    └─────────┘
///    │         │       ┌───┐
///    │         └──────▶│ing│
/// ┌─────┐              └───┘
/// │ Hel │
/// └─────┘              ┌────┐
///    │      ┌─────────▶│ er │
///    │      │          └────┘
///    │    ┌───┐
///    └───▶│ p │
///         └───┘
///           │          ┌─────┐
///           └─────────▶│ ing │
///                      └─────┘
/// ```
///
/// Traversing this trie is O(min(n, m)) with `n` representing the length of the
/// key being searched and `m` representing the longest matching prefix in the
/// tree.
///
/// Inserting into the trie is also O(n) with the length of the key being
/// inserted.
public struct PrefixTrie<Payload> {
  final class Node {
    /// The result of querying the trie for a given string. This represents the
    /// kind and length of the match.
    enum QueryResult: Equatable {
      /// The exact string queried was found in the trie.
      case same

      /// The query string is a prefix of the nodes in the trie; there are still
      /// unconsumed characters in the matching node's label.
      case stringIsPrefix

      /// The label of the queried node is a prefix of the string; there are
      /// still characters left in the query string that have yet to be
      /// matched.
      case labelIsPrefix

      /// The strings do not match at all.
      case dontMatch

      /// There's a common part of the string, but neither the label nor the
      /// query string were matched entirely.
      case haveCommonPart(Int)
    }

    /// The string corresponding to this hop in the trie.
    var label: Substring

    /// The data associated with this node, if any. If this is `nil`, the node
    /// is an intermediate node (or its data has been explicitly erased).
    var data: Payload?

    /// The children of this node. This array is always in sorted order by
    /// the node's `id`.
    var children = [Node]()

    /// Each node is identified in the child list by the first character in its
    /// label.
    var id: Character {
      label.first!
    }

    /// Creates a new `Node` with the given label and data.
    init(label: Substring, data: Payload?) {
      self.label = label
      self.data = data
    }

    /// Adds the provided child to the children list, maintaining the list's
    /// sort.
    func addChild(_ node: Node) {
      if children.isEmpty {
        children.append(node)
      } else {
        let index = children.lowerBound(of: node) {
          $0.id < $1.id
        }
        children.insert(node, at: index)
      }
    }

    /// Replaces the existing child for that `id` with the provided child.
    func updateChild(_ node: Node) {
      let index = children.lowerBound(of: node) {
        $0.id < $1.id
      }
      children[index] = node
    }

    /// Searches through the trie for the given string, returning the kind of
    /// match made.
    func query<S: StringProtocol>(_ s: S) -> QueryResult {
      let stringCount = s.count
      let labelCount = label.count

      // Find the length of common part.
      let leastCount = min(stringCount, labelCount)

      var index = s.startIndex
      var otherIndex = label.startIndex
      var length = 0
      while length < leastCount && s[index] == label[otherIndex] {
        s.formIndex(after: &index)
        label.formIndex(after: &otherIndex)
        length += 1
      }

      // One is prefix of another, find who is who
      if length == leastCount {
        if stringCount == labelCount {
          return .same
        } else if length == stringCount {
          return .stringIsPrefix
        } else {
          return .labelIsPrefix
        }
      } else if length == 0 {
          return .dontMatch
      } else {
        // The query string and the label have a common part, return its length.
        return .haveCommonPart(length)
      }
    }

    /// Splits the receiver into two nodes at the provided index. Doing this
    /// will turn the receiver into an intermediate node, and transfer its
    /// children to the new node.
    ///
    /// For example, if the current branch is:
    ///
    /// ```
    /// "Hel" -> "per" -> "s"
    /// ```
    ///
    /// then calling `"per".split(at: 1)` will turn the branch into:
    ///
    /// ```
    /// "Hel" -> "p" -> "er" -> "s"
    /// ```
    func split(at rawIndex: Int) {
      assert((1..<label.count).contains(rawIndex),
             "Trying to split outside the bounds of the label")

      let index = label.index(label.startIndex, offsetBy: rawIndex)
      let firstPart = label[..<index]
      let secondPart = label[index...]

      let new = Node(label: secondPart, data: data)
      new.children = children
      label = firstPart
      data = nil
      children = []
      addChild(new)
    }

    /// Searches the array for the given `id` and returns the node with that
    /// `id`, if present.
    func findChild(for id: Character) -> Node? {
      if children.isEmpty { return nil }

      let index = children.lowerBound(of: id) { $0.id < $1 }
      guard index < children.endIndex else { return nil }
      let node = children[index]
      guard node.id == id else { return nil }
      return node
    }
  }

  /// The root of the hierarchy, intentionally empty. This label is never
  /// queried.
  var root = Node(label: "", data: nil)

  /// Creates a new, empty prefix trie.
  public init() {}

  /// Searches the trie for the given query string and either returns the best
  /// matching entry or stores the provided payload into the trie.
  public subscript(_ query: String) -> Payload? {
    get {
      var current = root
      var bestMatch: Payload?
      var string = query[...]

      while true {
        let id = string.first!
        guard let existing = current.findChild(for: id) else {
          return bestMatch
        }

        switch existing.query(string) {
        case .same:
          // If we've found an exact match, return it directly.
          return existing.data
        case .labelIsPrefix:
          // If we have more of our query to consume, keep going down this path.
          string = string.dropFirst(existing.label.count)
          current = existing
          if let data = existing.data {
            // If there's data associated with this node, though, keep track of
            // it. We may end up with a later match that doesn't have associated
            // data.
            bestMatch = data
          }
        case .dontMatch:
          fatalError("Impossible because we found a child with id \(id)")
        default:
          // If we've consumed the whole query string, return the best match
          // now.
          return bestMatch
        }
      }
    }

    set {
      var current = root
      var string = query[...]

      while true {
        let id = string.first!

        guard let existing = current.findChild(for: id) else {
          current.addChild(Node(label: string, data: newValue))
          return
        }

        switch existing.query(string) {
        case .same:
          // If we've matched an entry exactly, just update its value in place.
          existing.data = newValue
          return
        case .stringIsPrefix:
          // In this case, the string we're matching is a prefix of an existing
          // string in the trie. e.g. we're trying to add "-debug-constraints"
          // when we already have "-debug-constraints-on-line" and
          // "-debug-constraints-attempt"

          // So far we have:
          //   "debug-" : <A>
          //     -> "constraints-" : <B>
          //       -> "on-line" : <C>
          //       -> "attempt" : <D>
          //
          // We need to end up with:
          //   "debug-" : <A>
          //     -> "constraints" : <B>
          //       -> "-"         : <E>
          //         -> "on-line" : <C>
          //         -> "attempt" : <D>
          //
          // In this example, we need to take the '-' from the end of B and
          // split it into its own node, and then add the existing children as a child
          // of that node.
          //

          // First, strip off the leading text of "constraints"
          let remaining = existing.label.dropFirst(string.count)

          // Create a new node for this, and give it the existing node's
          // children.
          let new = Node(label: remaining, data: existing.data)
          new.children = existing.children

          // Reset 'existing' to the common prefix, and set its data
          // accordingly.
          existing.label = string
          existing.data = newValue

          // Now remove all of 'existing's children, and replace it with this
          // hop.
          existing.children = [new]
          return
        case .dontMatch:
          fatalError("Impossible because we found a child with id \(id)")
        case .labelIsPrefix:
          // If we've matched an entry along the way, remove it from the
          // beginning of our query and continue down this path.
          string = string.dropFirst(existing.label.count)
          current = existing
        case .haveCommonPart(let length):
          // If the existing node has some in common with our node, we need
          // to split the existing node at the common point, then add the
          // remaining characters as a child of that node.
          existing.split(at: length)
          let new = Node(label: string.dropFirst(length), data: newValue)
          existing.addChild(new)
          return
        }
      }
    }
  }

  public var nodeCount: Int {
    var count = 1
    var queue = [root]
    while !queue.isEmpty {
      let node = queue.popLast()!
      queue += node.children
      count += node.children.count
    }
    return count
  }

  public func printDOT() {
    let writer = Node.DOTWriter(node: root)
    writer.writeDOT()
  }
}

// MARK: - DOT generation for nodes (for debugging)

extension PrefixTrie.Node {
  class DOTWriter {
    let node: PrefixTrie.Node
    init(node: PrefixTrie.Node) {
      self.node = node
    }
    var labelCounter = [Substring: Int]()
    var nodeIDs = [ObjectIdentifier: String]()

    func id(for node: PrefixTrie.Node) -> String {
      if let id = nodeIDs[ObjectIdentifier(node)] {
        return id
      }

      let count = labelCounter[node.label, default: 0]
      labelCounter[node.label] = count + 1

      let id: String
      if count == 0 {
        id = String(node.label)
      } else {
        id = "\(node.label)_\(count)"
      }
      nodeIDs[ObjectIdentifier(node)] = id
      return id
    }

    func writeDOT() {
      print("digraph Trie {")
      var queue = [node]
      while !queue.isEmpty {
        let node = queue.popLast()!
        var str = #"  "\#(id(for: node))" [label="\#(node.label)""#
        if node.data != nil {
          str += ", style=bold"
        }
        str += "]"
        print(str)
        for child in node.children {
          print(#"  "\#(id(for: node))" -> "\#(id(for: child))""#)
          queue.insert(child, at: 0)
        }
      }
      print("}")
    }
  }
}

extension Array {
  /// A naïve implementation of `std::lower_bound` for Array.
  /// Returns the index before the first element in the list that is ordered
  /// after the given `value`, as determined by the provided predicate.
  func lowerBound<T>(of value: T, isOrderedBefore: (Element, T) -> Bool) -> Int {
    var count = self.count
    var index = startIndex
    var first = startIndex
    var step = 0
    while count > 0 {
      index = first
      step = count / 2
      index += step
      if isOrderedBefore(self[index], value) {
        index += 1
        first = index
        count -= step + 1
      } else {
        count = step
      }
    }
    return first
  }
}
