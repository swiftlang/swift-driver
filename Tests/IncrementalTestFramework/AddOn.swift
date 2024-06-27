//===------------------ AddOn.swift - Swift Testing -----------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// An `AddOn` allows for extra code to be added to file to test what is compiled then.
/// The syntax is  `//# <identifier>` where the `<identifier>` is replaced by some word.
/// (There must be exactly one space after the '#')
/// For example the line `var gazorp //# initGazorp = 17`
/// will normally be compiled as written. But if the `Step` includes `initGazorp` in its `addOns`
/// the line passed to the compiler will be `var gazorp  = 17`
public struct AddOn {
  /// The name of the `AddOn`. That is, the identifier in the above description.
  public let name: String

  init(named name: String) {
    self.name = name
  }

  /// Adjust a string to reflect the effect of this `AddOn`.
  func adjust(_ s: String) -> String {
    s.replacingOccurrences(of: "//# \(name)", with: "")
  }
}

extension Array where Element == AddOn {
  func adjust(_ source: String) -> String {
    reduce(source) {adjusted, addOn in addOn.adjust(adjusted)}
  }
}
