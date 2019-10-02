import XCTest

import SwiftDriver
import TSCBasic

final class TripleTests: XCTestCase {
  func testBasics() throws {
    XCTAssertEqual(Triple("").arch, .unknown)
    XCTAssertEqual(Triple("kalimba").arch, .kalimba)
    XCTAssertEqual(Triple("x86_64-apple-macosx").arch, .x86_64)
    XCTAssertEqual(Triple("blah-apple").arch, .unknown)
    XCTAssertEqual(Triple("x86_64-apple-macosx").vendor, .apple)
    XCTAssertEqual(Triple("x86_64-apple-macosx").os, .macosx)
    XCTAssertEqual(Triple("x86_64-apple-macosx-macabi").environment, .macabi)
    XCTAssertEqual(Triple("x86_64-apple-macosx-macabixxmacho").objectFormat, .macho)
    XCTAssertEqual(Triple("mipsn32").environment, .gnuabin32)

    XCTAssertEqual(Triple("x86_64-unknown-mylinux").osName(), "mylinux")
    XCTAssertEqual(Triple("x86_64-unknown-mylinux-abi").osName(), "mylinux")
    XCTAssertEqual(Triple("x86_64-unknown").osName(), "")

    XCTAssertTrue(Triple("x86_64-apple-macosx10.13").osVersion() == (10, 13, 0))
    XCTAssertTrue(Triple("x86_64-apple-macosx1x.13").osVersion() == (0, 13, 0))
    XCTAssertTrue(Triple("x86_64-apple-macosx10.13.5-abi").osVersion() == (10, 13, 5))
  }
}

func ==<T: Equatable>(lhs: (T, T, T), rhs: (T, T, T)) -> Bool {
  return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
}
