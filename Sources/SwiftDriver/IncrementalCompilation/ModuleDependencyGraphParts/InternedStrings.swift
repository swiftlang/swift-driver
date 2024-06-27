//===------------------ InteredStrings.swift ------------------------------===//
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

import class Dispatch.DispatchQueue

public protocol InternedStringTableHolder {
  var internedStringTable: InternedStringTable {get}
}

public struct InternedString: CustomStringConvertible, Equatable, Hashable {

  let index: Int

  fileprivate init(_ s: String, _ table: InternedStringTable) {
    self.init(index: s.isEmpty ? 0 : table.intern(s))
  }

  private init(index: Int) {
    self.index = index
  }

  public var isEmpty: Bool { index == 0 }

  public static var empty: Self {
    let r = Self(index: 0)
    assert(r.isEmpty)
    return r
  }

  public func lookup(in holder: InternedStringTableHolder) -> String {
    holder.internedStringTable.strings[index]
  }

  public var description: String { "<<\(index)>>" }

  public func description(in holder: InternedStringTableHolder) -> String {
    "\(lookup(in: holder))\(description)"
  }
}

/// Like `<`, but refers to the looked-up strings.
public func isInIncreasingOrder(
  _ lhs: InternedString, _ rhs: InternedString,
  in holder: InternedStringTableHolder
) -> Bool {
  lhs.lookup(in: holder) < rhs.lookup(in: holder)
}

/// Hardcode empty as 0
public class InternedStringTable: IncrementalCompilationSynchronizer {
  /// Ensure accesses & mutations are thread-safe
  public let incrementalCompilationQueue: DispatchQueue

  var strings = [""]
  fileprivate var indices = ["": 0]

  public init(_ incrementalCompilationQueue: DispatchQueue) {
    self.incrementalCompilationQueue = incrementalCompilationQueue
  }

  fileprivate func intern(_ s: String) -> Int {
    mutationSafetyPrecondition()
    if let i = indices[s] { return i }
    let i = strings.count
    strings.append(s)
    indices[s] = i
    return i
  }

  var count: Int {
    accessSafetyPrecondition()
    return strings.count
  }

  func reserveCapacity(_ minimumCapacity: Int) {
    mutationSafetyPrecondition()
    strings.reserveCapacity(minimumCapacity)
    indices.reserveCapacity(minimumCapacity)
  }
}

extension InternedStringTable: InternedStringTableHolder {
  public var internedStringTable: InternedStringTable {self}

}

public extension StringProtocol {
  func intern(in holder: InternedStringTableHolder) -> InternedString {
    InternedString(String(self), holder.internedStringTable)
  }
}
