//===--------------- SynchronizedQueue.swift - Incremental ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

@_spi(Testing) public struct SynchronizedQueue<Element> {
  private var queue = ArraySlice<Element>()
  private var _isOpen = true
  private let lock = DispatchSemaphore(value: 1)
  private let occupancy = DispatchSemaphore(value: 0)

  private func synchronize<T>(_ fn: () -> T) -> T {
    defer {lock.signal()}
    lock.wait()
    return fn()
  }

  mutating func append(_ e: Element) {
    append(contentsOf: [e])
  }
  mutating func append<Elements: Collection>(contentsOf elements: Elements)
  where Elements.Element == Element
  {
    synchronize {
      queue.append(contentsOf: elements)
      elements.indices.forEach{ _ in  occupancy.signal() }
    }
  }
  var isEmpty: Bool {
    synchronize {queue.isEmpty}
  }
  mutating func removeFirst() -> Element? {
    synchronize {
      if !_isOpen { return nil }
      occupancy.wait()
      return queue.removeFirst()
    }
  }
  mutating func removeAll() ->  [Element]? {
    occupancy.wait()
    return synchronize {
      if !_isOpen && queue.isEmpty { return nil }
      let r = Array(queue)
      (1 ..< r.count) .forEach { _ in occupancy.wait() }
      queue.removeAll()
      return r
    }
  }
  var isOpen: Bool {
    synchronize {_isOpen}
  }
  mutating func close() {
    synchronize {_isOpen = false}; occupancy.signal()
  }
}
